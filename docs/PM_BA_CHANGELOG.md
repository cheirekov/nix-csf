# PM/BA Changelog

## 2026-02-24 — Batch NETDATA-CHARTSD-PATH-032

- Ticket(s): `T-032`
- Summary:
  - fixed Netdata charts.d execution failure where logs reported `systemd-cat-native: command not found`,
  - root cause: Netdata service `PATH` omitted `services.netdata.package/bin` even though helper binary existed in package output,
  - module now appends `config.services.netdata.package` to `systemd.services.netdata.path` when `services.nixCsf.netdata.enable = true`,
  - added eval guard that asserts Netdata package path is present in service PATH under Netdata-enabled evaluation.
- BA requirement mapping:
  - restores practical visibility of `nix_csf.*` charts in Netdata dashboards.
- PM milestone mapping:
  - release-candidate hardening: monitoring collector execution reliability.
- Risk impact:
  - `low` (PATH extension only; no firewall policy change).
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
- Open follow-ups:
  - add VM integration assertion for charts API presence (`nix_csf.run_status`).

## 2026-02-24 — Batch NETDATA-METRICS-READABILITY-031

- Ticket(s): `T-031`
- Summary:
  - fixed Netdata collector visibility gap where `nix-csf` metrics existed but Netdata charts were missing,
  - changed `/var/lib/nix-csf` tmpfiles mode to `0751` when `observability.metrics.enable = true` so non-root collectors can traverse to a known metrics file path,
  - kept `cache` directory at `0750` (`root:root`) to avoid broadening cache visibility,
  - added an eval guard to ensure Netdata-enabled evaluation keeps the expected tmpfiles rule.
- BA requirement mapping:
  - ensures Netdata integration is operational in real deployments, not only UI-visible.
- PM milestone mapping:
  - release-candidate hardening: monitoring path reliability.
- Risk impact:
  - `low` (directory listing for `/var/lib/nix-csf` remains blocked for non-root users; only path traversal is opened).
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
- Open follow-ups:
  - add VM/runtime integration assertion that Netdata user can read `metrics.prom` and charts appear.

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

## 2026-02-19 — Batch RELEASE-009

- Ticket(s): `T-009`
- Summary:
  - introduced repository release source of truth via `VERSION` (`0.1.0`),
  - added read-only module metadata option:
    - `services.nixCsf.moduleVersion`,
  - exported version into runtime outputs:
    - structured `run_start` event includes version,
    - Prometheus metric `nix_csf_build_info{version="..."} 1`,
  - added release automation script:
    - `scripts/release.sh` with SemVer gating and commit/tag workflow,
  - added flake release packaging:
    - `packages.<system>.release`,
    - `packages.<system>.version`,
  - added SemVer/eval/shell lint checks for x86_64 + aarch64,
  - fixed `flake.nix` check composition to preserve x86_64 base checks plus VM checks,
  - updated `scripts/validate.sh` to execute lightweight checks before VM suites,
  - documented SemVer compatibility and release workflow in:
    - `docs/RELEASE.md`,
    - `README.md`.
- BA requirement mapping:
  - delivers repeatable publish flow and explicit module versioning for public flake/non-flake consumption.
- PM milestone mapping:
  - Phase 4 release-quality baseline expanded with SemVer policy and release automation.
- Risk impact:
  - `low` (automation/docs + metadata wiring; existing firewall semantics unchanged).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh && bash -n scripts/release.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `./scripts/validate.sh`
  - `./scripts/release.sh --version 0.1.1 --dry-run --no-validate --allow-dirty`
- Open follow-ups:
  - cluster policy propagation model (`T-010`),
  - documentation use-case catalog expansion (`T-011`).

## 2026-02-19 — Batch CLUSTER-PROPAGATION-010

- Ticket(s): `T-010`
- Summary:
  - added cluster policy module API:
    - `services.nixCsf.clusterPolicy.{enable,url,failOpen,requireHTTPS,authTokenFile,nodeId}`,
  - added module assertions for cluster policy URL/auth path safety,
  - added runtime cluster policy fetch/caching path in `nix-csf-apply.sh`:
    - refresh fetches JSON policy,
    - optional `Authorization` bearer token from `authTokenFile`,
    - optional `X-Nix-Csf-Node` header from `nodeId`,
  - added fail-open/fail-closed behavior for:
    - fetch failures,
    - invalid JSON payloads,
    - invalid cached policy,
  - merged propagated CIDRs into effective allow/deny nftables sets,
  - added cluster observability metrics:
    - `feature="cluster_policy"`,
    - `source="cluster_policy_urls"`,
    - `cluster_allow_*` / `cluster_deny_*` set-entry counts,
  - extended smoke VM scenario with deterministic local cluster policy source and assertions.
- BA requirement mapping:
  - delivers the first centralized allow/deny governance model across a server cluster while preserving local declarative control.
- PM milestone mapping:
  - closes cluster propagation model priority and advances operations maturity.
- Risk impact:
  - `low` (feature is opt-in and failure behavior is explicit).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh && bash -n scripts/release.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `./scripts/validate.sh`
- Open follow-ups:
  - documentation use-case catalog expansion (`T-011`),
  - preset threat profiles (`T-012`).

## 2026-02-19 — Batch DOC-USECASES-011

