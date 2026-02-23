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
  - `T-029` LFD-like detector POC (Nix-native),
  - `T-028` legacy CSF list import bridge,
  - `T-013` troubleshooting command set + runbook,
  - `T-018` country allow-by-port parity (`CC_ALLOW_PORTS`),
  - `T-017` ICMP policy profiles (legacy/off/safe/diagnostic/open + optional rate limits).
- Validation model:
  - agent runs fast/lint/eval locally,
  - operator runs full VM suite (`./scripts/validate.sh`) and shares failures only.
- Newly triaged next-ticket set (CSF/LFD parity):
  - `T-028` legacy CSF list import bridge,
  - `T-030` fail2ban adapter/coexistence profile.

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

## 9) Backlog Triage LFD-NIX-WAY

- Scope delivered:
  - converted CSF/LFD parity questions into tracked engineering tickets:
    - `T-028` (`csf.allow/csf.deny/csf.ignore` migration bridge),
    - `T-029` (Nix-native LFD-like detector pipeline),
    - `T-030` (fail2ban adapter with single-writer firewall contract),
  - added `docs/LFD_NIX_WAY_POC.md` for implementation guardrails and acceptance boundaries,
  - updated board/roadmap/changelog priority ordering for release planning.
- Validation evidence:
  - documentation-only triage update.

## 10) Batch CSF-IMPORT-BRIDGE-028

- Scope delivered:
  - added migration tool `nix-csf-import-csf` for legacy `csf.allow/csf.deny/csf.ignore`,
  - added unsupported-line report output (line-number + reason) for non-CIDR CSF syntax,
  - added generated Nix snippet output for `services.nixCsf.localFiles` wiring,
  - integrated flake checks/package outputs and updated migration docs/examples.
- Validation evidence:
  - `bash -n scripts/nix-csf-import-csf.sh`
  - `./scripts/validate-fast.sh`

## 11) Batch LFD-DETECTOR-029

- Scope delivered:
  - added LFD-like detector tool `nix-csf-lfd-detector` (`scripts/nix-csf-lfd-detector.sh`),
  - added module API `services.nixCsf.lfdDetector.*` with explicit on/off toggle, thresholds, scheduling, endpoint/auth, and metrics options,
  - wired `nix-csf-lfd-detector.service` + `nix-csf-lfd-detector.timer`,
  - integrated detector path with control-plane write API (`nix-csfctl ban-temp`) and optional post-write refresh trigger,
  - added eval/lint coverage updates:
    - `checks.<system>.eval-lfd-detector`,
    - shellcheck coverage for detector script,
  - extended integration scenario with detector-driven temp-ban verification and metrics checks,
  - updated docs/examples:
    - `docs/LFD_DETECTOR.md`,
    - `README.md`,
    - `docs/USE_CASES.md`,
    - board/roadmap/changelog artifacts.
- Validation evidence:
  - `bash -n scripts/nix-csf-lfd-detector.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`
