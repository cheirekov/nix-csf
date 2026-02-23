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
- Feed reliability hotfix: Spamhaus endpoint refresh + parser compatibility for annotated/ipset feeds (`T-027`). [done 2026-02-20]

## Phase 2 — CSF-style policy expansion

- Country policy modes (`deny` and optional `allow`). [done 2026-02-19]
- Per-port country controls (deny mode / `CC_DENY_PORTS` style). [done 2026-02-19]
- Stateful rate-limit presets (SYN flood, connection flood). [done 2026-02-19]
- Preset threat profiles (server, workstation, edge node). [done 2026-02-20]
- Country allow-by-port controls (`CC_ALLOW_PORTS` parity). [done 2026-02-22]
- ICMP policy profiles (type/rate controls). [done 2026-02-21]

## Phase 3 — Operations maturity

- Structured logs and drop telemetry. [baseline done 2026-02-19]
- Optional Prometheus textfile metrics. [baseline done 2026-02-19]
- Cluster policy propagation model. [baseline done 2026-02-19]
- Cluster policy schema v2 (`allow`/`deny`/`ignore`, revision/TTL). [done 2026-02-20]
- Operator use-case catalog and deployment examples. [baseline done 2026-02-19]
- Dynamic offender propagation across cluster nodes. [baseline done 2026-02-20]
- Firewall coexistence profile (Docker/other dynamic firewall daemons). [done 2026-02-20]
- Hybrid local-files + remote-cluster list reconciliation.
- Legacy CSF list migration bridge (`csf.allow`, `csf.deny`, `csf.ignore`) with unsupported-entry reporting. [done 2026-02-23]
- LFD-like detector service (Nix-native) feeding dynamic offenders/control-plane APIs. [done 2026-02-23]
- fail2ban coexistence adapter (fail2ban detection -> `nix-csfctl` write path).
- Cluster control-plane and snapshot publisher POC (`T-024`). [done 2026-02-20]
- `nix-csfctl` operator write-path POC for cluster allow/deny/ignore (`T-025`). [done 2026-02-20]
- Dynamic escalation policy POC (`T-026`: N temporary bans => permanent deny promotion). [done 2026-02-20]
- Cluster auth/token lifecycle and secret-management guidance. [done 2026-02-20]
- Grafana/Prometheus monitoring pack and alert rules. [done 2026-02-20]
- Netdata monitoring integration (optional story on top of Prometheus/textfile metrics).
- Troubleshooting command set and runbook. [done 2026-02-23]

## Phase 4 — Release quality

- Integration tests with NixOS VMs. [baseline done 2026-02-19]
- SemVer and compatibility policy. [baseline done 2026-02-19]
- Release automation and module versioning. [baseline done 2026-02-19]
- Publish first stable release.
