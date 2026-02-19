# PM/BA Changelog

## 2026-02-19 — Batch KICKOFF-001

- Ticket(s): `T-000`, `T-001`
- Summary:
  - bootstrapped repository structure for a reusable NixOS firewall module,
  - implemented `services.nixCsf` baseline module,
  - added runtime apply/refresh workflow for nftables,
  - added team/process docs and delivery board.
- BA requirement mapping:
  - flake and non-flake module support,
  - CSF-inspired modern feature direction, especially country blocking.
- PM milestone mapping:
  - Phase 0 complete (`docs/ROADMAP.md`).
- Risk impact:
  - `low` (new module; no impact unless explicitly enabled by user).
- Validation evidence:
  - module evaluation and repository structure checks (local).
- Open follow-ups:
  - add formal test lane (`T-002`),
  - harden country policy modes (`T-003`).

## 2026-02-19 — Batch VALIDATION-002

- Ticket(s): `T-002`
- Summary:
  - added flake check pipeline outputs for module eval and shell lint,
  - added x86_64 NixOS VM smoke test (`checks.x86_64-linux.nix-csf-smoke`),
  - added `scripts/validate.sh` for one-command validation,
  - fixed nftables generation issues discovered during VM execution.
- BA requirement mapping:
  - "to be able to test the project somehow" requirement is now covered with a runnable smoke test.
- PM milestone mapping:
  - Phase 1 validation lane established.
- Risk impact:
  - `none` (no new policy surface; validation and correctness hardening only).
- Validation evidence:
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
  - `./scripts/validate.sh`
- Open follow-ups:
  - country policy modes (`T-003`),
  - per-port country policy (`T-004`).

## 2026-02-19 — Batch COUNTRY-MODES-003

- Ticket(s): `T-003`
- Summary:
  - added `services.nixCsf.country.mode` with `deny|allow`,
  - implemented allow-mode nftables semantics (`ip/ip6 saddr != @country_* drop`),
  - added safety behavior for allow mode when country data is unavailable,
  - extended smoke test to assert allow-mode rule rendering.
- BA requirement mapping:
  - strengthens CSF-inspired country control ergonomics while keeping behavior explicit.
- PM milestone mapping:
  - Phase 2 country policy modes completed.
- Risk impact:
  - `low` (feature is opt-in; fail-open/fail-closed behavior is explicit).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
- Open follow-ups:
  - per-port country policy (`T-004`),
  - source governance for blocklists (`T-005`).

## 2026-02-19 — Batch PORT-COUNTRY-004

- Ticket(s): `T-004`
- Summary:
  - added `services.nixCsf.country.portDeny` API:
    - `enable`, `countries`, `tcpPorts`, `udpPorts`,
    - `extraIPv4`, `extraIPv6`,
  - added assertions for country-code validity and minimum config completeness,
  - compiled dedicated nftables sets/rules for port-scoped country deny behavior,
  - extended smoke test with a port-country deny assertion.
- BA requirement mapping:
  - delivers CSF `CC_DENY_PORTS`-style behavior in a declarative Nix module API.
- PM milestone mapping:
  - Phase 2 per-port country controls (deny mode) completed.
- Risk impact:
  - `low` (opt-in policy path, validated through VM smoke execution).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
- Open follow-ups:
  - blocklist source catalog + schema (`T-005`),
  - country allow-by-port controls (`CC_ALLOW_PORTS` parity; future ticket).

## 2026-02-19 — Batch BLOCKLIST-GOVERNANCE-005

- Ticket(s): `T-005`
- Summary:
  - added trusted blocklist catalog schema in module options:
    - `services.nixCsf.blocklists.catalog.<id>.{url,family,format,description}`,
  - added catalog source selection and governance controls:
    - `blocklists.sources`,
    - `blocklists.enforceCatalog`,
    - `blocklists.requireHTTPS`,
  - resolved effective blocklist URL set at evaluation time by merging selected catalog URLs and legacy direct URLs,
  - added JSON schema reference: `docs/schemas/blocklist-catalog.schema.json`,
  - extended smoke test with deterministic local catalog source feed.
