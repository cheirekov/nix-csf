# Cluster Control-Plane POC (Retro + Design)

Last updated: 2026-02-20  
Owners: Security Architect + Nix Module Engineer + SRE + PM/BA
Status: baseline implemented (`T-024`), escalation PoC completed (`T-026`), operator workflow (`T-025`) in progress.

## 1) Objective

Define a practical "remote place" and operator workflow for cluster policy management that feels closer to CSF day-2 operations:

- add/remove `allow`/`deny`/`ignore` from an approved node or a master node,
- propagate dynamic temporary bans cluster-wide,
- support deterministic promotion from repeated temporary bans to permanent deny,
- preserve current Nix declarative model and runtime pull safety.

## 2) Retro of current implementation

## 2.1 What is already good

- Strong pull-based cluster model exists (`clusterPolicy` + `dynamicOffenders`).
- Strict/fail-open behavior is explicit and tested.
- Snapshot metadata (`revision`, `ttlSeconds`) and auth rotation are implemented.
- Dynamic bans support per-entry expiry in nft timeout sets.

## 2.2 Current gap vs CSF-like operator workflow

- No built-in write API/CLI to mutate cluster lists.
- No built-in "local command on node A => fan-out to all nodes" workflow.
- No built-in escalation policy (`N` temp bans => permanent deny).
- Remote JSON producer/control-plane is currently external to this repo.

## 3) Remote place options (POC)

### Option A: Git-backed snapshots (fastest initial)

- Source of truth: Git repo with JSON state.
- Distribution: static HTTP endpoint (Caddy/Nginx/object storage).
- Mutations: pull request or signed commit from approved operators.

Pros:

- easy audit trail,
- low complexity,
- easy rollback by revision.

Cons:

- slower operational loop,
- no built-in online mutation API,
- harder to drive automated escalation.

### Option B: Master control-plane service (recommended)

- Source of truth: service DB (SQLite for PoC, Postgres for scale).
- Distribution: generated immutable snapshots at stable URLs consumed by `nix-csf`.
- Mutations: authenticated API + CLI (`nix-csfctl`) from approved nodes.

Pros:

- closest to CSF operational experience,
- enables policy + dynamic workflows + escalation,
- keeps pull model unchanged for clients.

Cons:

- requires service operation and auth hardening.

### Option C: Distributed KV/service mesh first

- etcd/Consul/NATS-driven state.

Pros:

- high flexibility.

Cons:

- complexity too high for first PoC.

Team recommendation: start with Option B, keep Option A as fallback bootstrap.

## 4) Recommended PoC architecture (Option B)

Components:

1. `nix-csf-control-plane` service (master):
   - authoritative policy state,
   - dynamic offender/event state,
   - snapshot renderer.
2. `nix-csfctl` CLI:
   - policy mutation commands,
   - runs on master or approved cluster nodes.
3. Existing `nix-csf` clients:
   - continue pull/refresh from `clusterPolicy.url` and `dynamicOffenders.url`.

Snapshot endpoints (read-only for clients):

- `GET /snapshots/<env>/cluster-policy.json`
- `GET /snapshots/<env>/dynamic-offenders.json`

Mutation API endpoints (write):

- `POST /v1/policy/allow`
- `POST /v1/policy/deny`
- `POST /v1/policy/ignore`
- `DELETE /v1/policy/{allow|deny|ignore}`
- `POST /v1/offenders/ban-temp`
- `POST /v1/offenders/unban`

## 5) Escalation model PoC (`N` temp bans => permanent deny)

Proposed deterministic rule:

- key: source CIDR (`/32` or `/128`),
- window: rolling `W` minutes,
- threshold: `N` temporary ban events,
- action: move IP/CIDR to permanent deny set in cluster policy state,
- cooldown: optional manual review flag before auto-promotion (toggle).

Audit fields:

- `firstSeen`, `lastSeen`, `eventCountWindow`, `promotedAt`, `promotedBy`, `reason`.

## 6) Nix-way integration boundary

Keep this split:

- Declarative Nix: where to pull policy from, safety semantics, auth files, refresh cadence.
- Runtime control-plane: mutable cluster state and event-driven updates.

This preserves reproducibility while enabling day-2 operations.

## 7) Ticket breakdown

- `T-024`: control-plane + snapshot publisher PoC.
- `T-025`: `nix-csfctl` mutation workflow PoC (master + approved node usage).
- `T-026`: escalation policy PoC with deterministic promotion/audit.

## 8) Acceptance criteria (high-level)

For `T-024`:

- control-plane can publish valid v2 cluster policy and dynamic offender snapshots.
- `nix-csf` clients refresh successfully against PoC endpoints.

For `T-025`:

- operator can run one command to add/remove `allow|deny|ignore`.
- snapshot revision increments and propagates to clients.

For `T-026`:

- repeated temp bans for same source trigger promotion according to configured `N/W`.
- promotion appears in cluster policy deny snapshot and is auditable.
