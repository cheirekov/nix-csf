# Epic: Firewall Ownership + LFD Expansion

Last updated: 2026-02-25
Owner roles: PM/BA, Security Architect, Nix Module Engineer, Threat Intel Engineer, QA/Release Engineer

## Goal

Deliver `nix-csf` as the primary declarative firewall for NixOS hosts that need:

- input + forward + output policy control,
- gateway/NAT use cases,
- detector/escalation workflows beyond SSH,
- cluster-safe propagation of dynamic and permanent actions.

## Team decision summary

- Keep the single-writer model: `nix-csf` remains firewall state authority.
- Preserve explicit coexistence profiles for Docker/dynamic daemons.
- Introduce new datapath features as opt-in modules with safe defaults (`off`).
- Keep Stage 1 (firewall ownership features) and Stage 2 (detector/escalation expansion) independent enough to release incrementally.

## Stage 1 (firewall ownership)

### T-040 NAT datapath foundation

Acceptance focus:

- declarative SNAT/masquerade policy for routed internal networks,
- declarative DNAT/port-forward rules,
- no behavior change unless NAT options are enabled,
- integration checks prove generated nftables syntax and service apply success.

Initial scope boundaries:

- IPv4-first NAT support,
- explicit interfaces/cidrs in rules,
- no implicit wildcard NAT to avoid accidental exposure.

### T-041 Forwarding policy matrix

Acceptance focus:

- interface/zone-aware forward allow rules,
- clear deny-by-default and explicit allow transitions,
- compatibility with `coexistence.profile = "docker-coexist"` behavior.

### T-042 Optional egress policy controls

Acceptance focus:

- optional output restrictions (default remains current permissive path),
- allowlist-first model to reduce accidental breakage,
- operator lockout guardrails documented and tested.

## Stage 2 (detector/escalation expansion)

### T-043 LFD detector framework v2

Acceptance focus:

- generic detector abstraction for multiple journal sources,
- consistent event model into control-plane mutation path,
- detector-specific thresholds/windows.

### T-044 Built-in detector pack v2

Acceptance focus:

- extend beyond SSH-only path,
- curated detector profiles for common server services,
- per-detector enable/disable and threshold tuning.

### T-045 Escalation engine v2

Acceptance focus:

- unified temporary-ban and permanent-promotion workflow,
- policy knobs for threshold, time window, cooldown, reason classes,
- deterministic audit trail.

### T-046 Cluster propagation semantics v2

Acceptance focus:

- configurable sharing policy for temporary/permanent decisions,
- provenance metadata and replay-safe behavior,
- clear local-only vs cluster-wide action boundaries.

## Cross-cutting tickets

### T-047 Integration test expansion

- Gateway/NAT forwarding flows.
- Detector/escalation/cluster propagation flows.

### T-048 Documentation and deployment blueprints

- Gateway host example.
- Bastion host with restricted egress.
- Application host with multi-detector profile.
- Cluster policy sharing examples.

### T-049 Release-candidate hardening

- Burn-in validation guidance (KVM primary, TCG fallback notes).
- Documentation freeze checklist.
- Evidence packaging before release recommendation.

### T-050 Release-candidate decision package

- Explicit go/no-go recommendation based on hardening evidence.
- Cut checklist and rollback framing for first production tag.

## Validation model for this epic

- Agent lane: `./scripts/validate-agent.sh`
- Operator lane (manual): `./scripts/validate-capture.sh`
- Ticket closure rule: operator full-validation evidence required for runtime-changing tickets.
