# Session Brief

Last updated: 2026-02-20  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-020` (Cluster auth/token lifecycle and secret handling).
- Goal: deliver secure token rotation and secret handling for cluster policy and dynamic offender endpoints without breaking strict-mode behavior.
- In scope:
  - add ordered auth token rotation options:
    - `services.nixCsf.clusterPolicy.authTokenFiles`,
    - `services.nixCsf.dynamicOffenders.authTokenFiles`,
  - enforce secret file safety checks in runtime:
    - existence/readability checks,
    - permission hardening (no group/other access),
    - non-empty and whitespace-free token values,
  - implement ordered fetch fallback (try token candidates sequentially),
  - expose auth fallback observability in logs and metrics,
  - expand integration tests with auth-rotation fixture coverage,
  - update README/architecture/use-cases/board/changelog docs.
- Out of scope:
  - Grafana/Prometheus monitoring pack (`T-019`),
  - ICMP per-type/per-rate controls (`T-017`),
  - hybrid local-file + remote list reconciliation (`T-022`).
- Stop/rollback condition:
  - any regression that weakens strict fail-closed semantics or allows insecure secret-file handling.

## 2) Definition of done

- Rotation-capable auth options are available and validated in module assertions.
- Runtime supports legacy single-token mode and ordered multi-token fallback mode.
- Secret-file checks reject insecure permissions and malformed tokens.
- Logs/metrics expose candidate counts and selected token slot.
- Integration tests validate rotation fallback for both cluster and dynamic sources.
- Delivery board, session brief, changelog, and docs are updated.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - closed `T-020`:
    - added module options:
      - `services.nixCsf.clusterPolicy.authTokenFiles`,
      - `services.nixCsf.dynamicOffenders.authTokenFiles`,
    - added eval-time assertions:
      - `authTokenFiles` entries must be absolute paths,
      - `authTokenFile` cannot be combined with `authTokenFiles`,
    - implemented runtime token lifecycle in `scripts/nix-csf-apply.sh`:
      - auth token file validation (`exists`, `readable`, strict mode bits),
      - token content validation (non-empty, no whitespace),
      - ordered bearer-token fallback on fetch (`slot 1..N`),
      - compatibility mapping from legacy `authTokenFile` to candidate list,
    - observability updates:
      - structured `auth_fallback_success` event,
      - auth fields in `cluster_policy_meta` and `dynamic_offenders_meta`,
      - Prometheus metrics:
        - `nix_csf_auth_token_candidates{source=...}`,
        - `nix_csf_auth_token_selected_slot{source=...}`,
    - expanded integration test coverage (`tokenrotation` node):
      - auth-protected fixture endpoint requiring rotated tokens,
      - deterministic fallback-from-slot-1-to-slot-2 validation,
      - cache revision + nft rendering assertions after refresh,
      - metrics assertions for candidate count and selected slot.
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-smoke" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Next ticket candidate:
  - `T-019` Grafana/Prometheus monitoring pack, then `T-017`.
