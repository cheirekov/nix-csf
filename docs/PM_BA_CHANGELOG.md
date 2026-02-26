# PM/BA Changelog

## 2026-02-25 — `T-046` closure (operator full-validation confirmed)

- Ticket(s): `T-046` (`DONE`)
- Summary:
  - operator reported full validation success (`[nix-csf] validation succeeded`) after propagation semantics v2 rollout,
  - propagation v2 accepted with:
    - local vs cluster sharing boundaries,
    - provenance metadata and replay-safe snapshot marker behavior.
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - Stage-2 lane advanced to `T-047` (integration expansion).

## 2026-02-25 — Batch INTEGRATION-EXPANSION-047 (implementation lane)

- Ticket(s): `T-047` (`IN_PROGRESS`)
- Summary:
  - expanded integration test coverage with a dedicated gateway+detector scenario:
    - added `gatewaydetector` node in `tests/integration.nix`,
    - validates gateway semantics:
      - NAT table/rule generation,
      - forwarding matrix rendering for LAN->WAN flow,
      - egress default-drop policy rendering,
    - validates detector/escalation/cluster chain:
      - journal SSH failures -> LFD detector temp-ban mutation,
      - escalation promotion into cluster deny snapshot,
      - promoted CIDR present in nft deny set and absent from dynamic offender snapshot cache.
- BA requirement mapping:
  - directly advances `T-047` acceptance for combined gateway and detector/escalation coverage in VM integration flow.
- PM milestone mapping:
  - begins cross-cutting quality hardening before `T-048` documentation blueprint pass.
- Risk impact:
  - `low` (test-only expansion; runtime module behavior unchanged).
- Validation evidence (agent lane):
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required before moving `T-047` to `DONE`.

## 2026-02-25 — `T-045` closure (operator full-validation confirmed)

- Ticket(s): `T-045` (`DONE`)
- Summary:
  - operator reported full validation success (`[nix-csf] validation succeeded`) after escalation engine v2 rollout,
  - escalation v2 accepted with:
    - cooldown/reason-class governance,
    - deterministic promotion audit metadata.
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - Stage-2 lane advanced to `T-046` (cluster propagation semantics v2).

## 2026-02-25 — Batch PROPAGATION-V2-046 (implementation lane)

- Ticket(s): `T-046` (`IN_PROGRESS`)
- Summary:
  - implemented propagation semantics v2 in control-plane runtime:
    - scope-aware mutations (`cluster`/`local`) for policy and dynamic offender endpoints,
    - node-aware visibility boundaries with `X-Nix-Csf-Node` + payload `nodeId`,
    - provenance metadata in snapshots/audit (`scope`, `originNode`, `source`, `mutationId`, `updatedAt`),
    - replay-safe snapshot marker `lastMutationId`,
  - module/service wiring:
    - added `services.nixCsf.controlPlane.propagation.*` options,
    - control-plane ExecStart now emits propagation-v2 flags,
  - operator tooling:
    - `nix-csfctl` now supports global `--node-id`,
    - added mutation-level `--scope`, `--node-id`, `--source` arguments for relevant commands,
  - quality and coverage updates:
    - `eval-control-plane` asserts propagation-v2 flags,
    - integration scenario validates local-vs-cluster visibility and provenance metadata for node-a/node-b flows,
  - documentation updates:
    - `README.md`,
    - `docs/USE_CASES.md`,
    - `docs/CLUSTER_CONTROL_PLANE_POC.md`,
    - board/roadmap/session state transitions.
- BA requirement mapping:
  - satisfies `T-046` acceptance for controlled sharing boundaries, provenance metadata, and replay-safe marker exposure.
- PM milestone mapping:
  - advances Stage-2 cluster semantics hardening before Stage-2 integration/documentation expansion (`T-047`/`T-048`).
- Risk impact:
  - `medium` (control-plane mutation/snapshot semantics changed; pull-client schema remains backward-compatible).
- Validation evidence (agent lane):
  - `python3 -m py_compile scripts/nix-csf-control-plane.py`
  - `bash -n scripts/nix-csfctl.sh`
  - `./scripts/validate-agent.sh`
  - `nix build .#checks.x86_64-linux.control-plane-lint --print-build-logs`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required before moving `T-046` to `DONE`.

## 2026-02-25 — `T-044` closure (operator full-validation confirmed)

