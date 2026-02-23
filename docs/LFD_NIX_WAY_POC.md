# LFD Nix-Way POC Plan

Date: 2026-02-23

This document captures the initial architecture and ticket contract for CSF/LFD parity work in `nix-csf`.

## Design Principles

- Keep `nix-csf` as the single firewall writer (`nftables` state authority).
- Keep detector components separate from firewall rendering.
- Preserve declarative Nix config while allowing controlled runtime state in dedicated data paths.
- Support strict enable/disable toggles for dynamic detection features.

## Ticket Set

## `T-028` Legacy CSF list import bridge

Goal:

- import operational data from `csf.allow`, `csf.deny`, `csf.ignore` into `nix-csf` local overlays.

Scope:

- parser/bridge for legacy file ingestion,
- unsupported-line reporting for CSF advanced expressions (for example `tcp|in|...`),
- migration runbook examples.

Acceptance:

- CIDR/IP entries are imported deterministically,
- unsupported entries are reported with line numbers and conversion hints,
- no hidden mutation of declarative Nix options.

Status:

- done (2026-02-23) via `nix-csf-import-csf` and `docs/CSF_IMPORT.md`.

## `T-029` LFD-like detector POC (Nix-native)

Goal:

- provide optional brute-force/login-failure detection similar in effect to LFD.

Scope:

- detector service (starting with `sshd` signal path),
- temp bans emitted via `nix-csfctl ban-temp` (not direct nft writes),
- optional escalation into permanent deny using existing control-plane policy path,
- explicit `enable` toggle and threshold options.

Acceptance:

- turning the feature off removes detector writes,
- turning it on produces temp bans visible in dynamic offender snapshots and nft timeout sets after refresh,
- logs/metrics expose detector actions and escalation decisions.

Status:

- done (2026-02-23) via `services.nixCsf.lfdDetector.*`, `scripts/nix-csf-lfd-detector.sh`,
  integration coverage, and `docs/LFD_DETECTOR.md`.

## `T-030` fail2ban adapter/coexistence

Goal:

- allow fail2ban to be used as detector while `nix-csf` remains firewall authority.

Scope:

- action template/script for fail2ban -> `nix-csfctl` handoff,
- reference fail2ban jail config snippets,
- coexistence tests and documentation.

Acceptance:

- fail2ban can trigger temp bans without writing independent nft chains/rules,
- conflicts with Docker/coexistence profiles are avoided by single-writer contract,
- adapter can be enabled/disabled independently.

Status:

- done (2026-02-23) via `services.nixCsf.fail2banAdapter.*`,
  `scripts/nix-csf-fail2ban-action.sh`, integration coverage, and `docs/FAIL2BAN_ADAPTER.md`.

## Cluster Propagation Path

Preferred dynamic path:

1. detector (lfd-like or fail2ban adapter) emits temp ban,
2. local control-plane records snapshot update,
3. nodes pull dynamic snapshot via `dynamicOffenders.url`,
4. `nix-csf-refresh` applies timeout sets.

This preserves one dynamic distribution mechanism for both local and cluster modes.
