#!/usr/bin/env python3
"""nix-csf control-plane POC service.

This service keeps mutable cluster state in a runtime data directory,
publishes cluster/dynamic snapshots, and exposes authenticated mutation endpoints.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


def default_state() -> dict[str, Any]:
    return {
        "policyRevision": 0,
        "dynamicRevision": 0,
        "policy": {
            "allowIPv4": [],
            "allowIPv6": [],
            "denyIPv4": [],
            "denyIPv6": [],
            "ignoreIPv4": [],
            "ignoreIPv6": [],
        },
        "dynamic": {
            "entries": [],
        },
        "escalation": {
            "eventHistory": {},
            "cooldownUntil": {},
            "nextPromotionId": 1,
            "promotions": [],
        },
    }


def normalize_cidr(raw_value: str) -> tuple[str, str]:
    network = ipaddress.ip_network(raw_value, strict=False)
    normalized = str(network)
    family = "ipv4" if network.version == 4 else "ipv6"
    return normalized, family


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, indent=2)
        handle.write("\n")
    os.replace(tmp_path, path)


class StateStore:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir
        self.state_file = data_dir / "state.json"
        self._lock = threading.RLock()
        self._state = self._load_or_init()

    def _load_or_init(self) -> dict[str, Any]:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if not self.state_file.exists():
            state = default_state()
            atomic_write_json(self.state_file, state)
            return state

        with self.state_file.open("r", encoding="utf-8") as handle:
            try:
                loaded = json.load(handle)
            except json.JSONDecodeError as err:
                raise RuntimeError(f"invalid state file JSON: {self.state_file}: {err}") from err

        if not isinstance(loaded, dict):
            raise RuntimeError(f"state file must be a JSON object: {self.state_file}")

        state = default_state()
        state["policyRevision"] = int(loaded.get("policyRevision", 0))
        state["dynamicRevision"] = int(loaded.get("dynamicRevision", 0))

        policy = loaded.get("policy", {}) if isinstance(loaded.get("policy", {}), dict) else {}
        for key in state["policy"].keys():
            value = policy.get(key, [])
            if isinstance(value, list):
                state["policy"][key] = [str(item) for item in value if isinstance(item, str)]

        dynamic = loaded.get("dynamic", {}) if isinstance(loaded.get("dynamic", {}), dict) else {}
        entries = dynamic.get("entries", [])
        if isinstance(entries, list):
            sanitized_entries: list[dict[str, Any]] = []
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                cidr = entry.get("cidr")
                family = entry.get("family")
                expires_at = entry.get("expiresAt")
                reason = entry.get("reason")
                if not isinstance(cidr, str) or family not in ("ipv4", "ipv6"):
                    continue
                if not isinstance(expires_at, int):
                    continue
                if reason is not None and not isinstance(reason, str):
                    reason = None
                sanitized_entries.append(
                    {
                        "cidr": cidr,
                        "family": family,
                        "expiresAt": expires_at,
                        "reason": reason,
                    }
                )
            state["dynamic"]["entries"] = sanitized_entries

        escalation = loaded.get("escalation", {}) if isinstance(loaded.get("escalation", {}), dict) else {}
        event_history = escalation.get("eventHistory", {})
        if isinstance(event_history, dict):
            sanitized_history: dict[str, list[int]] = {}
            for key, values in event_history.items():
                if not isinstance(key, str) or "|" not in key or not isinstance(values, list):
                    continue
                normalized_values = [value for value in values if isinstance(value, int)]
                if normalized_values:
                    sanitized_history[key] = sorted(normalized_values)
            state["escalation"]["eventHistory"] = sanitized_history

        cooldown_until = escalation.get("cooldownUntil", {})
        if isinstance(cooldown_until, dict):
            sanitized_cooldown: dict[str, int] = {}
            for key, value in cooldown_until.items():
                if not isinstance(key, str) or "|" not in key:
                    continue
                if not isinstance(value, int):
                    continue
                if value > 0:
                    sanitized_cooldown[key] = value
            state["escalation"]["cooldownUntil"] = sanitized_cooldown

        promotions = escalation.get("promotions", [])
        if isinstance(promotions, list):
            sanitized_promotions: list[dict[str, Any]] = []
            next_promotion_id = 1
            for entry in promotions:
                if not isinstance(entry, dict):
                    continue
                promotion_id = entry.get("id")
                cidr = entry.get("cidr")
                family = entry.get("family")
                first_seen = entry.get("firstSeen")
                last_seen = entry.get("lastSeen")
                event_count = entry.get("eventCountWindow")
                promoted_at = entry.get("promotedAt")
                promoted_by = entry.get("promotedBy")
                reason = entry.get("reason")
                reason_class = entry.get("reasonClass")
                cooldown_seconds = entry.get("cooldownSeconds", 0)
                cooldown_until_value = entry.get("cooldownUntil", 0)
                if not isinstance(cidr, str) or family not in ("ipv4", "ipv6"):
                    continue
                if not isinstance(first_seen, int) or not isinstance(last_seen, int):
                    continue
                if not isinstance(event_count, int) or event_count <= 0:
                    continue
                if not isinstance(promoted_at, int):
                    continue
                if not isinstance(promoted_by, str):
                    continue
                if promotion_id is not None and (not isinstance(promotion_id, int) or promotion_id <= 0):
                    continue
                if reason is not None and not isinstance(reason, str):
                    reason = None
                if reason_class is not None and not isinstance(reason_class, str):
                    reason_class = None
                if not isinstance(cooldown_seconds, int) or cooldown_seconds < 0:
                    cooldown_seconds = 0
                if not isinstance(cooldown_until_value, int) or cooldown_until_value < 0:
                    cooldown_until_value = 0
                if promotion_id is None:
                    promotion_id = next_promotion_id
                sanitized_entry: dict[str, Any] = {
                    "id": promotion_id,
                    "cidr": cidr,
                    "family": family,
                    "firstSeen": first_seen,
                    "lastSeen": last_seen,
                    "eventCountWindow": event_count,
                    "promotedAt": promoted_at,
                    "promotedBy": promoted_by,
                    "cooldownSeconds": cooldown_seconds,
                    "cooldownUntil": cooldown_until_value,
                }
                if reason is not None:
                    sanitized_entry["reason"] = reason
                if reason_class is not None:
                    sanitized_entry["reasonClass"] = reason_class
                sanitized_promotions.append(sanitized_entry)
                if promotion_id >= next_promotion_id:
                    next_promotion_id = promotion_id + 1
            sanitized_promotions.sort(key=lambda item: item["id"])
            state["escalation"]["promotions"] = sanitized_promotions
            state["escalation"]["nextPromotionId"] = next_promotion_id

        next_promotion_id_loaded = escalation.get("nextPromotionId")
        if isinstance(next_promotion_id_loaded, int) and next_promotion_id_loaded > 0:
            state["escalation"]["nextPromotionId"] = max(
                state["escalation"]["nextPromotionId"], next_promotion_id_loaded
            )

        atomic_write_json(self.state_file, state)
        return state

    def _save_locked(self) -> None:
        atomic_write_json(self.state_file, self._state)

    def _policy_key(self, list_name: str, family: str) -> str:
        suffix = "IPv4" if family == "ipv4" else "IPv6"
        return f"{list_name}{suffix}"

    def _prune_expired_locked(self, now_epoch: int) -> bool:
        entries = self._state["dynamic"]["entries"]
        kept = [entry for entry in entries if entry["expiresAt"] > now_epoch]
        if len(kept) == len(entries):
            return False

        self._state["dynamic"]["entries"] = kept
        self._state["dynamicRevision"] += 1
        self._save_locked()
        return True

    def _escalation_key(self, cidr: str, family: str) -> str:
        return f"{family}|{cidr}"

    def _reason_class(self, reason: str | None) -> str:
        if reason is None:
            return "unknown"
        value = reason.strip()
        if value == "":
            return "unknown"
        if ":" in value:
            return value.split(":", 1)[0]
        return value

    def _apply_escalation_locked(
        self,
        *,
        cidr: str,
        family: str,
        now_epoch: int,
        reason: str | None,
        enable: bool,
        threshold: int,
        window_seconds: int,
        cooldown_seconds: int,
        reason_classes: list[str],
        max_audit_entries: int,
    ) -> dict[str, Any]:
        reason_class = self._reason_class(reason)
        class_eligible = reason_classes == [] or reason_class in reason_classes

        if not enable:
            return {
                "enabled": False,
                "escalated": False,
                "eventCountWindow": 0,
                "threshold": threshold,
                "windowSeconds": window_seconds,
                "cooldownSeconds": cooldown_seconds,
                "cooldownUntil": 0,
                "cooldownActive": False,
                "reasonClass": reason_class,
                "reasonClassEligible": class_eligible,
                "reasonClasses": reason_classes,
                "promotionChanged": False,
                "dynamicChanged": False,
                "stateChanged": False,
            }

        if not class_eligible:
            return {
                "enabled": True,
                "escalated": False,
                "eventCountWindow": 0,
                "threshold": threshold,
                "windowSeconds": window_seconds,
                "cooldownSeconds": cooldown_seconds,
                "cooldownUntil": 0,
                "cooldownActive": False,
                "reasonClass": reason_class,
                "reasonClassEligible": False,
                "reasonClasses": reason_classes,
                "promotionChanged": False,
                "dynamicChanged": False,
                "stateChanged": False,
            }

        key = self._escalation_key(cidr, family)
        history = self._state["escalation"]["eventHistory"]
        cooldown_map: dict[str, int] = self._state["escalation"]["cooldownUntil"]
        existing = history.get(key, [])
        keep_after = now_epoch - window_seconds
        filtered = [value for value in existing if value >= keep_after]
        filtered.append(now_epoch)
        filtered.sort()
        history[key] = filtered

        event_count = len(filtered)
        cooldown_until = cooldown_map.get(key, 0)
        if not isinstance(cooldown_until, int) or cooldown_until < 0:
            cooldown_until = 0
        cooldown_active = cooldown_until > now_epoch
        escalated = event_count >= threshold and not cooldown_active
        promotion_changed = False
        dynamic_changed = False

        if escalated:
            deny_key = self._policy_key("deny", family)
            deny_entries: list[str] = self._state["policy"][deny_key]
            if cidr not in deny_entries:
                deny_entries.append(cidr)
                deny_entries.sort()
                self._state["policyRevision"] += 1
                promotion_changed = True

            dynamic_entries: list[dict[str, Any]] = self._state["dynamic"]["entries"]
            kept_dynamic = [
                entry for entry in dynamic_entries
                if not (entry["cidr"] == cidr and entry["family"] == family)
            ]
            if len(kept_dynamic) != len(dynamic_entries):
                self._state["dynamic"]["entries"] = kept_dynamic
                dynamic_changed = True

            if promotion_changed:
                promotions: list[dict[str, Any]] = self._state["escalation"]["promotions"]
                promotion_id = self._state["escalation"]["nextPromotionId"]
                self._state["escalation"]["nextPromotionId"] += 1
                next_cooldown_until = now_epoch + cooldown_seconds if cooldown_seconds > 0 else 0
                promotion_record: dict[str, Any] = {
                    "id": promotion_id,
                    "cidr": cidr,
                    "family": family,
                    "firstSeen": filtered[0],
                    "lastSeen": filtered[-1],
                    "eventCountWindow": event_count,
                    "promotedAt": now_epoch,
                    "promotedBy": "auto-escalation",
                    "reasonClass": reason_class,
                    "cooldownSeconds": cooldown_seconds,
                    "cooldownUntil": next_cooldown_until,
                }
                if reason is not None:
                    promotion_record["reason"] = reason
                promotions.append(promotion_record)
                if len(promotions) > max_audit_entries:
                    del promotions[0 : len(promotions) - max_audit_entries]
                if cooldown_seconds > 0:
                    cooldown_map[key] = next_cooldown_until
                    cooldown_until = next_cooldown_until
                elif key in cooldown_map:
                    del cooldown_map[key]
                    cooldown_until = 0

            # Reset the rolling history after promotion to avoid repeated promotions
            # from the same burst window.
            history[key] = []

        return {
            "enabled": True,
            "escalated": escalated,
            "eventCountWindow": event_count,
            "threshold": threshold,
            "windowSeconds": window_seconds,
            "cooldownSeconds": cooldown_seconds,
            "cooldownUntil": cooldown_until,
            "cooldownActive": cooldown_active,
            "reasonClass": reason_class,
            "reasonClassEligible": class_eligible,
            "reasonClasses": reason_classes,
            "promotionChanged": promotion_changed,
            "dynamicChanged": dynamic_changed,
            "stateChanged": True,
        }

    def add_policy(self, list_name: str, cidr: str) -> dict[str, Any]:
        normalized, family = normalize_cidr(cidr)
        key = self._policy_key(list_name, family)

        with self._lock:
            entries = self._state["policy"][key]
            changed = False
            if normalized not in entries:
                entries.append(normalized)
                entries.sort()
                self._state["policyRevision"] += 1
                self._save_locked()
                changed = True

            return {
                "changed": changed,
                "cidr": normalized,
                "family": family,
                "policyRevision": self._state["policyRevision"],
            }

    def remove_policy(self, list_name: str, cidr: str) -> dict[str, Any]:
        normalized, family = normalize_cidr(cidr)
        key = self._policy_key(list_name, family)

        with self._lock:
            entries = self._state["policy"][key]
            changed = False
            if normalized in entries:
                entries.remove(normalized)
                self._state["policyRevision"] += 1
                self._save_locked()
                changed = True

            return {
                "changed": changed,
                "cidr": normalized,
                "family": family,
                "policyRevision": self._state["policyRevision"],
            }

    def ban_temp(
        self,
        cidr: str,
        ttl_seconds: int,
        reason: str | None,
        *,
        escalation_enable: bool,
        escalation_threshold: int,
        escalation_window_seconds: int,
        escalation_cooldown_seconds: int,
        escalation_reason_classes: list[str],
        escalation_max_audit_entries: int,
    ) -> dict[str, Any]:
        normalized, family = normalize_cidr(cidr)
        now_epoch = int(time.time())
        expires_at = now_epoch + ttl_seconds

        with self._lock:
            self._prune_expired_locked(now_epoch)

            entries: list[dict[str, Any]] = self._state["dynamic"]["entries"]
            changed = False
            for entry in entries:
                if entry["cidr"] == normalized and entry["family"] == family:
                    if expires_at > entry["expiresAt"]:
                        entry["expiresAt"] = expires_at
                        changed = True
                    if reason is not None and reason != entry.get("reason"):
                        entry["reason"] = reason
                        changed = True
                    break
            else:
                entries.append(
                    {
                        "cidr": normalized,
                        "family": family,
                        "expiresAt": expires_at,
                        "reason": reason,
                    }
                )
                changed = True

            escalation_result = self._apply_escalation_locked(
                cidr=normalized,
                family=family,
                now_epoch=now_epoch,
                reason=reason,
                enable=escalation_enable,
                threshold=escalation_threshold,
                window_seconds=escalation_window_seconds,
                cooldown_seconds=escalation_cooldown_seconds,
                reason_classes=escalation_reason_classes,
                max_audit_entries=escalation_max_audit_entries,
            )

            needs_save = changed or escalation_result["stateChanged"]
            if needs_save:
                if changed or escalation_result["dynamicChanged"]:
                    self._state["dynamicRevision"] += 1
                self._state["dynamic"]["entries"].sort(
                    key=lambda item: (item["family"], item["cidr"])
                )
                self._save_locked()

            return {
                "changed": changed,
                "cidr": normalized,
                "family": family,
                "expiresAt": expires_at,
                "dynamicRevision": self._state["dynamicRevision"],
                "escalation": escalation_result,
            }

    def unban(self, cidr: str) -> dict[str, Any]:
        normalized, family = normalize_cidr(cidr)
        with self._lock:
            entries: list[dict[str, Any]] = self._state["dynamic"]["entries"]
            kept = [entry for entry in entries if not (entry["cidr"] == normalized and entry["family"] == family)]
            changed = len(kept) != len(entries)
            if changed:
                self._state["dynamic"]["entries"] = kept
                self._state["dynamicRevision"] += 1
                self._save_locked()

            return {
                "changed": changed,
                "cidr": normalized,
                "family": family,
                "dynamicRevision": self._state["dynamicRevision"],
            }

    def snapshots(self, env_name: str, cluster_ttl: int, dynamic_ttl: int) -> tuple[dict[str, Any], dict[str, Any]]:
        now_epoch = int(time.time())
        with self._lock:
            self._prune_expired_locked(now_epoch)

            policy = self._state["policy"]
            policy_snapshot = {
                "schemaVersion": 2,
                "revision": f"{env_name}-policy-r{self._state['policyRevision']}",
                "ttlSeconds": cluster_ttl,
                "allowIPv4": sorted(set(policy["allowIPv4"])),
                "allowIPv6": sorted(set(policy["allowIPv6"])),
                "denyIPv4": sorted(set(policy["denyIPv4"])),
                "denyIPv6": sorted(set(policy["denyIPv6"])),
                "ignoreIPv4": sorted(set(policy["ignoreIPv4"])),
                "ignoreIPv6": sorted(set(policy["ignoreIPv6"])),
            }

            ban_ipv4: list[dict[str, Any]] = []
            ban_ipv6: list[dict[str, Any]] = []
            for entry in sorted(self._state["dynamic"]["entries"], key=lambda item: (item["family"], item["cidr"])):
                rendered_entry: dict[str, Any] = {
                    "cidr": entry["cidr"],
                    "expiresAt": entry["expiresAt"],
                }
                if entry.get("reason"):
                    rendered_entry["reason"] = entry["reason"]
                if entry["family"] == "ipv4":
                    ban_ipv4.append(rendered_entry)
                else:
                    ban_ipv6.append(rendered_entry)

            dynamic_snapshot = {
                "schemaVersion": 1,
                "revision": f"{env_name}-dyn-r{self._state['dynamicRevision']}",
                "ttlSeconds": dynamic_ttl,
                "banIPv4": ban_ipv4,
                "banIPv6": ban_ipv6,
            }

            return policy_snapshot, dynamic_snapshot

    def promotion_audit(self, limit: int = 200) -> list[dict[str, Any]]:
        with self._lock:
            promotions: list[dict[str, Any]] = self._state["escalation"]["promotions"]
            if limit <= 0:
                return []
            selected = promotions[-limit:]
            return [dict(item) for item in selected]


class ControlPlaneServer(ThreadingHTTPServer):
    def __init__(
        self,
        bind: tuple[str, int],
        handler_cls: type[BaseHTTPRequestHandler],
        *,
        store: StateStore,
        env_name: str,
        cluster_snapshot_ttl: int,
        dynamic_snapshot_ttl: int,
        default_ban_ttl: int,
        escalation_enable: bool,
        escalation_threshold: int,
        escalation_window_seconds: int,
        escalation_cooldown_seconds: int,
        escalation_reason_classes: list[str],
        escalation_max_audit_entries: int,
        require_auth: bool,
        auth_token_file: str | None,
    ) -> None:
        super().__init__(bind, handler_cls)
        self.store = store
        self.env_name = env_name
        self.cluster_snapshot_ttl = cluster_snapshot_ttl
        self.dynamic_snapshot_ttl = dynamic_snapshot_ttl
        self.default_ban_ttl = default_ban_ttl
        self.escalation_enable = escalation_enable
        self.escalation_threshold = escalation_threshold
        self.escalation_window_seconds = escalation_window_seconds
        self.escalation_cooldown_seconds = escalation_cooldown_seconds
        self.escalation_reason_classes = escalation_reason_classes
        self.escalation_max_audit_entries = escalation_max_audit_entries
        self.require_auth = require_auth
        self.auth_token_file = auth_token_file

    def read_token(self) -> str | None:
        if self.auth_token_file is None:
            return None

        token_path = Path(self.auth_token_file)
        if not token_path.exists() or not token_path.is_file():
            return None

        raw = token_path.read_text(encoding="utf-8")
        token = raw.strip()
        if not token or any(ch.isspace() for ch in token):
            return None
        return token


class Handler(BaseHTTPRequestHandler):
    server: ControlPlaneServer

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length <= 0:
            return {}

        raw = self.rfile.read(content_length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as err:
            raise ValueError(f"invalid JSON body: {err}") from err

        if not isinstance(payload, dict):
            raise ValueError("request body must be a JSON object")
        return payload

    def _authorized(self) -> bool:
        if not self.server.require_auth:
            return True

        expected_token = self.server.read_token()
        if expected_token is None:
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": "auth token unavailable or invalid"},
            )
            return False

        auth_header = self.headers.get("Authorization", "")
        if auth_header != f"Bearer {expected_token}":
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return False

        return True

    def _route_parts(self) -> list[str]:
        path = self.path.split("?", 1)[0]
        return [part for part in path.split("/") if part]

    def do_GET(self) -> None:  # noqa: N802
        parts = self._route_parts()

        if parts == ["healthz"]:
            self._send_json(HTTPStatus.OK, {"status": "ok"})
            return

        if not self._authorized():
            return

        if len(parts) == 3 and parts[0] == "snapshots":
            env_name = parts[1]
            filename = parts[2]
            if env_name != self.server.env_name:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "unknown environment"})
                return

            policy_snapshot, dynamic_snapshot = self.server.store.snapshots(
                env_name=env_name,
                cluster_ttl=self.server.cluster_snapshot_ttl,
                dynamic_ttl=self.server.dynamic_snapshot_ttl,
            )
            if filename == "cluster-policy.json":
                self._send_json(HTTPStatus.OK, policy_snapshot)
                return
            if filename == "dynamic-offenders.json":
                self._send_json(HTTPStatus.OK, dynamic_snapshot)
                return

        if parts == ["v1", "escalation", "promotions"]:
            limit_raw = self.headers.get("X-Nix-Csf-Limit", "200")
            try:
                limit = int(limit_raw)
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid X-Nix-Csf-Limit"})
                return
            promotions = self.server.store.promotion_audit(limit=limit)
            self._send_json(
                HTTPStatus.OK,
                {
                    "escalation": {
                        "enabled": self.server.escalation_enable,
                        "threshold": self.server.escalation_threshold,
                        "windowSeconds": self.server.escalation_window_seconds,
                        "cooldownSeconds": self.server.escalation_cooldown_seconds,
                        "reasonClasses": self.server.escalation_reason_classes,
                    },
                    "promotions": promotions,
                },
            )
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._authorized():
            return

        parts = self._route_parts()
        try:
            payload = self._read_json_body()
        except ValueError as err:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            return

        if len(parts) == 3 and parts[0] == "v1" and parts[1] == "policy":
            action = parts[2]
            if action not in ("allow", "deny", "ignore"):
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "unknown policy list"})
                return

            cidr = payload.get("cidr")
            if not isinstance(cidr, str) or cidr == "":
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "cidr must be a non-empty string"})
                return

            try:
                result = self.server.store.add_policy(action, cidr)
            except ValueError as err:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                return

            self._send_json(HTTPStatus.OK, result)
            return

        if parts == ["v1", "offenders", "ban-temp"]:
            cidr = payload.get("cidr")
            ttl_seconds = payload.get("ttlSeconds", self.server.default_ban_ttl)
            reason = payload.get("reason")

            if not isinstance(cidr, str) or cidr == "":
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "cidr must be a non-empty string"})
                return
            if not isinstance(ttl_seconds, int) or ttl_seconds <= 0:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "ttlSeconds must be a positive integer"})
                return
            if reason is not None and not isinstance(reason, str):
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "reason must be a string when provided"})
                return

            try:
                result = self.server.store.ban_temp(
                    cidr,
                    ttl_seconds,
                    reason,
                    escalation_enable=self.server.escalation_enable,
                    escalation_threshold=self.server.escalation_threshold,
                    escalation_window_seconds=self.server.escalation_window_seconds,
                    escalation_cooldown_seconds=self.server.escalation_cooldown_seconds,
                    escalation_reason_classes=self.server.escalation_reason_classes,
                    escalation_max_audit_entries=self.server.escalation_max_audit_entries,
                )
            except ValueError as err:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                return

            self._send_json(HTTPStatus.OK, result)
            return

        if parts == ["v1", "offenders", "unban"]:
            cidr = payload.get("cidr")
            if not isinstance(cidr, str) or cidr == "":
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "cidr must be a non-empty string"})
                return

            try:
                result = self.server.store.unban(cidr)
            except ValueError as err:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                return

            self._send_json(HTTPStatus.OK, result)
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._authorized():
            return

        parts = self._route_parts()
        try:
            payload = self._read_json_body()
        except ValueError as err:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            return

        if len(parts) == 3 and parts[0] == "v1" and parts[1] == "policy":
            action = parts[2]
            if action not in ("allow", "deny", "ignore"):
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "unknown policy list"})
                return

            cidr = payload.get("cidr")
            if not isinstance(cidr, str) or cidr == "":
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "cidr must be a non-empty string"})
                return

            try:
                result = self.server.store.remove_policy(action, cidr)
            except ValueError as err:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                return

            self._send_json(HTTPStatus.OK, result)
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def log_message(self, format_string: str, *args: Any) -> None:
        message = format_string % args
        sys.stdout.write(f"nix-csf-control-plane: {self.address_string()} {self.command} {self.path} :: {message}\n")
        sys.stdout.flush()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="nix-csf control-plane POC service")
    parser.add_argument("--bind-address", default="127.0.0.1")
    parser.add_argument("--port", default=18081, type=int)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--environment", default="prod")
    parser.add_argument("--cluster-policy-ttl-seconds", default=300, type=int)
    parser.add_argument("--dynamic-snapshot-ttl-seconds", default=120, type=int)
    parser.add_argument("--default-ban-ttl-seconds", default=900, type=int)
    parser.add_argument("--escalation-enable", action="store_true")
    parser.add_argument("--escalation-threshold", default=5, type=int)
    parser.add_argument("--escalation-window-seconds", default=900, type=int)
    parser.add_argument("--escalation-cooldown-seconds", default=0, type=int)
    parser.add_argument("--escalation-reason-class", action="append", default=[])
    parser.add_argument("--escalation-max-audit-entries", default=5000, type=int)
    parser.add_argument("--require-auth", action="store_true")
    parser.add_argument("--auth-token-file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.port <= 0 or args.port > 65535:
        print("invalid --port value", file=sys.stderr)
        return 2

    if args.cluster_policy_ttl_seconds <= 0:
        print("--cluster-policy-ttl-seconds must be positive", file=sys.stderr)
        return 2

    if args.dynamic_snapshot_ttl_seconds <= 0:
        print("--dynamic-snapshot-ttl-seconds must be positive", file=sys.stderr)
        return 2

    if args.default_ban_ttl_seconds <= 0:
        print("--default-ban-ttl-seconds must be positive", file=sys.stderr)
        return 2

    if args.escalation_threshold <= 0:
        print("--escalation-threshold must be positive", file=sys.stderr)
        return 2

    if args.escalation_window_seconds <= 0:
        print("--escalation-window-seconds must be positive", file=sys.stderr)
        return 2

    if args.escalation_cooldown_seconds < 0:
        print("--escalation-cooldown-seconds must be zero or positive", file=sys.stderr)
        return 2

    if args.escalation_max_audit_entries <= 0:
        print("--escalation-max-audit-entries must be positive", file=sys.stderr)
        return 2

    escalation_reason_classes: list[str] = []
    for raw_value in args.escalation_reason_class:
        value = raw_value.strip()
        if value == "":
            print("--escalation-reason-class values must be non-empty", file=sys.stderr)
            return 2
        if any(ch.isspace() for ch in value):
            print("--escalation-reason-class values must not contain whitespace", file=sys.stderr)
            return 2
        if value not in escalation_reason_classes:
            escalation_reason_classes.append(value)

    data_dir = Path(args.data_dir)
    if not data_dir.is_absolute():
        print("--data-dir must be an absolute path", file=sys.stderr)
        return 2

    auth_token_file = args.auth_token_file
    if auth_token_file is not None and not os.path.isabs(auth_token_file):
        print("--auth-token-file must be an absolute path", file=sys.stderr)
        return 2

    if args.require_auth and auth_token_file is None:
        print("--require-auth requires --auth-token-file", file=sys.stderr)
        return 2

    if args.environment == "":
        print("--environment must not be empty", file=sys.stderr)
        return 2

    store = StateStore(data_dir)

    server = ControlPlaneServer(
        (args.bind_address, args.port),
        Handler,
        store=store,
        env_name=args.environment,
        cluster_snapshot_ttl=args.cluster_policy_ttl_seconds,
        dynamic_snapshot_ttl=args.dynamic_snapshot_ttl_seconds,
        default_ban_ttl=args.default_ban_ttl_seconds,
        escalation_enable=args.escalation_enable,
        escalation_threshold=args.escalation_threshold,
        escalation_window_seconds=args.escalation_window_seconds,
        escalation_cooldown_seconds=args.escalation_cooldown_seconds,
        escalation_reason_classes=escalation_reason_classes,
        escalation_max_audit_entries=args.escalation_max_audit_entries,
        require_auth=args.require_auth,
        auth_token_file=auth_token_file,
    )

    print(
        "nix-csf-control-plane: listening on "
        f"{args.bind_address}:{args.port} "
        f"env={args.environment} "
        f"data_dir={data_dir} "
        f"escalation_enabled={'true' if args.escalation_enable else 'false'} "
        f"escalation_threshold={args.escalation_threshold} "
        f"escalation_window_seconds={args.escalation_window_seconds} "
        f"escalation_cooldown_seconds={args.escalation_cooldown_seconds} "
        f"escalation_reason_classes={','.join(escalation_reason_classes)} "
        f"require_auth={'true' if args.require_auth else 'false'}"
    )
    sys.stdout.flush()

    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