- Ticket(s): `T-044` (`DONE`)
- Summary:
  - operator reported full validation success (`[nix-csf] validation succeeded`) after built-in detector pack rollout,
  - detector pack v2 accepted with:
    - curated profile model (`server-basic/web/mail/hardened`),
    - per-detector tuning and resolved-detector guardrails.
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - Stage-2 lane advanced to `T-045` (escalation engine v2).

## 2026-02-25 — Batch ESCALATION-V2-045 (implementation lane)

- Ticket(s): `T-045` (`IN_PROGRESS`)
- Summary:
  - implemented escalation engine v2 in control-plane runtime:
    - new policy knobs:
      - `services.nixCsf.controlPlane.escalation.cooldownSeconds`,
      - `services.nixCsf.controlPlane.escalation.reasonClasses`,
    - cooldown-aware promotion suppression for repeated temp-ban events,
    - reason-class eligibility filter across detector/fail2ban/manual ban reasons,
    - deterministic promotion audit metadata:
      - monotonic `id`,
      - `reasonClass`,
      - `cooldownSeconds`,
      - `cooldownUntil`,
  - module and service wiring:
    - control-plane ExecStart now emits `--escalation-cooldown-seconds` and repeated `--escalation-reason-class` flags,
    - added assertion for `reasonClasses` token validity (non-empty, no whitespace),
  - quality and coverage updates:
    - `eval-control-plane` now asserts escalation v2 flags in rendered service command,
    - integration scenario expanded to validate:
      - reason-class exclusion path (`syn_flood`),
      - cooldown-active suppression for repeated promotions,
      - promotion audit metadata fields (`id`, `reasonClass`, cooldown fields),
  - documentation updates:
    - `README.md`,
    - `docs/LFD_DETECTOR.md`,
    - `docs/USE_CASES.md`.
- BA requirement mapping:
  - satisfies `T-045` acceptance for threshold/window/cooldown/reason-class controls and deterministic promotion audit trail.
- PM milestone mapping:
  - advances Stage-2 lane from detector-pack delivery to escalation-policy hardening.
- Risk impact:
  - `medium` (runtime promotion behavior changed; isolated to control-plane escalation path).
- Validation evidence (agent lane):
  - `python3 -m py_compile scripts/nix-csf-control-plane.py`
  - `bash -n scripts/validate.sh`
  - `bash -n scripts/nix-csfctl.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-control-plane" --print-build-logs`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector" "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector-pack" --print-build-logs`
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required before moving `T-045` to `DONE`.

## 2026-02-25 — `T-043` closure (operator full-validation confirmed)

- Ticket(s): `T-043` (`DONE`)
- Summary:
  - operator reported full validation success (`[nix-csf] validation succeeded`) after detector framework v2 rollout,
  - detector framework v2 accepted with:
    - multi-source detector model via `lfdDetector.detectors`,
    - runtime `--detectors-file` wiring,
    - per-detector metrics families.
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - Stage-2 lane advanced to `T-044` (built-in detector pack v2).

## 2026-02-25 — Batch DETECTOR-PACK-044 (implementation lane)

- Ticket(s): `T-044` (`IN_PROGRESS`)
- Summary:
  - implemented built-in detector pack v2 API:
    - added `services.nixCsf.lfdDetector.detectorPack.*`,
    - profile presets: `server-basic`, `server-web`, `server-mail`, `server-hardened`,
    - built-in detectors:
      - `ssh-auth`,
      - `nginx-auth`,
      - `dovecot-auth`,
    - per-detector tuning exposed for sources/filter/extract/threshold/window/ttl/reason,
  - resolution semantics/guardrails:
    - resolved detector precedence:
      - explicit `lfdDetector.detectors` (if non-empty),
      - else `lfdDetector.detectorPack` (if enabled),
      - else legacy single-detector fallback,
    - assertion added to prevent mixed config (`detectors` + `detectorPack.enable`),
    - detector validation assertions now target resolved detectors (name/source/extract),
  - quality and coverage updates:
    - integration scenario migrated from ad-hoc `app-auth` detector to built-in `nginx-auth` path,
    - added eval check `checks.<system>.eval-lfd-detector-pack` validating generated detectors-file content,
    - added detector-pack eval check to operator validation script,
  - documentation updates:
    - `README.md`,
    - `docs/LFD_DETECTOR.md`,
    - `docs/USE_CASES.md`.
- BA requirement mapping:
  - satisfies `T-044` acceptance for curated service detector profiles and per-detector threshold tuning.
- PM milestone mapping:
  - advances Stage-2 detector/escalation lane after `T-043` closure.