- Ticket(s): `T-011`
- Summary:
  - added operator-focused use-case catalog:
    - `docs/USE_CASES.md`,
  - added seven practical deployment scenarios:
    - public web,
    - SSH bastion allow-list,
    - port-scoped country deny,
    - governed catalog-only blocklists,
    - cluster policy propagation,
    - offline/local file feeds,
    - observability with Prometheus textfile metrics,
  - added baseline operator verification commands for apply/refresh/rules/logs/metrics checks,
  - updated README to link the full use-case catalog.
- BA requirement mapping:
  - directly addresses the request for richer, operator-ready documentation examples and use cases.
- PM milestone mapping:
  - closes documentation use-case catalog expansion and improves operations maturity onboarding.
- Risk impact:
  - `none` (documentation/process-only changes; no runtime policy logic changed in this ticket).
- Validation evidence:
  - `./scripts/validate.sh`
- Open follow-ups:
  - preset threat profiles (`T-012`),
  - troubleshooting command set and runbook (`T-013`).

## 2026-02-19 — Batch STRICT-SEMANTICS-014

- Ticket(s): `T-014`
- Summary:
  - hardened apply-time strict semantics in `nix-csf-apply.sh`:
    - when `blocklists.failOpen = false`, `apply` now fails if required feed cache is absent,
    - when `clusterPolicy.failOpen = false`, `apply` now fails if cluster policy cache is absent,
  - fixed cluster fetch return-code handling so invalid JSON is classified correctly on refresh,
  - changed static rule evaluation order to deny-first for explicit CIDR sets:
    - `denyIPv4/denyIPv6` now evaluate before `allowIPv4/allowIPv6`,
  - expanded integration coverage with deterministic strict apply failure assertions for blocklist cache-missing scenarios,
  - expanded PM backlog with prioritized centralized-control tickets:
    - `T-015` cluster schema v2 (`allow`/`deny`/`ignore`, revision/TTL/signing),
    - `T-016` dynamic offender propagation,
    - `T-017` ICMP policy profiles,
    - `T-018` country allow-by-port parity,
    - `T-019` Grafana/Prometheus monitoring pack,
    - `T-020` cluster auth/token lifecycle and secret handling.
- BA requirement mapping:
  - improves fail-closed predictability and addresses core operator concerns about centralized behavior safety and policy precedence.
- PM milestone mapping:
  - closes strict-semantics hardening lane and seeds the next centralized-control implementation queue.
- Risk impact:
  - `medium` (strict-mode behavior is intentionally tighter; hosts with strict settings now require cache warmup before apply succeeds).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh && bash -n scripts/validate.sh && bash -n scripts/release.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration"`
  - `./scripts/validate.sh`
- Open follow-ups:
  - preset threat profiles (`T-012`),
  - cluster schema v2 (`T-015`),
  - dynamic offender propagation (`T-016`).

## 2026-02-20 — Batch THREAT-PROFILES-012

- Ticket(s): `T-012`
- Summary:
  - introduced profile API:
    - `services.nixCsf.threatProfile = "custom"|"server"|"workstation"|"edge"`,
  - implemented profile defaults with explicit-override safety via `mkDefault`,
  - defined profile baselines:
    - `server`: enables balanced SYN/connection flood controls, `logDrops = true`, `autoRefresh.onCalendar = "hourly"`,
    - `workstation`: defaults to no inbound open TCP/UDP ports,
    - `edge`: defaults to `openTCPPorts = [ 22 443 ]`, `openUDPPorts = [ 53 51820 ]`, strict SYN flood + balanced connection flood controls,
  - added lightweight profile evaluation check:
    - `checks.<system>.eval-profiles`,
  - updated validation pipeline to build the new profile check in `scripts/validate.sh`,
  - extended integration VM coverage with deterministic `profileedge` runtime assertions,
  - added profile quick-start/override documentation in README and use-case catalog.
- BA requirement mapping:
  - delivers safer, faster onboarding for common host roles while preserving declarative per-host control.
- PM milestone mapping:
  - closes Phase 2 preset threat profiles and advances readiness for centralized cluster governance work.
- Risk impact:
  - `low` (opt-in profile selection; explicit host config keeps highest precedence).
- Validation evidence:
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Open follow-ups:
  - cluster schema v2 (`T-015`),
  - dynamic offender propagation (`T-016`),
  - ICMP policy profiles (`T-017`).

## 2026-02-20 — Batch CLUSTER-SCHEMA-V2-015

- Ticket(s): `T-015`
- Summary:
  - added cluster policy schema v2 runtime support in `nix-csf-apply.sh`:
    - `allowIPv4/allowIPv6`,
    - `denyIPv4/denyIPv6`,
    - `ignoreIPv4/ignoreIPv6`,
    - metadata keys `schemaVersion`, `revision`, `ttlSeconds`,
  - added explicit schema validation for fetched and cached cluster policy payloads,
  - implemented cache TTL guardrails:
    - fail-closed when `clusterPolicy.failOpen = false` and cache is expired,
    - fail-open warning and skip-merge behavior when `clusterPolicy.failOpen = true`,
  - implemented ignore-precedence reconciliation:
    - merge ignore CIDRs into allow sets,
    - subtract ignore CIDRs from deny-style sources (static deny, country deny, per-port country deny, blocklist feeds, cluster deny),
  - added cluster policy metadata observability:
    - structured `cluster_policy_meta` log event,
    - Prometheus gauges for schema version, cache age, TTL, expired state,
    - set-entry counters for cluster ignore sets,
  - expanded tests:
    - smoke suite now asserts ignore precedence + schema/TTL metrics,
    - integration suite adds `clusterexpired` stale-cache strict failure scenario,
  - fixed regression discovered during integration:
    - explicit `clusterPolicy.failOpen = false` was being coerced to `true` due jq `// true` behavior;
    - parsing now preserves explicit `false`.
