# Architecture

## Design goals

- Security-first defaults (`drop` inbound/forward by default).
- Declarative module API for NixOS users.
- Runtime feed refresh without rebuilding the system.
- Compatibility with both flake and non-flake module imports.
- Profile-driven onboarding (`threatProfile`) with explicit override precedence.
- Governed remote blocklist ingestion through a source catalog schema.
- Hybrid local-files + remote policy reconciliation for day-2 overrides.
- Centralized cluster policy propagation for multi-host allow/deny overlays.
- Cluster policy schema v2 governance (`allow`/`deny`/`ignore` + revision/TTL).
- Clear separation between declarative policy state and runtime dynamic offender state.
- Secret-managed auth lifecycle for remote cluster and dynamic endpoints.
- Coexistence strategy for hosts that run additional firewall mutators (for example Docker).
- Optional NAT datapath foundation for gateway hosts (`nat.*`).
- Optional forwarding matrix for zone/interface-routed traffic (`forwarding.*`).
- Operator-ready monitoring pack (Prometheus alerts + Grafana dashboards + runbook).
- Repeatable SemVer-based release lifecycle.

## Components

- `modules/nixos/nix-csf.nix`
  - NixOS module options and service wiring.
- `scripts/nix-csf-apply.sh`
  - Runtime rule compiler and loader for nftables.
- `scripts/nix-csf-control-plane.py`
  - Optional mutable-state control-plane service (PoC) for policy/dynamic snapshot publishing.
- `scripts/nix-csfctl.sh`
  - Operator CLI for authenticated control-plane mutations and promotion audit queries.
- `VERSION`
  - Single source of truth for module/project SemVer.
- `scripts/release.sh`
  - Maintainer release automation (validate, version bump, tag flow).
- `docs/monitoring/prometheus-alert-rules.yml`
  - Prometheus alert policy for nix-csf runtime health.
- `docs/monitoring/grafana-dashboard.json`
  - Grafana dashboard template for nix-csf operational visibility.
- `docs/MONITORING.md`
  - Monitoring runbook and wiring examples.
- `systemd` units
  - `nix-csf-apply.service`: early boot apply.
  - `nix-csf-refresh.service`: network-online refresh.
  - `nix-csf-refresh.timer`: periodic refresh schedule.
  - `nix-csf-control-plane.service` (optional): local/master mutable policy API + snapshot publisher.
- Runtime state
  - `/var/lib/nix-csf/cache`: cached remote feeds.
  - `/var/lib/nix-csf/cache/dynamic-offenders.json`: cached dynamic offender snapshot.
  - `/var/lib/nix-csf/generated-ruleset.nft`: last generated ruleset.
  - optional Prometheus textfile metrics output (default: `/var/lib/nix-csf/metrics.prom`).
  - `/var/lib/nix-csf-control-plane/state.json`: mutable control-plane state (outside declarative rebuild output).

## Data flow

1. Nix evaluation generates a JSON config from module options.
   Profile presets are resolved at eval-time through `mkDefault` so explicit per-host values still win.
2. Module version metadata (`services.nixCsf.moduleVersion`) is injected from `VERSION`.
3. Boot-time apply service renders nftables rules from:
   - static config values,
   - local operator-managed files (`localFiles.*`),
   - cached feed data.
4. Refresh service (manual/timer) downloads latest feed files and optional cluster policy overlay JSON.
5. Remote auth token files are loaded from secret paths, validated, and used with ordered fallback when multiple candidates are configured.
6. Cluster policy cache metadata (schema/revision/TTL) is validated before merge.
7. Dynamic offender snapshot is validated and converted into timeout-based nft sets.
8. Coexistence profile determines forward-hook ownership:
   - `exclusive-firewall`: forward policy is fully module-driven,
   - `docker-coexist`: keep forward policy `accept` and enforce deny-style overlays only.
9. Optional NAT mode renders an additional `table ip nix_csf_nat` with:
   - `prerouting` DNAT/port-forward rules,
   - `postrouting` masquerade rules for configured source CIDRs.
10. Optional forwarding matrix expands `forwarding.zones` + `forwarding.rules` into explicit
    `chain forward` accept clauses under deny-by-default (`forwardPolicy = drop`) posture.
11. Optional control-plane mode stores mutable policy/dynamic state in `controlPlane.dataDir`
   and serves snapshots consumed by standard `clusterPolicy`/`dynamicOffenders` client flow.
12. Rules are regenerated and atomically re-applied.
13. Optional observability export writes:
   - structured event logs to journald,
   - snapshot metrics in Prometheus textfile format (including build/version metadata and auth-slot telemetry).

## Security boundaries

- `networking.firewall.enable` is asserted off to avoid mixed ownership.
- nftables policy is explicit and auditable in generated output.
- Remote feeds are optional and can run `failOpen` to reduce outage risk.
- In strict mode (`failOpen = false`), `apply` requires cache presence for remote sources and fails closed when cache is absent.
- Blocklist sources can be governed by catalog IDs (`blocklists.sources`) with schema-backed metadata.
- Cluster ignore overlays can explicitly subtract CIDRs from deny-style sources.
- Local ignore overlays (`localFiles.ignore`) are merged with cluster ignore before reconciliation.
- Dynamic offender snapshots enforce schema + optional TTL cache-age guardrails.
- Dynamic snapshots are bounded by `dynamicOffenders.maxEntries` to avoid oversized runtime merges.
- Auth token files are validated at runtime for strict permissions/content before remote fetches (`authTokenFile`/`authTokenFiles`).
- Optional control-plane mutation endpoints can require bearer auth via `controlPlane.requireAuth` + `controlPlane.authTokenFile`.
- `nix-csfctl` supports the same bearer-token model via `--auth-token-file`.
- Docker coexistence mode is explicit (`coexistence.profile = "docker-coexist"`) and guarded by `forwardPolicy = "accept"` to reduce forwarding regressions.
- Stage-1 NAT guardrail: `nat.enable = true` is currently blocked with `coexistence.profile = "docker-coexist"` to avoid mixed NAT ownership.
- Stage-1 forwarding guardrails:
  - `forwarding.rules` requires `forwardPolicy = "drop"`,
  - `forwarding.rules` is blocked with `coexistence.profile = "docker-coexist"` to avoid ambiguous forward ownership.

## Centralized dynamic model

Baseline implementation now includes:

- `dynamicOffenders` remote snapshot fetch/caching,
- per-entry TTL/expiry conversion into nft timeout sets,
- strict fail-closed behavior on expired snapshots (`failOpen = false`),
- auth token rotation fallback (`authTokenFiles`) for cluster and dynamic endpoints,
- optional local/master control-plane API + snapshot publisher for mutable day-2 workflows (`controlPlane.*`),
- operator mutation workflow via `nix-csfctl` (policy add/remove, temp ban/unban, promotion audit),
- observability metrics for dynamic snapshot schema/cache-age/TTL/expiry and auth token slot selection.

See `docs/DYNAMIC_CLUSTER_POC.md` for extended roadmap recommendations:

- hybrid local-files + remote cluster list workflows,
- token lifecycle handling for cluster auth (baseline implemented with `authTokenFiles`),
- Grafana/Prometheus operational model,
- Docker and other dynamic-firewall coexistence strategy (baseline implemented via `coexistence.profile`).

For cluster write-path/control-plane POC design, see:

- `docs/CLUSTER_CONTROL_PLANE_POC.md`.