- Risk impact:
  - `medium` (detector-source defaults expanded; firewall writer contract unchanged).
- Validation evidence (agent lane):
  - `bash -n scripts/nix-csf-lfd-detector.sh`
  - `bash -n scripts/validate.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector" "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector-pack" --print-build-logs`
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required before moving `T-044` to `DONE`.

## 2026-02-25 — Batch DETECTOR-FRAMEWORK-043 (implementation lane)

- Ticket(s): `T-043` (`IN_PROGRESS`)
- Summary:
  - implemented LFD detector framework v2 with reusable multi-source detector model:
    - added `services.nixCsf.lfdDetector.detectors` API (name, source selectors, optional filter/extract regex, threshold/window/ttl/reason),
    - runtime service now passes generated detector definitions through `--detectors-file`,
    - legacy single-detector options (`sshdUnit`, `journalIdentifier`, `windowSeconds`, `threshold`, `banTTLSeconds`, `reason`) remain as fallback for compatibility,
  - detector runtime/compiler upgrades (`scripts/nix-csf-lfd-detector.sh`):
    - supports multiple enabled detectors per run,
    - detector-specific counting and ban emission while preserving unified control-plane mutation path,
    - per-detector metrics families (`*_by_detector`) plus detector-count metrics,
    - explicit detector-name/source guardrails and duplicate-name protection,
  - quality and coverage updates:
    - `eval-lfd-detector` now evaluates v2 detector definitions and asserts `--detectors-file` wiring,
    - integration scenario upgraded with two detectors (`ssh-auth`, `app-auth`) and end-to-end assertions for both ban paths,
  - documentation updates:
    - `README.md`, `docs/LFD_DETECTOR.md`, `docs/USE_CASES.md`, `docs/SCRIPTS_RUNBOOK.md`.
- BA requirement mapping:
  - satisfies `T-043` acceptance for generic detector abstraction with detector-specific thresholds/windows and consistent control-plane event path.
- PM milestone mapping:
  - starts Stage-2 delivery lane after `T-042` closure.
- Risk impact:
  - `medium` (detector runtime behavior expanded; firewall writer contract unchanged).
- Validation evidence (agent lane):
  - `bash -n scripts/nix-csf-lfd-detector.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-lfd-detector" --print-build-logs`
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required before moving `T-043` to `DONE`.

## 2026-02-25 — `T-042` closure (operator full-validation confirmed)

- Ticket(s): `T-042` (`DONE`)
- Summary:
  - operator provided full validation evidence after smoke assertion adjustment,
  - closure evidence: `[nix-csf] validation succeeded`,
  - Stage-1 egress controls accepted:
    - output policy model (`egress.*`),
    - egress sets/rules/metrics,
    - eval + smoke coverage.
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - Stage-2 lane advanced to `T-043` (detector framework v2).

## 2026-02-25 — Batch EGRESS-CONTROLS-042 (+ `T-041` closure)

- Ticket(s): `T-041` (`DONE`), `T-042` (`IN_PROGRESS`)
- Summary:
  - closed `T-041` after operator full-validation confirmation (`[nix-csf] validation succeeded`),
  - implemented Stage-1 optional egress model (`services.nixCsf.egress.*`) through runtime compiler:
    - output-chain policy is now driven by `egress.defaultPolicy` when `egress.enable = true`,
    - emits explicit output allow/deny sets (`egress_allow_*`, `egress_deny_*`),
    - enforces output-path controls for trusted interfaces, destination CIDRs, and destination TCP/UDP ports,
    - keeps lockout-safe default (`egress.enable = false` -> output policy accept),
  - observability and logging updates:
    - added egress set cardinality and source-count metrics,
    - added egress policy metric (`nix_csf_egress_policy{policy=*}`),
    - extended structured `set_counts` event with egress fields,
  - quality coverage updates:
    - added `checks.<system>.eval-egress`,
    - wired `eval-egress` into `scripts/validate.sh`,
    - extended smoke scenario with deterministic egress config + ruleset/metric assertions,
  - documentation/process updates:
    - README/architecture/use-cases/troubleshooting updates for egress behavior and runbook checks,
    - board/roadmap/session artifacts aligned to `T-042` active lane.
- BA requirement mapping:
  - delivers requested optional hardened egress path while preserving default-safe outbound behavior.
- PM milestone mapping:
  - closes Stage-1 forwarding ticket (`T-041`) and advances Stage-1 epic to `T-042`.