- BA requirement mapping:
  - addresses centralized list governance concerns (allow/deny/ignore), strict stale-cache behavior, and provides a concrete path toward CSF-like cluster operations.
- PM milestone mapping:
  - closes Phase 3 cluster schema v2 milestone and unblocks dynamic propagation/coexistence implementation tickets.
- Risk impact:
  - `medium` (strict-mode behavior now correctly enforces fail-closed semantics for expired cluster policy cache).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
- Open follow-ups:
  - dynamic offender propagation (`T-016`),
  - firewall coexistence profile (`T-021`),
  - token lifecycle/secret handling (`T-020`),
  - Grafana/Prometheus monitoring pack (`T-019`).

## 2026-02-20 — Batch DYNAMIC-OFFENDERS-016

- Ticket(s): `T-016`
- Summary:
  - added module API for dynamic offender snapshots:
    - `services.nixCsf.dynamicOffenders.{enable,url,failOpen,requireHTTPS,authTokenFile,nodeId,defaultEntryTTLSeconds,maxEntries}`,
  - added module assertions for dynamic snapshot URL/auth path safety,
  - implemented dynamic snapshot runtime pipeline in `nix-csf-apply.sh`:
    - refresh/apply cache semantics with strict fail-closed support,
    - schema validation for dynamic payload (`banIPv4`/`banIPv6` entries),
    - snapshot TTL cache-age guard via payload `ttlSeconds`,
    - per-entry expiration via `ttlSeconds` or `expiresAt` (fallback to `defaultEntryTTLSeconds`),
    - max-entry guardrail (`maxEntries`),
    - nft timeout-set rendering:
      - `dynamic_ban_ipv4`,
      - `dynamic_ban_ipv6`,
  - integrated dynamic enforcement into rule chain with allow precedence retained,
  - added dynamic observability:
    - structured `dynamic_offenders_meta` event,
    - Prometheus feature/source/set metrics and snapshot health gauges
      (`schema`, `cache_age`, `ttl`, `cache_expired`),
  - expanded tests:
    - smoke suite covers timeout rendering, expired-entry exclusion, and allow-vs-dynamic precedence ordering,
    - integration suite adds strict expired-cache scenario (`dynamicexpired`),
  - updated docs:
    - README dynamic configuration and payload examples,
    - architecture/runtime model updates,
    - operator use-case catalog dynamic section,
    - roadmap + delivery board/session brief alignment.
- BA requirement mapping:
  - delivers CSF-like temporary cluster block behavior with explicit TTL and deterministic precedence in a Nix-native runtime model.
- PM milestone mapping:
  - closes dynamic offender propagation baseline and promotes Docker coexistence profile (`T-021`) as next delivery focus.
- Risk impact:
  - `medium` (new strict path can fail closed by design when dynamic snapshot cache is missing/expired under `failOpen = false`).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Open follow-ups:
  - firewall coexistence profile (`T-021`),
  - token lifecycle/secret handling (`T-020`),
  - Grafana/Prometheus monitoring pack (`T-019`),
  - hybrid local+remote list reconciliation (`T-022`).

## 2026-02-20 — Batch DOCKER-COEXIST-021

- Ticket(s): `T-021`
- Summary:
  - completed coexistence profile API in module options:
    - `services.nixCsf.coexistence.profile = "exclusive-firewall"|"docker-coexist"`,
  - added eval-time assertion:
    - `docker-coexist` requires `services.nixCsf.forwardPolicy = "accept"`,
  - implemented runtime coexistence behavior in `nix-csf-apply.sh`:
    - parse + validate profile from generated config,
    - fail fast for invalid `docker-coexist` forward-policy combinations,
    - in `docker-coexist`, compile deny-style forward overlays while preserving policy accept for Docker forwarding,
  - added coexistence observability metrics:
    - `nix_csf_feature_enabled{feature="coexist_docker"}`,
    - `nix_csf_coexistence_profile{profile="..."}`,
  - expanded integration coverage with Docker-enabled node:
    - validates apply success and coexistence forward-chain rendering,
    - validates Docker daemon/network operations (`docker network create/inspect/rm`),
  - updated docs/roadmap/board/session artifacts with coexistence examples and operational notes.
- BA requirement mapping:
  - addresses CSF-style cluster host reality where Docker or another daemon mutates firewall state, while keeping declarative deny controls in place.
- PM milestone mapping:
  - closes firewall coexistence profile milestone and advances next priorities to token lifecycle (`T-020`) and monitoring pack (`T-019`).
- Risk impact:
  - `medium` (new forward-path behavior for coexist mode; mitigated by explicit profile opt-in and integration tests).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
- Open follow-ups:
  - cluster auth/token lifecycle + secret handling (`T-020`),
  - Grafana/Prometheus monitoring pack (`T-019`),
  - ICMP policy profiles (`T-017`),
  - hybrid local+remote list reconciliation (`T-022`).

## 2026-02-20 — Batch TOKEN-LIFECYCLE-020

