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

## Phase 2 — CSF-style policy expansion

- Country policy modes (`deny` and optional `allow`).
- Per-port country controls.
- Preset threat profiles (server, workstation, edge node).

## Phase 3 — Operations maturity

- Structured logs and drop telemetry.
- Optional Prometheus textfile metrics.
- Troubleshooting command set and runbook.

## Phase 4 — Release quality

- Integration tests with NixOS VMs.
- SemVer and compatibility policy.
- Publish first stable release.