- Risk impact:
  - `medium` (new output-chain behavior when explicitly enabled).
- Validation evidence (agent lane):
  - `bash -n scripts/nix-csf-apply.sh`
  - `bash -n scripts/validate.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-egress" --print-build-logs`
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - operator full-validation evidence (`./scripts/validate-capture.sh`) required to move `T-042` from `IN_PROGRESS` to `DONE`.

## 2026-02-25 — Batch FORWARD-MATRIX-041 (implementation lane)

- Ticket(s): `T-041` (`IN_PROGRESS`)
- Summary:
  - implemented Stage-1 forwarding matrix model for routed traffic:
    - new module API:
      - `services.nixCsf.forwarding.zones`,
      - `services.nixCsf.forwarding.rules`,
    - zone-to-zone rule semantics with optional interface/CIDR/port selectors,
  - runtime compiler changes:
    - parses forwarding zones/rules from runtime JSON,
    - validates forwarding selectors (zone references, interface tokens, CIDR family, protocol/port contract),
    - renders explicit forward-chain accept clauses from forwarding matrix,
    - adds forwarding feature/source metrics:
      - `nix_csf_feature_enabled{feature="forwarding_matrix"}`,
      - `nix_csf_source_count{source="forwarding_*"}`,
    - adds triage keyword coverage for forwarding lines,
  - safety guardrails:
    - forwarding rules require `forwardPolicy = "drop"` for explicit allow posture,
    - forwarding matrix is blocked with `coexistence.profile = "docker-coexist"` in Stage 1,
  - quality coverage:
    - new eval check `checks.<system>.eval-forwarding`,
    - smoke scenario includes zone-based forwarding rules and forwarding metrics assertions,
  - updated docs/runbooks:
    - `README.md`, `docs/USE_CASES.md`, `docs/TROUBLESHOOTING.md`, `docs/ARCHITECTURE.md`.
- BA requirement mapping:
  - delivers requested interface/zone-aware forwarding allow model in declarative Nix API.
- PM milestone mapping:
  - executes second Stage-1 ticket from epic plan (`T-041`).
- Risk impact:
  - `medium` (new forward datapath behavior; constrained by explicit opt-in and guardrails).
- Validation evidence (agent lane):
  - `./scripts/validate-agent.sh`
  - `bash -n scripts/nix-csf-apply.sh`
  - `bash -n scripts/nix-csf-triage.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-forwarding" --print-build-logs`
- Open follow-ups:
  - operator full-validation evidence required (`./scripts/validate-capture.sh`) before moving `T-041` to `DONE`.

## 2026-02-25 — Batch NAT-FOUNDATION-040 (implementation lane)

- Ticket(s): `T-040` (`DONE`)
- Summary:
  - implemented Stage-1 NAT foundation in module + runtime pipeline:
    - new module API: `services.nixCsf.nat.*`,
    - IPv4 masquerade support (`nat.masquerade`),
    - explicit IPv4 port-forward DNAT rules (`nat.portForwards`),
  - runtime compiler changes:
    - renders additional `table ip nix_csf_nat` (`prerouting` + `postrouting`),
    - emits NAT-linked forward accept rules in `chain forward`,
    - adds NAT feature/source metrics (`nix_csf_feature_enabled{feature="nat_*"}`, `nix_csf_source_count{source="nat_*"}`),
    - extends triage signal extraction for NAT lines (`dnat/masquerade`),
  - added safety boundaries/assertions:
    - NAT is opt-in and requires `nat.externalInterface`,
    - IPv4-only validation for Stage-1 sources/destinations,
    - guardrail: NAT blocked with `coexistence.profile = "docker-coexist"` in this stage,
  - added quality coverage:
    - new check `checks.<system>.eval-nat`,
    - smoke scenario now includes NAT rules and metric assertions,
  - updated docs/runbooks:
    - `README.md`, `docs/USE_CASES.md`, `docs/TROUBLESHOOTING.md`, `docs/ARCHITECTURE.md`.
- BA requirement mapping:
  - starts requested epic direction where nix-csf is primary firewall owner for gateway-style traffic flows.
- PM milestone mapping:
  - executes first implementation ticket from epic plan (`T-040`).
- Risk impact:
  - `medium` (new datapath behavior; constrained by explicit opt-in and assertions).
- Validation evidence (agent lane):
  - `bash -n scripts/nix-csf-apply.sh`
  - `bash -n scripts/nix-csf-triage.sh`
  - `bash -n scripts/validate.sh`
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-nat" --print-build-logs`
  - `./scripts/validate-agent.sh`