- Ticket(s): `T-020`
- Summary:
  - added ordered auth token rotation options in module API:
    - `services.nixCsf.clusterPolicy.authTokenFiles`,
    - `services.nixCsf.dynamicOffenders.authTokenFiles`,
  - kept backward compatibility with legacy single-token options:
    - `clusterPolicy.authTokenFile`,
    - `dynamicOffenders.authTokenFile`,
  - added eval-time safety assertions:
    - token file paths must be absolute,
    - legacy `authTokenFile` cannot be combined with `authTokenFiles`,
  - implemented secure token lifecycle handling in `nix-csf-apply.sh`:
    - validates secret files exist and are readable,
    - enforces strict file permissions (no group/other bits),
    - rejects empty tokens and whitespace-containing token values,
    - attempts token candidates in order and falls back on auth failures,
  - added auth fallback observability:
    - structured `auth_fallback_success` event,
    - auth candidate/selected-slot fields in cluster and dynamic metadata events,
    - Prometheus gauges:
      - `nix_csf_auth_token_candidates{source="cluster_policy|dynamic_offenders"}`,
      - `nix_csf_auth_token_selected_slot{source="cluster_policy|dynamic_offenders"}`,
  - expanded integration coverage (`tokenrotation` node):
    - local fixture server requires rotated tokens for cluster + dynamic endpoints,
    - validates fallback from slot 1 to slot 2,
    - validates cache revision updates, nft rendering, and metrics output.
- BA requirement mapping:
  - addresses professional secret/token handling for centralized cluster operation and supports staged token rotation without declarative churn.
- PM milestone mapping:
  - closes cluster auth/token lifecycle milestone and advances monitoring pack (`T-019`) as the next NOW ticket.
- Risk impact:
  - `medium` (strict secret-file validation can fail refresh/apply when file modes or token format are unsafe by design).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Open follow-ups:
  - Grafana/Prometheus monitoring pack (`T-019`),
  - ICMP policy profiles (`T-017`),
  - country allow-by-port parity (`T-018`),
  - hybrid local+remote list reconciliation (`T-022`).

## 2026-02-20 — Batch MONITORING-PACK-019

- Ticket(s): `T-019`
- Summary:
  - delivered monitoring artifacts:
    - Prometheus alert rules: `docs/monitoring/prometheus-alert-rules.yml`,
    - Grafana dashboard: `docs/monitoring/grafana-dashboard.json`,
    - operations runbook: `docs/MONITORING.md`,
  - implemented alert coverage for:
    - refresh staleness,
    - cluster policy cache expiry,
    - dynamic snapshot cache expiry,
    - dynamic-ban cardinality spikes,
    - auth token fallback slot activity,
    - elevated refresh runtime,
  - added monitoring-focused validation checks in `flake.nix`:
    - `checks.<system>.eval-monitoring`,
    - `checks.<system>.monitoring-pack`,
  - updated validation pipeline in `scripts/validate.sh` to execute monitoring checks prior to VM suites,
  - updated user/operator docs:
    - `README.md`,
    - `docs/ARCHITECTURE.md`,
    - `docs/USE_CASES.md`,
    - `docs/DYNAMIC_CLUSTER_POC.md`,
    - `docs/ROADMAP.md`,
    - `docs/DELIVERY_BOARD.md`.
- BA requirement mapping:
  - fulfills requested detailed monitoring guidance with operational examples and actionable alerting around centralized/dynamic firewall behavior.
- PM milestone mapping:
  - closes Grafana/Prometheus monitoring pack milestone and advances ICMP profile work (`T-017`) as next NOW ticket.
