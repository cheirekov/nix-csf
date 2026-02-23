# Session Brief

Last updated: 2026-02-23  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `IMPLEMENTATION`
- Active ticket: `T-024` (Cluster control-plane and snapshot publisher POC).
- Goal: deliver an in-repo mutable control-plane PoC that can back both:
  - cluster pull clients, and
  - single-node local mutable workflows (runtime state outside declarative rebuild output).
- In scope:
  - control-plane service implementation and module wiring,
  - snapshot + mutation API for allow/deny/ignore and temporary bans,
  - integration/eval/lint coverage updates,
  - documentation and board/changelog updates.
- Out of scope:
  - escalation policy (`T-026`),
  - operator CLI (`T-025`),
  - hybrid local-files reconciliation (`T-022`).

## 2) Definition of done

- `services.nixCsf.controlPlane.*` options available and evaluated.
- Optional `nix-csf-control-plane.service` starts and serves snapshots.
- API mutations are reflected in downstream refresh + nft state.
- Documentation states mutable runtime-state boundary (`/var/lib/...` survives rebuilds).

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - added control-plane implementation:
    - `scripts/nix-csf-control-plane.py`,
  - added module option/service wiring:
    - `services.nixCsf.controlPlane.*`,
    - `systemd.services.nix-csf-control-plane`,
    - tmpfiles/runtime packaging/assertions,
  - extended integration scenario:
    - `controlplanepoc` node covers mutation API -> refresh -> nft update flow,
    - docker coexist test hardened with explicit docker service path for `nft` and higher start timeout for slow VM hosts,
  - added eval/lint checks:
    - `checks.<system>.eval-control-plane`,
    - `checks.<system>.control-plane-lint`,
    - validate script wiring,
  - updated docs:
    - `README.md`,
    - `docs/ARCHITECTURE.md`,
    - `docs/DELIVERY_BOARD.md`,
    - `docs/ROADMAP.md`.
- Validation evidence:
  - `bash -n scripts/validate.sh`
  - `python3 -m py_compile scripts/nix-csf-control-plane.py`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-control-plane" "path:/home/yc/work/nix-csf#checks.x86_64-linux.control-plane-lint" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.nix-csf-integration" --print-build-logs` (executed in no-KVM/TCG runner; long-running)
- Next ticket candidate:
  - `T-026` dynamic escalation policy (`N` temporary bans => permanent deny) with explicit local-only mode support.

## 4) Interrupt Hotfix — T-027

- Severity: `P0`
- Trigger:
  - operator-reported risk that country/blocklist source ingestion might not work reliably.
- Resolution:
  - updated default Spamhaus URLs to current DROP endpoints,
  - parser now supports semicolon-annotated lines and ipset-style `add` lines,
  - smoke suite expanded with deterministic fixtures for both blocklist and country feed parsing.
- Validation:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`

## 5) Current execution lane

- Active ticket: `T-022` (`IN_PROGRESS`) — hybrid local-files + remote reconciliation contract.
- Recently completed:
  - `T-013` troubleshooting command set + runbook,
  - `T-018` country allow-by-port parity (`CC_ALLOW_PORTS`),
  - `T-017` ICMP policy profiles (legacy/off/safe/diagnostic/open + optional rate limits).
- Validation model:
  - agent runs fast/lint/eval locally,
  - operator runs full VM suite (`./scripts/validate.sh`) and shares failures only.

## 6) Batch ICMP-PROFILES-017

- Scope delivered:
  - implemented `services.nixCsf.icmp.profile` runtime semantics in apply pipeline,
  - added optional rate limiting for profile-generated ICMP rules,
  - preserved legacy `allowICMP` behavior under `icmp.profile = "legacy"`,
  - added ICMP profile/rate-limit metrics and test coverage.
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`

## 7) Batch COUNTRY-PORT-ALLOW-018

- Scope delivered:
  - added `services.nixCsf.country.portAllow` option family (`CC_ALLOW_PORTS` parity),
  - implemented apply/runtime support for country-scoped port-allow enforcement in input and docker-coexist forward chains,
  - added port-allow metrics (`feature`, `set_entries`, `source_count`) and smoke coverage,
  - updated docs/examples/board artifacts for operator usage and ticket closure.
- Validation evidence:
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`

## 8) Batch TROUBLESHOOTING-RUNBOOK-013

- Scope delivered:
  - added operator snapshot command `nix-csf-triage` (`scripts/nix-csf-triage.sh`),
  - packaged/installed triage tool through module + flake package outputs,
  - added `docs/TROUBLESHOOTING.md` with symptom-driven command flows and handoff guidance,
  - linked troubleshooting workflow from README/monitoring docs and closed board roadmap item.
- Validation evidence:
  - `bash -n scripts/nix-csf-triage.sh`
  - `bash -n scripts/nix-csf-apply.sh`
  - `./scripts/validate-fast.sh`
