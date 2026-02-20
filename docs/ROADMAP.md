# Roadmap

## Phase 0 — Kickoff (done)

- Repository scaffold.
- Flake + non-flake module entrypoints.
- Baseline module (`services.nixCsf`) with:
  - static allow/deny CIDRs,
  - open TCP/UDP ports,
  - ICMP control,
  - country deny feeds,
  - external blocklist feeds,
  - boot apply + scheduled refresh.

## Phase 1 — Safety hardening

- Validation lane (`nix flake check` and smoke profile). [done 2026-02-19]
- Clear failure semantics for feed outages.
- Safer defaults and improved assertions.
- Blocklist source governance catalog + schema. [done 2026-02-19]

## Phase 2 — CSF-style policy expansion

- Country policy modes (`deny` and optional `allow`). [done 2026-02-19]
- Per-port country controls (deny mode / `CC_DENY_PORTS` style). [done 2026-02-19]
- Stateful rate-limit presets (SYN flood, connection flood). [done 2026-02-19]
- Preset threat profiles (server, workstation, edge node). [done 2026-02-20]
- Country allow-by-port controls (`CC_ALLOW_PORTS` parity).
- ICMP policy profiles (type/rate controls).

## Phase 3 — Operations maturity

- Structured logs and drop telemetry. [baseline done 2026-02-19]
- Optional Prometheus textfile metrics. [baseline done 2026-02-19]
- Cluster policy propagation model. [baseline done 2026-02-19]
- Operator use-case catalog and deployment examples. [baseline done 2026-02-19]
- Cluster policy schema v2 (`allow`/`deny`/`ignore`, revision/TTL/signing).
- Dynamic offender propagation across cluster nodes.
- Cluster auth/token lifecycle and secret-management guidance.
- Grafana/Prometheus monitoring pack and alert rules.
- Troubleshooting command set and runbook.

## Phase 4 — Release quality

- Integration tests with NixOS VMs. [baseline done 2026-02-19]
- SemVer and compatibility policy. [baseline done 2026-02-19]
- Release automation and module versioning. [baseline done 2026-02-19]
- Publish first stable release.
