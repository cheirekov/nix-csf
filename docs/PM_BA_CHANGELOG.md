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