- Risk impact:
  - `low` (monitoring/docs/check-path expansion only; runtime firewall enforcement semantics unchanged).
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-monitoring" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.monitoring-pack" --print-build-logs`
  - `./scripts/validate.sh`
- Open follow-ups:
  - ICMP policy profiles (`T-017`),
  - country allow-by-port parity (`T-018`),
  - hybrid local+remote list reconciliation (`T-022`),
  - Netdata monitoring integration (`T-023`, optional enhancement).

## 2026-02-20 — Triage NETDATA-023

- Ticket(s): `T-023`
- Decision:
  - accepted as separate story (not blocker for core monitoring pack).
- Priority/severity:
  - `P3` enhancement.
- Scope:
  - map existing `nix_csf_*` metrics into Netdata charts + alarms,
  - keep semantic alignment with Prometheus/Grafana monitoring pack to avoid drift.

## 2026-02-20 — Batch CLUSTER-RETRO-PLAN-024

- Ticket(s): `T-024` (planning kickoff), `T-025` (new), `T-026` (new)
- Summary:
  - performed clustering retro focused on CSF-like day-2 workflow gaps:
    - no built-in cluster write-path command/API,
    - no built-in local mutation fan-out flow,
    - no built-in escalation rule from temporary to permanent bans,
  - created dedicated design/PoC artifact:
    - `docs/CLUSTER_CONTROL_PLANE_POC.md`,
  - defined and queued new cluster-first PoC tickets:
    - `T-024` control-plane + snapshot publisher,
    - `T-025` operator mutation workflow (`nix-csfctl`),
    - `T-026` escalation policy (`N` temporary bans => permanent deny),
  - reordered delivery board priorities to cluster-first sequence and aligned roadmap/session docs.
- BA requirement mapping:
  - directly addresses operator request for easy remote policy management and CSF-style cluster behavior while preserving Nix declarative boundaries.
- PM milestone mapping:
  - establishes the next execution lane for cluster control-plane usability and dynamic escalation maturity.
- Risk impact:
  - `none` (planning/documentation-only change; runtime firewall behavior unchanged).
- Validation evidence:
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
- Open follow-ups:
  - implement `T-024`,
  - implement `T-025`,
  - implement `T-026`.

## 2026-02-20 — Batch CONTROL-PLANE-POC-024

- Ticket(s): `T-024`
- Summary:
  - implemented in-repo control-plane PoC service:
    - `scripts/nix-csf-control-plane.py`,
    - mutable state persisted under `controlPlane.dataDir` (default `/var/lib/nix-csf-control-plane`),
    - read endpoints:
      - `GET /healthz`,
      - `GET /snapshots/<env>/cluster-policy.json`,
      - `GET /snapshots/<env>/dynamic-offenders.json`,
    - write endpoints:
      - `POST /v1/policy/{allow|deny|ignore}`,
      - `DELETE /v1/policy/{allow|deny|ignore}`,
      - `POST /v1/offenders/ban-temp`,
      - `POST /v1/offenders/unban`,
  - added module API and systemd wiring:
    - `services.nixCsf.controlPlane.*`,
    - `systemd.services.nix-csf-control-plane`,
    - tmpfiles/assertions for runtime state and auth configuration,
  - extended integration coverage with `controlplanepoc` node:
    - API mutation -> `nix-csf-refresh.service` -> cache update -> nft set/ruleset verification,
  - added validation gates:
    - `checks.<system>.eval-control-plane`,
    - `checks.<system>.control-plane-lint`,
    - `scripts/validate.sh` wiring for both checks,
  - improved VM test robustness for Docker coexist path in slow/no-KVM runs:
    - `systemd.services.docker.path = [ pkgs.nftables ]`,
    - `systemd.services.docker.serviceConfig.TimeoutStartSec = "300s"`.
- BA requirement mapping:
  - addresses requested "non-static list" operations in NixOS by keeping mutable runtime policy data outside declarative rebuild artifacts while preserving pull-based client safety.
- PM milestone mapping:
  - closes cluster control-plane snapshot publisher PoC and promotes escalation work (`T-026`) as NOW priority.
- Risk impact:
  - `medium` (new optional service surface + API path; defaults remain unchanged unless `controlPlane.enable = true`).
- Validation evidence:
  - `bash -n scripts/validate.sh`
  - `python3 -m py_compile scripts/nix-csf-control-plane.py`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-control-plane" "path:/home/yc/work/nix-csf#checks.x86_64-linux.control-plane-lint" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs` (slow/no-KVM TCG runtime)
- Open follow-ups:
  - implement escalation policy (`T-026`) with explicit local-only mode compatibility,
  - implement operator CLI (`T-025`),
  - define hybrid local-files reconciliation contract (`T-022`).

## 2026-02-20 — Batch FEED-HOTFIX-027

- Ticket(s): `T-027`
- Summary:
  - triaged and fixed a `P0` feed reliability regression affecting country/blocklist enforcement quality:
    - updated default Spamhaus catalog endpoints from deprecated URLs to current public endpoints:
      - `https://www.spamhaus.org/drop/drop.txt`
      - `https://www.spamhaus.org/drop/dropv6.txt`,
    - hardened feed parser normalization:
      - strip `;` inline annotations (Spamhaus-style lines),
      - accept ipset-style feed entries:
        - `add <set> <cidr_or_ip>`
        - `ipset add <set> <cidr_or_ip>`,
    - extended deterministic smoke coverage:
      - semicolon-annotated blocklist fixture parsing,
      - ipset-style blocklist line parsing,
      - country template fetch path with semicolon-annotated local fixture.
- BA requirement mapping:
  - resolves operator-reported risk that country/blocklist source ingestion may silently miss entries.
- PM milestone mapping:
  - emergency quality hardening to preserve trust in source governance and refresh semantics.
- Risk impact:
  - `low` (parser compatibility and source URL fixes; no policy precedence changes).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - continue `T-026` escalation policy completion,
  - evaluate richer feed-kind taxonomy (`COUNTRY_`, `CLOUD_*`, `TOR`, `OPEN_PROXY`) as a separate scope-controlled epic.

## 2026-02-20 — Batch ESCALATION-026

- Ticket(s): `T-026`
- Summary:
  - implemented deterministic escalation policy in control-plane runtime:
    - rolling event history keyed by `family|cidr`,
    - promotion rule: `N` temp-ban events within `windowSeconds` => permanent deny promotion,
    - promoted CIDR is written into policy deny list and removed from dynamic entries,
    - persisted promotion audit trail with bounded retention (`maxAuditEntries`),
  - added control-plane API exposure:
    - `GET /v1/escalation/promotions` (audit visibility),
    - `ban-temp` response now returns escalation metadata,
  - added Nix module wiring/options:
    - `services.nixCsf.controlPlane.escalation.enable`,
    - `services.nixCsf.controlPlane.escalation.tempBanThreshold`,
    - `services.nixCsf.controlPlane.escalation.windowSeconds`,
    - `services.nixCsf.controlPlane.escalation.maxAuditEntries`,
  - extended integration scenario assertions for promotion path and cache/nft reconciliation.
- BA requirement mapping:
  - addresses CSF-style "repeated temporary bans become permanent deny" behavior in a deterministic Nix-compatible runtime model.
- PM milestone mapping:
  - closes escalation policy PoC milestone and unblocks focus on operator CLI (`T-025`).
- Risk impact:
  - `medium` (mutable runtime behavior expansion in optional control-plane path; default disabled unless configured).
- Validation evidence:
  - `python3 -m py_compile scripts/nix-csf-control-plane.py`
  - `./scripts/validate-fast.sh`
  - `./scripts/validate-capture.sh` (operator run; succeeded)