- BA requirement mapping:
  - delivers "blocklist source catalog + schema" with explicit trust/governance behavior.
- PM milestone mapping:
  - Phase 1 source-governance hardening completed.
- Risk impact:
  - `low` (backward compatible; legacy direct URLs remain supported unless `enforceCatalog` is enabled).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
- Open follow-ups:
  - stateful rate-limit presets (`T-006`),
  - structured logging and metrics exporter (`T-007`).

## 2026-02-19 — Batch RATE-LIMIT-PRESETS-006

- Ticket(s): `T-006`
- Summary:
  - added stateful rate-limit presets:
    - `services.nixCsf.rateLimits.synFlood.{enable,preset}`,
    - `services.nixCsf.rateLimits.connFlood.{enable,preset}`,
  - implemented preset mapping (`relaxed|balanced|strict`) to nftables `rate` + `burst`,
  - rendered per-source nftables meters for IPv4 and IPv6 in the input chain,
  - extended smoke test with assertions for `syn_flood_*` and `conn_flood_*` rule presence.
- BA requirement mapping:
  - delivers a practical, declarative anti-flood profile layer aligned with CSF-inspired usability.
- PM milestone mapping:
  - Phase 2 policy expansion progressed with production-usable presets.
- Risk impact:
  - `low` (feature is opt-in and guarded by validation; legacy `synRateLimit` conflict is asserted).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
- Open follow-ups:
  - structured logging and metrics exporter (`T-007`),
  - scenario expansion in integration tests (`T-008`).

## 2026-02-19 — Batch OBSERVABILITY-007

- Ticket(s): `T-007`
- Summary:
  - added observability module API:
    - `services.nixCsf.observability.structuredLogging`,
    - `services.nixCsf.observability.metrics.{enable,outputFile}`,
  - implemented structured apply/refresh event logs (`run_start`, `set_counts`, `metrics_written`, `run_complete`),
  - implemented Prometheus textfile snapshot metrics export with:
    - feature enable gauges,
    - set entry counts,
    - source counts,
    - run success/timestamp/duration gauges,
  - extended smoke test to assert:
    - apply-mode metrics output,
    - refresh-mode metrics output,
    - post-refresh feed ingestion and metric count transition,
  - expanded README with observability examples and architecture notes.
- BA requirement mapping:
  - enables easier operations and troubleshooting for modern firewall workflows.
- PM milestone mapping:
  - Phase 3 operations maturity baseline established.
- Risk impact:
  - `low` (observability controls are backward compatible; metrics exporter is opt-in).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
- Open follow-ups:
  - integration scenario broadening (`T-008`),
  - cluster policy propagation model (`T-010`).

## 2026-02-19 — Batch INTEGRATION-008

- Ticket(s): `T-008`
- Summary:
  - added a second VM-based integration suite: `tests/integration.nix`,
  - validated two-node scenarios:
    - `good` node:
      - legacy `synRateLimit` rule rendering,
      - forward policy rendering,
      - metrics disabled behavior,
      - fail-closed refresh failure path for missing blocklist feed,
    - `failclosed` node:
      - fail-closed apply failure when `country.mode = "allow"` has no available data and `failOpen = false`,
  - exposed the new suite in flake checks as:
    - `checks.x86_64-linux.nix-csf-integration`,
  - updated `scripts/validate.sh` to run both VM checks:
    - smoke + integration,
  - updated README validation docs to describe both suites.
- BA requirement mapping:
  - expands practical testability and confidence for strict failure semantics in modern firewall workflows.
- PM milestone mapping:
  - Phase 4 integration-tests baseline started.
- Risk impact:
  - `low` (test-only expansion and validation script wiring).
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
- Open follow-ups:
  - release automation and module versioning (`T-009`),
  - cluster policy propagation model (`T-010`),
  - documentation use-case catalog expansion (`T-011`).
