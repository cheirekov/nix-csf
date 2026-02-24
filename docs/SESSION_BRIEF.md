# Session Brief

Last updated: 2026-02-24  
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

- Active ticket: none (`WIP` slot open).
- Recently completed:
  - `T-023` Netdata monitoring integration,
  - `T-030` fail2ban adapter/coexistence profile,
  - `T-029` LFD-like detector POC (Nix-native),
  - `T-028` legacy CSF list import bridge,
  - `T-013` troubleshooting command set + runbook,
  - `T-018` country allow-by-port parity (`CC_ALLOW_PORTS`),
  - `T-017` ICMP policy profiles (legacy/off/safe/diagnostic/open + optional rate limits).
- Validation model:
  - agent runs fast/lint/eval locally,
  - operator runs full VM suite (`./scripts/validate.sh`) and shares failures only.
- Newly triaged next-ticket set (CSF/LFD parity):
  - release-candidate hardening (ticket `TBD`; VM burn-in stability + docs freeze).

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

## 12) Batch FAIL2BAN-ADAPTER-030

- Scope delivered:
  - added fail2ban adapter command `nix-csf-fail2ban-action` (`scripts/nix-csf-fail2ban-action.sh`),
  - added module API `services.nixCsf.fail2banAdapter.*`,
  - generated fail2ban action file wiring:
    - `/etc/fail2ban/action.d/<actionName>.local`,
  - added flake/package/check integration:
    - `checks.<system>.eval-fail2ban-adapter`,
    - package output `fail2ban-action`,
    - shellcheck coverage for adapter script,
  - extended integration test flow with adapter-driven ban/unban assertions through
    control-plane dynamic snapshots and rendered timeout rules,
  - added documentation:
    - `docs/FAIL2BAN_ADAPTER.md`,
    - README + use-case updates.
- Validation evidence:
  - `bash -n scripts/nix-csf-fail2ban-action.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-fail2ban-adapter" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`

## 13) Batch NETDATA-INTEGRATION-023

- Scope delivered:
  - added Netdata collector plugin:
    - `scripts/nix-csf-netdata.chart.sh`,
  - added module API `services.nixCsf.netdata.*`:
    - enable, metricsFile override, update interval, chart priority, health alarm install toggle, alert recipient,
  - wired Netdata integration declaratively when enabled:
    - `services.netdata.extraPluginPaths` includes generated plugin package,
    - generated collector config: `/etc/netdata/conf.d/charts.d/nix_csf.conf`,
    - generated alarms: `/etc/netdata/conf.d/health.d/nix_csf.conf`,
  - added module assertions:
    - requires `services.netdata.enable = true`,
    - requires `services.nixCsf.observability.metrics.enable = true`,
    - validates absolute metrics file path,
  - added evaluation/lint coverage:
    - `checks.<system>.eval-netdata`,
    - shellcheck coverage for `nix-csf-netdata.chart.sh`,
    - validate scripts include `eval-netdata`,
  - updated docs:
    - `docs/NETDATA.md`,
    - `docs/MONITORING.md`,
    - `README.md`,
    - `docs/USE_CASES.md`,
    - board/roadmap/changelog artifacts.
- Validation evidence:
  - `bash -n scripts/nix-csf-netdata.chart.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.shellcheck" --print-build-logs`
  - `./scripts/validate-fast.sh`

## 14) Batch NETDATA-METRICS-READABILITY-031

- Scope delivered:
  - fixed non-root collector access to `/var/lib/nix-csf/metrics.prom` by making parent directory traversal possible without directory listing (`/var/lib/nix-csf` -> `0751` when metrics are enabled),
  - preserved cache directory protection (`/var/lib/nix-csf/cache` remains `0750 root:root`),
  - added eval check coverage to guard tmpfiles mode for Netdata-enabled evaluation,
  - updated Netdata and use-case runbooks with explicit `sudo -u netdata test -r /var/lib/nix-csf/metrics.prom` verification.
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`

## 15) Batch NETDATA-CHARTSD-PATH-032

- Scope delivered:
  - fixed Netdata charts.d collector startup failure by extending `systemd.services.netdata.path` with `services.netdata.package` when `services.nixCsf.netdata.enable = true`,
  - added eval guard that asserts netdata package path inclusion in service PATH for Netdata-enabled evaluation,
  - documented known failure mode (`systemd-cat-native: command not found`) and mitigation in Netdata runbook.
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