- Open follow-ups:
  - complete and validate `T-025` operator CLI workflow.

## 2026-02-20 — Batch OPERATOR-CLI-025

- Ticket(s): `T-025`
- Summary:
  - implemented operator CLI:
    - `scripts/nix-csfctl.sh`,
    - commands: `health`, `policy add/remove`, `ban-temp`, `unban`, `promotions`,
    - auth support via `--auth-token-file` (Bearer token),
  - wired CLI into module/packaging:
    - `controlPlane.enable` now installs both `nix-csf-control-plane` and `nix-csfctl`,
    - added flake package output: `packages.<system>.nix-csfctl`,
    - expanded shellcheck coverage to include new scripts,
  - switched control-plane integration workflow to CLI-backed mutation assertions
    (replacing raw curl mutation calls).
- BA requirement mapping:
  - closes "easy write-path from master/approved node" requirement for day-2 operations.
- PM milestone mapping:
  - completes operator mutation workflow PoC and unblocks full focus on reconciliation contract (`T-022`).
- Risk impact:
  - `low` (new operator tooling; control-plane runtime behavior unchanged).
- Validation evidence:
  - `./scripts/validate-fast.sh`
  - `./scripts/validate-capture.sh` (operator run; succeeded)
- Open follow-ups:
  - implement and validate hybrid local+remote reconciliation contract (`T-022`).

## 2026-02-20 — Batch HYBRID-RECON-022

- Ticket(s): `T-022`
- Summary:
  - introduced hybrid local-file policy source model:
    - new module API: `services.nixCsf.localFiles.{enable,allow,deny,ignore,failOnMissing}`,
    - local file parsing supports plain CIDR/IP and ipset-style `add` lines,
  - implemented deterministic reconciliation contract in apply pipeline:
    - merge local allow/deny overlays with declarative base,
    - merge `localFiles.ignore` with cluster `ignore*`,
    - promote effective ignore into allow and subtract from deny-style overlays
      (static deny, country deny, per-port country deny, blocklist feeds, cluster deny),
  - added observability for hybrid sources:
    - feature toggle metric `local_files`,
    - local/effective ignore set cardinality metrics,
    - local file source counters,
  - extended tests:
    - smoke coverage for local allow/deny/ignore reconciliation behavior + metrics,
    - integration `controlplanepoc` assertions for local ignore overriding remote cluster deny.
- BA requirement mapping:
  - addresses CSF-like local list operations while preserving Nix declarative/remote policy boundaries.
- PM milestone mapping:
  - advances hybrid reconciliation contract implementation for cluster-aware operations.
- Risk impact:
  - `medium` (new reconciliation path in apply pipeline).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - run full VM validation (`./scripts/validate-capture.sh`) for final ticket closure.

## 2026-02-21 — Batch ICMP-PROFILES-017

- Ticket(s): `T-017`
- Summary:
  - implemented ICMP profile engine in apply pipeline:
    - `icmp.profile = legacy|off|safe|diagnostic|open`,
    - `icmp.rateLimit.{enable,rate,burst}` support for profile-generated rules,
    - profile-specific nft rule generation with strict behavior for `off`, `safe`, and `diagnostic`,
    - compatibility preservation for `legacy` + `allowICMP`,
  - added ICMP observability metrics:
    - `nix_csf_feature_enabled{feature="icmp_rate_limit"}`,
    - `nix_csf_icmp_profile{profile="..."}`,
  - expanded validation and tests:
    - `eval-profiles` now asserts ICMP profile defaults for threat profiles,
    - integration assertions for legacy profile behavior and edge-safe profile rule output,
    - smoke assertions for ICMP profile/rate-limit metrics,
  - updated operator docs and planning artifacts:
    - `README.md`,
    - `docs/USE_CASES.md`,
    - `docs/DYNAMIC_CLUSTER_POC.md`,
    - `docs/ROADMAP.md`,
    - `docs/DELIVERY_BOARD.md`.
- BA requirement mapping:
  - closes requested ICMP policy gap with explicit, safer, profile-driven behavior while retaining backward compatibility.
- PM milestone mapping:
  - closes `T-017` and advances priority to country allow-by-port parity (`T-018`).
- Risk impact:
  - `medium` (input-chain ICMP behavior is now profile-driven when not in legacy mode).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-018` country allow-by-port parity,
  - `T-013` troubleshooting runbook,
  - `T-023` Netdata integration (optional).

## 2026-02-22 — Batch COUNTRY-PORT-ALLOW-018

- Ticket(s): `T-018`
- Summary:
  - implemented CSF `CC_ALLOW_PORTS` parity as `services.nixCsf.country.portAllow`:
    - module API added: `enable`, `countries`, `tcpPorts`, `udpPorts`, `extraIPv4`, `extraIPv6`,
    - runtime assertions added for country-code validity, port presence, and source availability,
  - extended apply pipeline with `portAllow` support:
    - country feed ingestion + cache reuse for port-allow sets,
    - fail-open/fail-closed semantics aligned with existing country policy model,
    - nft set generation: `country_port_allow_ipv4` / `country_port_allow_ipv6`,
    - input/forward chain enforcement for selected TCP/UDP ports using country-scoped deny-on-mismatch rules,
  - expanded observability:
    - feature metric: `country_port_allow`,
    - set cardinality metrics for `country_port_allow_ipv4/ipv6`,
    - configured-country source counter metric `country_port_allow_codes`,
  - expanded deterministic smoke coverage:
    - `country.portAllow` fixture configuration,
    - rule emission assertions,
    - metrics assertions and post-refresh set-content validation,
  - updated operator docs and planning artifacts:
    - `README.md`,
    - `docs/USE_CASES.md`,
    - `docs/REFERENCES_ANALYSIS.md`,
    - `docs/ROADMAP.md`,
    - `docs/DELIVERY_BOARD.md`.
- BA requirement mapping:
  - closes requested "ports opened only to selected countries" parity in a declarative Nix API without introducing imperative state drift.
- PM milestone mapping:
  - closes `T-018` and leaves `T-013` (runbook) + `T-023` (Netdata story) as next queued items.
- Risk impact:
  - `medium` (new input/forward chain enforcement path for port-scoped country allow restrictions).
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-013` troubleshooting command/runbook completion,
  - `T-023` Netdata monitoring integration story.

