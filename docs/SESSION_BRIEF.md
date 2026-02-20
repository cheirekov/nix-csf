# Session Brief

Last updated: 2026-02-20  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-015` (Cluster policy schema v2).
- Goal: deliver schema v2 semantics for centralized lists and close strict TTL behavior with integration evidence.
- In scope:
  - extend cluster payload contract with `ignore*`, `schemaVersion`, `revision`, `ttlSeconds`,
  - enforce schema validation + cache TTL behavior in runtime apply/refresh,
  - expose cluster schema/TTL metadata in logs and metrics,
  - add VM checks for ignore precedence and strict TTL fail-closed behavior,
  - publish architecture POC recommendation for dynamic cluster workflow and Docker coexistence.
- Out of scope:
  - dynamic offender propagation runtime pipeline (`T-016`),
  - Docker coexistence implementation (`T-021`),
  - ICMP type/rate controls (`T-017`).
- Stop/rollback condition:
  - any regression in strict `clusterPolicy.failOpen = false` behavior or existing integration scenarios.

## 2) Definition of done

- Cluster policy schema v2 keys are accepted and validated.
- `ignore` lists can override deny-style overlays safely.
- Cache TTL behavior is explicit and fail-closed in strict mode.
- Integration tests include stale-cache strict failure and pass.
- Delivery board, changelog, and architecture/docs are updated with next-priority handoff.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - closed `T-015`:
    - runtime supports cluster policy v2 fields:
      - `ignoreIPv4`, `ignoreIPv6`,
      - `schemaVersion`, `revision`, `ttlSeconds`,
    - schema validation added for fetched/cached cluster policy,
    - TTL cache guard implemented with strict fail-closed semantics,
    - cluster ignore precedence implemented (subtract from deny-style sources, merge into allow),
    - cluster schema/TTL metadata exposed in structured logs and metrics,
    - smoke test expanded for ignore precedence and schema metrics,
    - integration suite expanded with `clusterexpired` stale-cache strict scenario,
    - fixed regression in fail-open parsing where explicit `clusterPolicy.failOpen = false` was being coerced to `true`.
  - architecture/product follow-through:
    - added `docs/DYNAMIC_CLUSTER_POC.md` with team recommendation for:
      - CSF-style dynamic ban propagation,
      - local-files + remote snapshot reconciliation,
      - token lifecycle handling,
      - Docker coexistence posture,
      - Grafana/Prometheus monitoring model.
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
- Next ticket candidate:
  - `T-016` dynamic offender propagation, then `T-021` Docker/dynamic-daemon coexistence profile.

