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
- Hybrid local-files + remote-cluster list reconciliation. [done 2026-02-23]
- Legacy CSF list migration bridge (`csf.allow`, `csf.deny`, `csf.ignore`) with unsupported-entry reporting. [done 2026-02-23]
- LFD-like detector service (Nix-native) feeding dynamic offenders/control-plane APIs. [done 2026-02-23]
- fail2ban coexistence adapter (fail2ban detection -> `nix-csfctl` write path). [done 2026-02-23]
- Cluster control-plane and snapshot publisher POC (`T-024`). [done 2026-02-20]
- `nix-csfctl` operator write-path POC for cluster allow/deny/ignore (`T-025`). [done 2026-02-20]
- Dynamic escalation policy POC (`T-026`: N temporary bans => permanent deny promotion). [done 2026-02-20]
- Cluster auth/token lifecycle and secret-management guidance. [done 2026-02-20]
- Grafana/Prometheus monitoring pack and alert rules. [done 2026-02-20]
- Netdata monitoring integration (optional story on top of Prometheus/textfile metrics). [done 2026-02-23]
- Troubleshooting command set and runbook. [done 2026-02-23]

## Phase 4 — Release quality

- Integration tests with NixOS VMs. [baseline done 2026-02-19]
- SemVer and compatibility policy. [baseline done 2026-02-19]
- Release automation and module versioning. [baseline done 2026-02-19]
- Publish first stable release.

## Phase 5 — Firewall ownership expansion (new epic / Stage 1)

- Epic kickoff and staged acceptance plan (`T-039`). [done 2026-02-25]
- NAT datapath foundation (`T-040`). [done 2026-02-25]
  - scope:
  - declarative SNAT/masquerade for routed networks,
  - declarative DNAT/port-forward path,
  - explicit safety defaults (off unless enabled).
- Forwarding policy matrix (`T-041`). [done 2026-02-25]
  - interface/zone-aware forward allow model for gateway hosts.
- Optional egress controls (`T-042`). [done 2026-02-25]
  - output allowlist/denylist for hardened hosts.
- Gateway-grade test coverage (`T-047`, Stage 1 subset). [done 2026-02-25]
  - VM validation for NAT + forward + egress combinations.

## Phase 6 — Detector/escalation expansion (new epic / Stage 2)

- LFD detector framework v2 (`T-043`). [done 2026-02-25]
  - reusable multi-source signal model (not SSH-only).
- Built-in detector pack v2 (`T-044`). [done 2026-02-25]
  - SSH plus additional service-level detectors (auth/flood patterns).
- Escalation engine v2 (`T-045`). [done 2026-02-25]
  - normalized temp-ban and permanent-promotion path across sources.
- Cluster propagation semantics v2 (`T-046`). [done 2026-02-25]
  - controlled sharing for temporary and permanent actions.
- Documentation blueprints and examples (`T-048`). [done 2026-02-25]
  - deployment patterns for standalone and clustered nodes.
- Gateway/detector integration coverage (`T-047`, Stage 2 subset). [done 2026-02-25]
  - regression checks for detector->ban->propagation pipeline.

## Phase 7 — Release-candidate hardening

- Release-candidate hardening checklist (`T-049`). [done 2026-02-26]
  - VM burn-in guidance for KVM and TCG environments,
  - documentation freeze checklist,
  - pre-release validation evidence contract.

## Phase 8 — RC decision and cut readiness

- Release-candidate decision package (`T-050`). [done 2026-02-26]
  - evidence-backed RC recommendation,
  - cut checklist and rollback framing for first production tag.

## Phase 9 — Post-RC operator polish

- Optional Netdata plugin-noise cleanup profile (`T-051`). [done 2026-02-26]
  - reduce non-critical plugin warnings in default Netdata deployments,
  - preserve `nix_csf.*` chart collection behavior.

## Phase 10 — Policy authoring ergonomics

- Optional policy-as-code authoring helper (`T-052`). [done 2026-02-26]
  - `nix-csfctl policy compile` workflow for authoring and validation,
  - deterministic compile output for CI/operator review.

## Phase 11 — Production hardening extensions

- Detector pack template expansion (`T-053`). [done 2026-02-26]
  - added curated templates for additional auth-facing services.
- BIND production blueprint and secure cluster/CI workflow (`T-054`). [done 2026-02-26]
  - authoritative DNS production pattern and CI temporary access model.
- DNS flood controls v1 (`T-055`). [done 2026-02-26]
  - DNS-port-specific UDP/TCP meters with trusted-source bypass selectors.
- Cluster/API auth-failure detector templates (`T-056`). [done 2026-02-26]
  - detector-pack templates for control-plane and API proxy auth failures.
- Security validation and pen-test runbook (`T-057`). [done 2026-02-26]
  - reproducible ingress/flood/auth-abuse validation workflow for operations.
- Control-plane TLS reverse-proxy on dedicated node port (`T-058`). [done 2026-02-26]
  - secure exposure pattern for non-80/443 API endpoints.
- Cluster auth token lifecycle runbook (`T-059`). [done 2026-02-26]
  - token generation/rotation/verification workflow.