## 2026-02-23 — Batch TROUBLESHOOTING-RUNBOOK-013

- Ticket(s): `T-013`
- Summary:
  - delivered operator troubleshooting command bundle:
    - new tool: `scripts/nix-csf-triage.sh`,
    - installed command: `nix-csf-triage` via module/package wiring,
    - one-command snapshot support (`--output`, journal depth, metrics path, optional artifacts path),
  - delivered dedicated troubleshooting runbook:
    - new `docs/TROUBLESHOOTING.md`,
    - symptom-driven flows for apply/refresh/control-plane/coexistence/membership checks,
    - standard "handoff packet" guidance for validation and incident triage,
  - integrated docs and packaging:
    - README usage and docs index updates,
    - monitoring runbook cross-link,
    - flake shellcheck and package outputs include triage script/tool.
- BA requirement mapping:
  - closes the request for a consistent troubleshooting command set and operational runbook.
- PM milestone mapping:
  - closes `T-013`; leaves `T-023` Netdata integration as the next planned story.
- Risk impact:
  - `low` (operator tooling/documentation only; no firewall rule semantics changed).
- Validation evidence:
  - `bash -n scripts/nix-csf-triage.sh`
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-023` Netdata monitoring integration.

## 2026-02-23 — Backlog Triage LFD-NIX-WAY

- Ticket(s): `T-028`, `T-029`, `T-030`
- Trigger:
  - release-readiness review against real CSF operational workflows (`csf.allow`, `csf.deny`, `csf.ignore`, LFD behavior, fail2ban coexistence).
- Summary:
  - created migration/security ticket set for CSF-to-nix-csf operational parity:
    - `T-028` Legacy CSF list import bridge:
      - ingest `csf.allow/csf.deny/csf.ignore` style files into nix-csf local overlays,
      - emit explicit unsupported-line reports for CSF advanced port syntax,
      - preserve declarative safety boundaries (no hidden mutable rewrite of Nix config),
    - `T-029` LFD-like detector POC (Nix-native):
      - detector reads host auth/service failure signals,
      - emits temp bans through control-plane/dynamic offender pipeline (`nix-csfctl ban-temp`),
      - supports strict on/off module toggle and escalation policy integration,
    - `T-030` fail2ban adapter/coexistence:
      - fail2ban remains detector only,
      - nix-csf remains single firewall writer,
      - provide adapter action template and coexistence test coverage.
  - added architecture note `docs/LFD_NIX_WAY_POC.md` to lock in detector/write-path boundaries before implementation.
- BA requirement mapping:
  - addresses CSF `lfd`/list migration concerns in a NixOS-safe architecture without mixing multiple independent nft writers.
- PM milestone mapping:
  - shifts near-term priority from optional monitoring enhancement to migration + detector parity for first stable release confidence.
- Risk impact:
  - `low` (planning/ticketing update only).
- Validation evidence:
  - documentation-only triage update.

## 2026-02-23 — Batch CSF-IMPORT-BRIDGE-028

- Ticket(s): `T-028`
- Summary:
  - delivered legacy CSF list migration bridge:
    - new tool `nix-csf-import-csf` (`scripts/nix-csf-import-csf.sh`),
    - imports CIDR/IP-compatible entries from `csf.allow/csf.deny/csf.ignore`,
    - writes explicit unsupported-line report with source + line number + reason
      (for example CSF advanced `tcp|...` rules and `Include` directives),
    - emits generated `localFiles` Nix snippet for operator wiring,
  - added deterministic validation coverage:
    - new `checks.<system>.csf-import-check` fixture test in flake checks,
    - shellcheck coverage for new import script,
  - integrated packaging/operator surface:
    - flake package output `csf-import`,
    - module host package install includes `nix-csf-import-csf`,
    - validation scripts now include `csf-import-check`,
  - expanded operator docs/examples:
    - new migration guide `docs/CSF_IMPORT.md`,
    - README and use-case catalog examples updated.
- BA requirement mapping:
  - addresses real-world migration from existing CSF deployments while preserving Nix-native runtime ownership and explicit conversion visibility.
- PM milestone mapping:
  - closes `T-028`; advances next priority to `T-029` (LFD-like detector POC) and `T-030` (fail2ban adapter).
- Risk impact:
  - `low` (new import tool/checks/docs; firewall runtime behavior unchanged).
- Validation evidence:
  - `bash -n scripts/nix-csf-import-csf.sh`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-029` LFD-like detector POC (Nix-native),
  - `T-030` fail2ban adapter/coexistence profile,
  - `T-023` Netdata integration.

## 2026-02-23 — Batch LFD-DETECTOR-029

