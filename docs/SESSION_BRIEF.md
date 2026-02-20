# Session Brief

Last updated: 2026-02-20  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-016` (Dynamic offender propagation).
- Goal: deliver CSF-like temporary offender propagation with deterministic TTL behavior and strict-mode safety.
- In scope:
  - add module API for dynamic offender snapshots (`services.nixCsf.dynamicOffenders.*`),
  - fetch/cache/validate dynamic snapshot JSON in runtime apply/refresh pipeline,
  - convert snapshot entries into nft timeout sets (`dynamic_ban_ipv4`/`dynamic_ban_ipv6`),
  - enforce snapshot TTL cache-age behavior for fail-open/fail-closed modes,
  - expose dynamic snapshot health + cardinality metrics,
  - expand VM smoke/integration coverage for dynamic TTL semantics.
- Out of scope:
  - Docker/firewall coexistence implementation (`T-021`),
  - cluster token lifecycle automation (`T-020`),
  - ICMP per-type/per-rate controls (`T-017`),
  - hybrid local-file + remote list reconciliation (`T-022`).
- Stop/rollback condition:
  - any regression in strict fail-closed semantics for existing blocklist/cluster/country paths.

## 2) Definition of done

- Dynamic offender API is available and validated in module assertions.
- Dynamic snapshot supports temporary bans with `ttlSeconds`/`expiresAt` semantics.
- Timeout-based nft sets are rendered and enforced.
- Strict mode fails closed on missing/expired snapshot cache.
- Metrics/logs include dynamic snapshot health/state.
- Delivery board, session brief, changelog, and docs are updated.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - closed `T-016`:
    - added `services.nixCsf.dynamicOffenders` options:
      - `enable`, `url`, `failOpen`, `requireHTTPS`,
      - `authTokenFile`, `nodeId`,
      - `defaultEntryTTLSeconds`, `maxEntries`,
    - runtime dynamic snapshot pipeline in `scripts/nix-csf-apply.sh`:
      - fetch + cache + schema validation,
      - strict/fail-open behavior for fetch/schema/cache-age failures,
      - snapshot TTL (`ttlSeconds`) cache-age guard,
      - per-entry TTL resolution (`ttlSeconds`/`expiresAt` fallback to default TTL),
      - nft timeout set rendering (`dynamic_ban_ipv4`, `dynamic_ban_ipv6`),
    - observability updates:
      - structured `dynamic_offenders_meta` event,
      - Prometheus metrics for dynamic feature/source/counts and snapshot health,
    - tests:
      - smoke suite asserts timeout rendering, expired-entry exclusion, and allow-vs-dynamic precedence order,
      - integration suite adds strict expired-cache failure scenario (`dynamicexpired` node),
    - docs updated:
      - README, architecture, roadmap, and use-case catalog.
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Next ticket candidate:
  - `T-021` firewall coexistence profile (Docker + dynamic daemons), then `T-020`.