- Closure note:
  - epic lane advanced to `T-041` after operator handoff/commit baseline, treating `T-040` implementation batch as complete for current branch state.
- Open follow-ups:
  - continue Stage-1 epic with `T-041`/`T-042`.

## 2026-02-25 — Batch EPIC-KICKOFF-039

- Ticket(s): `T-039`
- Summary:
  - initiated new epic focused on:
    - Stage 1: `nix-csf` as primary firewall datapath owner (NAT/forward/egress),
    - Stage 2: LFD detector/escalation expansion beyond SSH-only coverage,
  - created staged ticket sequence:
    - `T-040` NAT datapath foundation,
    - `T-041` forwarding policy matrix,
    - `T-042` optional egress controls,
    - `T-043` detector framework v2,
    - `T-044` built-in detector pack v2,
    - `T-045` escalation engine v2,
    - `T-046` cluster propagation semantics v2,
    - `T-047` integration-test expansion,
    - `T-048` documentation/deployment blueprints,
  - added epic charter doc with cross-role architecture guardrails:
    - `docs/EPIC_FIREWALL_LFD_EXPANSION.md`.
- BA requirement mapping:
  - aligns next delivery cycle to user-requested CSF-style firewall ownership plus broader LFD behavior in Nix style.
- PM milestone mapping:
  - creates executable staged backlog and acceptance sequencing for next implementation sessions.
- Risk impact:
  - `none` (planning/documentation only in this batch).
- Validation evidence:
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - start implementation with `T-040` in next batch.

## 2026-02-25 — Batch README-IA-038

- Ticket(s): `T-038`
- Summary:
  - refactored `README.md` into a docs-first entrypoint for faster operator navigation,
  - added clearer quick links and grouped documentation map (core, security/policy, integrations, migration, governance),
  - reduced inline README sprawl by keeping concise examples and moving deep paths to dedicated docs pages.
- BA requirement mapping:
  - improves first-read discoverability and lowers operator onboarding friction.
- PM milestone mapping:
  - release-candidate documentation hardening.
- Risk impact:
  - `none` (documentation-only).
- Validation evidence:
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - continue release-candidate hardening ticket.

## 2026-02-24 — Batch SCRIPT-RUNBOOK-COMPLETENESS-036

- Ticket(s): `T-036`
- Summary:
  - added a one-page script/runbook index with:
    - complete script matrix (purpose, command mapping, lane ownership),
    - per-script usage examples,
    - operator workflows for validation, migration, control-plane operations, triage, and release,
  - linked runbook from README project docs section.
- BA requirement mapping:
  - closes documentation completeness gap for script usage and operational handoff.
- PM milestone mapping:
  - release readiness hardening via explicit operator playbooks.
- Risk impact:
  - `none` (documentation-only).
- Validation evidence:
  - `./scripts/validate-agent.sh`
- Open follow-ups:
  - proceed to release-candidate hardening ticket.

## 2026-02-24 — T-035 closure (operator full-validation confirmed)

- Ticket(s): `T-035`
- Summary:
  - completed local list overlap/conflict audit lane and received operator full-validation evidence,
  - closure evidence provided by operator: `[nix-csf] validation succeeded`.
- Risk impact:
  - `low` (reporting/metrics only; firewall enforcement unchanged).