- Ticket(s): `T-029`
- Summary:
  - delivered Nix-native LFD-like detector path:
    - new tool `nix-csf-lfd-detector` (`scripts/nix-csf-lfd-detector.sh`),
    - detector scans SSH failure signals from journald (`sshdUnit` and/or `journalIdentifier` sources),
    - thresholded offenders are written through control-plane API via `nix-csfctl ban-temp`
      (no direct nft writes),
    - optional immediate refresh (`refreshAfterBan`) triggers `nix-csf-refresh.service` after changed bans,
    - detector emits Prometheus textfile metrics (`/var/lib/nix-csf/lfd-detector.prom` by default),
  - expanded module API and wiring:
    - new `services.nixCsf.lfdDetector.*` options (toggle, thresholds, schedule, endpoint/auth, metrics),
    - new service/timer units:
      - `nix-csf-lfd-detector.service`,
      - `nix-csf-lfd-detector.timer`,
    - safety assertions added for dynamic-offender dependency, endpoint/auth path shape, and journal source requirements,
  - expanded validation and integration coverage:
    - new eval check `checks.<system>.eval-lfd-detector`,
    - shellcheck now includes detector script,
    - integration scenario extends control-plane POC with SSH-failure-style events -> detector run -> dynamic/nft verification,
  - expanded docs/examples:
    - new runbook `docs/LFD_DETECTOR.md`,
    - README + use-case catalog updated with LFD detector examples.
- BA requirement mapping:
  - implements requested CSF/LFD-style dynamic block behavior in Nix way while preserving single-writer firewall authority.
- PM milestone mapping:
  - closes `T-029`; next priority remains `T-030` (fail2ban adapter) with `T-023` as optional monitoring story.
- Risk impact:
  - `medium` (new runtime detector/write path and timer behavior).
- Validation evidence:
  - `bash -n scripts/nix-csf-lfd-detector.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-030` fail2ban adapter/coexistence profile,
  - `T-023` Netdata integration.

## 2026-02-23 — Batch FAIL2BAN-ADAPTER-030

- Ticket(s): `T-030`
- Summary:
  - delivered fail2ban adapter path that preserves single-writer firewall contract:
    - new adapter tool `nix-csf-fail2ban-action` (`scripts/nix-csf-fail2ban-action.sh`),
    - supports `ban`/`unban` plus fail2ban-compatible `start`/`stop`/`check` no-op actions,
    - translates fail2ban offender signals into control-plane mutations via `nix-csfctl`
      (`ban-temp`/`unban`) instead of direct nft writes,
    - optional immediate refresh triggers after ban/unban updates,
  - expanded module API and wiring:
    - new `services.nixCsf.fail2banAdapter.*` option family,
    - generated action template:
      - `/etc/fail2ban/action.d/<actionName>.local`,
    - safety assertions for endpoint/auth path validity and control-plane/dynamic dependencies,
  - expanded validation and integration coverage:
    - new eval check `checks.<system>.eval-fail2ban-adapter`,
    - shellcheck includes adapter script,
    - integration scenario verifies adapter-driven ban/unban mutation flow through
      control-plane cache and rendered nft timeout rules,
  - expanded docs/examples:
    - new runbook `docs/FAIL2BAN_ADAPTER.md`,
    - README + use-case catalog updates,
    - board/roadmap/reference artifacts updated for ticket closure.
- BA requirement mapping:
  - implements requested fail2ban coexistence in Nix style by keeping fail2ban detector-only
    and `nix-csf` as firewall state authority.
- PM milestone mapping:
  - closes `T-030`; next queued story is `T-023` (Netdata integration).
- Risk impact:
  - `medium` (new detector adapter write path and generated fail2ban action template).
- Validation evidence:
  - `bash -n scripts/nix-csf-fail2ban-action.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-fail2ban-adapter" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - `T-023` Netdata integration.

## 2026-02-23 — Batch NETDATA-INTEGRATION-023

- Ticket(s): `T-023`
- Summary:
  - delivered Netdata integration for existing `nix_csf_*` metric surface:
    - new Netdata charts collector plugin:
      - `scripts/nix-csf-netdata.chart.sh`,
    - new module API:
      - `services.nixCsf.netdata.*`,
    - generated Netdata config outputs when enabled:
      - `/etc/netdata/conf.d/charts.d/nix_csf.conf`,
      - `/etc/netdata/conf.d/health.d/nix_csf.conf` (optional),
  - added guardrails:
    - `services.netdata.enable = true` required for `services.nixCsf.netdata.enable`,
    - `services.nixCsf.observability.metrics.enable = true` required,
    - metrics file path validated as absolute,
  - added validation coverage:
    - new eval check: `checks.<system>.eval-netdata`,
    - shellcheck coverage for Netdata collector script,
    - validate scripts include `eval-netdata`,
  - updated docs:
    - new runbook: `docs/NETDATA.md`,
    - monitoring doc update: `docs/MONITORING.md`,
    - README + use-case + board/roadmap/session updates.
- BA requirement mapping:
  - closes optional Netdata monitoring story with Nix-native, declarative wiring and no duplicate firewall writer.
- PM milestone mapping:
  - closes `T-023`; next queue moves to release-candidate hardening (ticket `TBD`).
- Risk impact:
  - `low` (monitoring path only; no firewall enforcement semantics changed).
- Validation evidence:
  - `bash -n scripts/nix-csf-netdata.chart.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`
- Open follow-ups:
  - release-candidate hardening (ticket `TBD`).
