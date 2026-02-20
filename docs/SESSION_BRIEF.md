# Session Brief

Last updated: 2026-02-20  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-012` (Preset threat profiles).
- Goal: deliver easy profile-based defaults (`server`, `workstation`, `edge`) with explicit override precedence.
- In scope:
  - add `services.nixCsf.threatProfile` API and profile documentation,
  - define profile defaults using `mkDefault` to preserve explicit host overrides,
  - add lightweight profile-eval check coverage for all profiles and override precedence,
  - extend VM integration coverage with an `edge` profile runtime scenario,
  - align board/changelog/docs with ticket closure and next-priority handoff.
- Out of scope:
  - cluster schema v2 (`T-015`),
  - dynamic offender propagation (`T-016`),
  - ICMP policy profile expansion (`T-017`).
- Stop/rollback condition:
  - regressions in existing smoke/integration checks or profile behavior violating explicit-option precedence.

## 2) Definition of done

- `services.nixCsf.threatProfile` exists with `custom|server|workstation|edge`.
- Profile defaults are applied only as `mkDefault`; explicit user options win.
- Validation covers all profiles (`eval-profiles`) and runtime `edge` rendering.
- README/use-case/architecture docs include profile guidance.
- Delivery board and changelog reflect `T-012` completion and next priority (`T-015`).

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - closed `T-012`:
    - added `services.nixCsf.threatProfile`:
      - `custom` (current baseline behavior),
      - `server` (balanced flood controls + drop logging + hourly refresh default),
      - `workstation` (no inbound open TCP/UDP defaults),
      - `edge` (22/443 TCP + 53/51820 UDP + stricter SYN flood baseline),
    - implemented profile defaults via `mkDefault` so explicit host values override profile values,
    - added flake check `checks.<system>.eval-profiles` to validate server/workstation defaults and edge override precedence,
    - extended integration VM suite with `profileedge` runtime assertions,
    - updated README and use-case documentation with profile examples.
- Validation evidence:
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs`
  - `./scripts/validate.sh`
- Next ticket candidate:
  - `T-015` cluster policy schema v2 (`allow`/`deny`/`ignore` + revision/TTL), then `T-016`.
