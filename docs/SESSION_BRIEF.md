# Session Brief

Last updated: 2026-02-20  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-019` (Grafana/Prometheus monitoring pack).
- Goal: ship an operator-ready monitoring bundle (dashboard + alert rules + runbook) aligned with existing `nix_csf_*` metrics.
- In scope:
  - deliver Grafana dashboard JSON for `nix-csf` health and capacity views,
  - deliver Prometheus alert rules for staleness, cache expiry, auth fallback, and performance,
  - deliver monitoring runbook with NixOS wiring examples,
  - add validation checks for monitoring assets in flake/validate pipeline,
  - triage optional Netdata story and register it as a backlog ticket.
- Out of scope:
  - ICMP per-type/per-rate controls (`T-017`),
  - country allow-by-port parity (`T-018`),
  - hybrid local-file + remote list reconciliation (`T-022`).
- Stop/rollback condition:
  - any alert/dashboard asset that cannot be validated deterministically in CI checks.

## 2) Definition of done

- Monitoring assets exist in-repo with stable file paths.
- Prometheus alert rules are parse-validated.
- Grafana dashboard JSON is parse/shape validated.
- Validation pipeline includes dedicated monitoring checks.
- Documentation (README/use-cases/architecture/monitoring doc) references and explains the pack.
- Delivery board, session brief, changelog, and roadmap are updated.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - closed `T-019`:
    - added monitoring assets:
      - `docs/monitoring/prometheus-alert-rules.yml`,
      - `docs/monitoring/grafana-dashboard.json`,
      - `docs/MONITORING.md`,
    - alert coverage includes:
      - refresh staleness,
      - cluster policy cache expiry,
      - dynamic snapshot cache expiry,
      - dynamic-ban cardinality spike,
      - auth fallback slot activity,
      - elevated refresh duration,
    - added monitoring validation checks in `flake.nix`:
      - `checks.<system>.eval-monitoring`,
      - `checks.<system>.monitoring-pack`,
    - extended `scripts/validate.sh` to include monitoring checks before VM tests,
    - updated docs:
      - README, architecture, use-case catalog, roadmap, and dynamic cluster POC.
  - triaged and registered optional Netdata story:
    - `T-023` (Netdata monitoring integration) added to delivery board and roadmap.
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-monitoring" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.monitoring-pack" --print-build-logs`
  - `./scripts/validate.sh`
- Next ticket candidate:
  - `T-017` ICMP policy profiles, then `T-018`.
