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