- Validation evidence:
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`.
- Open follow-ups:
  - proceed to release-candidate hardening ticket.

## 2026-02-24 — Batch LOCAL-LIST-AUDIT-035 (+ T-034 closure)

- Ticket(s): `T-034`, `T-035`
- Summary:
  - closed `T-034` after operator-provided full validation evidence (`[nix-csf] validation succeeded`),
  - completed `T-035` by implementing deterministic local list audit in apply pipeline:
    - `/var/lib/nix-csf/local-list-audit-summary.tsv` with duplicate/overlap counts,
    - `/var/lib/nix-csf/local-list-conflicts.tsv` with exact CIDR conflicts and resolution semantics,
    - structured audit event + warning on non-zero duplicates/overlaps,
    - Prometheus metrics for local duplicate and overlap cardinality by role/pair/family,
  - added smoke coverage for duplicate+overlap metrics and audit artifacts.
- BA requirement mapping:
  - explicit operator visibility for allow/deny/ignore conflicts during CSF migration and day-2 operations.
- PM milestone mapping:
  - post-1.0 production hardening lane for list-governance clarity.
- Risk impact:
  - `low` (observability/reporting additions; enforcement semantics remain unchanged).
- Validation evidence:
  - `./scripts/validate-agent.sh`
  - `bash -n scripts/nix-csf-apply.sh`
  - operator: `./scripts/validate-capture.sh` -> `[nix-csf] validation succeeded`
- Open follow-ups:
  - proceed to release-candidate hardening ticket.

## 2026-02-24 — Batch VALIDATION-LANE-SPLIT-037

- Ticket(s): `T-037`
- Summary:
  - formalized two validation lanes to reduce context/token burn and keep progress stable:
    - added `scripts/validate-agent.sh` (no `nix build`; shell + python syntax + `flake check --no-build`),
    - changed `scripts/validate-fast.sh` to delegate to `validate-agent.sh` for backward compatibility,
    - kept `scripts/validate.sh` and `scripts/validate-capture.sh` as operator-manual full-validation lane (`nix build` + VM tests),
  - updated team hard rules and README runbook so full `nix build` evidence is user-provided for ticket closure.
- BA requirement mapping:
  - predictable collaboration loop with explicit manual ownership of heavy test workloads.
- PM milestone mapping:
  - delivery throughput hardening before continuing `T-034` completion.
- Risk impact:
  - `low` (process/script lane split only; no firewall runtime behavior changes).
- Validation evidence:
  - `bash -n scripts/validate-agent.sh`
  - `bash -n scripts/validate-fast.sh`
  - `bash -n scripts/validate.sh`
- Open follow-ups:
  - continue `T-034`; close only after operator full-validation evidence (`./scripts/validate-capture.sh`).

## 2026-02-24 — Backlog triage LEGACY-IMPORT-AND-DOCS-034-036

- Ticket(s): `T-034`, `T-035`, `T-036`
- Summary:
  - reviewed production feedback after Netdata closure and CSF legacy import usage,
  - triaged advanced CSF allow-line compatibility gap (`advanced_port_rule`) into a dedicated parity ticket (`T-034`),
  - confirmed current dedupe behavior:
    - import stage dedupes each output via `sort -u`,
    - apply stage dedupes merged local overlays via normalized `sort -u`,
  - created follow-up ticket (`T-035`) for explicit overlap/conflict reporting instead of implicit dedupe only,
  - created documentation hardening ticket (`T-036`) for full script usage index + examples.
- BA requirement mapping:
  - migration parity, operator clarity, and production runbook maturity.
- PM milestone mapping:
  - post-1.0 patch stabilization and backlog quality gate.
- Risk impact:
  - `none` (triage and prioritization only; no runtime behavior change in this entry).
- Validation evidence:
  - board/session/changelog alignment updated.
- Open follow-ups:
  - execute `T-034` as next implementation lane.

## 2026-02-24 — Batch NETDATA-DISCOVERY-AND-PROCESS-HARDENING-033

- Ticket(s): `T-033`
- Summary:
  - fixed Netdata charts.d discovery path so `nix_csf.chart.sh` is actually discovered and loaded:
    - generate `/etc/netdata/conf.d/charts.d.conf` with `chartsd=/etc/netdata/conf.d/charts.d`,
    - install generated collector script at `/etc/netdata/conf.d/charts.d/nix_csf.chart.sh`,
    - keep generated collector parameters in `/etc/netdata/conf.d/charts.d/nix_csf.conf`,
  - retained prior hotfixes:
    - non-root metrics traversal (`/var/lib/nix-csf` mode `0751` when metrics enabled),
    - Netdata service PATH includes netdata package binaries (`systemd-cat-native` availability),
  - updated docs/runbooks to match real runtime wiring,
  - hardened process rules for continuous engineering mode:
    - mandatory same-batch docs + process artifact updates for all patches,
    - mandatory regression guard for each production hotfix.
- BA requirement mapping:
  - closes the observed gap where Netdata UI was reachable but `nix_csf.*` charts were absent.
- PM milestone mapping:
  - production patch hardening and process discipline reinforcement.
- Risk impact:
  - `low` (monitoring-path change; no firewall policy semantics changed).
- Validation evidence:
  - `nix build "path:/home/yc/work/nix-csf#checks.x86_64-linux.eval-netdata" --print-build-logs`
  - `nix flake check "path:/home/yc/work/nix-csf" --all-systems --no-build`
- Open follow-ups:
  - add VM integration assertion that Netdata charts API exposes `nix_csf.run_status`.

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
