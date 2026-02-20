# Dynamic Cluster POC (Nix Way)

Last updated: 2026-02-20  
Owners: Security Architect + Nix Module Engineer + SRE

## 1) Goal

Define a professional, Nix-idiomatic path for CSF-style dynamic behavior:

- temporary offender bans,
- cluster-wide sharing of allow/deny/ignore data,
- safe coexistence with other firewall/dynamic agents (especially Docker),
- clear observability and token/secret handling.

This document is a recommendation and POC contract. Baseline implementation now includes
`clusterPolicy` schema v2, dynamic offender snapshot propagation (`dynamicOffenders`), and
coexistence profiles (`coexistence.profile`, including `docker-coexist`), plus control-plane
snapshot publishing/mutation baseline (`controlPlane`, `T-024`).
Remaining items focus on escalation policy, operator workflow, and reconciliation hardening.

For the detailed remote-control-plane retro and write-path design, see
`docs/CLUSTER_CONTROL_PLANE_POC.md`.

## 2) Nix-way constraints

- Keep long-lived policy declarative in Nix (`services.nixCsf.*`).
- Treat dynamic bans as runtime state with explicit TTL, never as hidden permanent config.
- Make precedence deterministic and auditable.
- Keep host boot behavior deterministic for fail-open vs fail-closed modes.

## 3) Recommended architecture

### 3.1 Policy plane (declarative)

Source of truth in NixOS config:

- static lists (`allowIPv4/denyIPv4/...`),
- country policies,
- blocklists,
- cluster policy endpoint and strictness.

### 3.2 Cluster policy plane (snapshot)

Current `clusterPolicy` payload (v2) should remain the baseline cluster contract:

- `allowIPv4`, `allowIPv6`
- `denyIPv4`, `denyIPv6`
- `ignoreIPv4`, `ignoreIPv6`
- `schemaVersion`, `revision`, `ttlSeconds`

Recommended operational contract:

- control-plane emits immutable snapshots per revision,
- clients cache + validate,
- `ttlSeconds` enforces staleness behavior,
- strict nodes (`failOpen = false`) fail closed when snapshot is expired/unavailable.

### 3.3 Runtime dynamic plane (temporary bans)

For CSF-like behavior, use a dedicated runtime path:

- detector service emits offender events,
- local node writes temporary entries into dedicated nft sets with timeout,
- cluster sync shares temporary entries with TTL intact,
- expiry auto-removes offenders without manual cleanup.

POC recommendation:

- dynamic sets: `dynamic_ban_ipv4`, `dynamic_ban_ipv6` with timeout flags,
- source signals: rate-limit/log events,
- dynamic entries do not mutate declarative Nix state.

## 4) Local files + remote policy reconciliation

To match CSF operator workflow, support hybrid sources:

- local operator override files (`allow.local`, `deny.local`, `ignore.local`),
- remote cluster snapshot (`clusterPolicy.url`),
- runtime dynamic list cache.

Recommended precedence:

1. `ignore` (highest)
2. static/local `allow`
3. static/local `deny`
4. country/blocklist/cluster deny overlays
5. dynamic temporary bans

Notes:

- current implementation already applies strong `ignore` semantics against deny overlays,
- dynamic ban precedence should still allow explicit `ignore` to unblock emergency false positives.

## 5) Token generation and distribution

Token lifecycle baseline is implemented in `T-020`:

- `clusterPolicy.authTokenFiles` and `dynamicOffenders.authTokenFiles` support ordered fallback.
- Legacy `authTokenFile` is still supported for single-token deployments.
- Runtime enforces secret-file checks:
  - file exists and is readable,
  - no group/other permission bits,
  - token value is non-empty and whitespace-free.
- Observability includes auth candidate counts and selected token slot metrics.

Recommended process:

1. Generate tokens out-of-band (`openssl rand -hex 32` or equivalent).
2. Store tokens in secret manager (`sops-nix`, `agenix`, Vault, or cloud secret store).
3. Materialize runtime files per node (for example in `/run/secrets`).
4. Configure ordered overlap for rotation:
   - `authTokenFiles = [ "/run/secrets/current" "/run/secrets/next" ];`
   - control-plane accepts both for a rotation window.
5. Roll control-plane and nodes, then remove old token from both endpoint and host config.

## 6) Docker and other firewall daemons

### 6.1 Main risk

Docker mutates firewall state dynamically (bridge/NAT rules). Hard replacement of all chains can break container networking.

### 6.2 Coexistence strategy status

- Baseline implemented in `T-021`:
  - explicit host profiles:
  - `exclusive-firewall` (nix-csf full ownership),
  - `docker-coexist` (nix-csf filter policy + Docker-managed NAT).
  - integration test coverage with Docker-enabled nodes.
- Recommended next hardening:
  - add targeted interface/network exemption patterns for non-Docker daemons when required.

## 7) Monitoring and Grafana model

Current metrics already expose:

- cluster policy health (`schema`, `ttl`, `cache_age`, `expired`),
- dynamic offender snapshot health,
- token candidate/selected-slot state for remote auth.

POC monitoring pack should include:

- Prometheus scrape for host textfile metrics,
- Grafana dashboard panels:
  - `last_run_success` by host/mode,
  - set cardinality (allow/deny/country/feed/dynamic),
  - cluster snapshot age vs TTL,
  - strict-mode failures over time,
- alert rules:
  - cluster snapshot expired on strict nodes,
  - repeated apply failures,
  - sudden dynamic-ban spikes.

Optional extension path:

- Netdata mapping of the same `nix_csf_*` metric surface (`T-023`) to avoid dual semantics.

## 8) Nix-style examples

### 8.1 Global open ports

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 ];
};
```

### 8.2 Ports open only for selected countries (current model)

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 ];
  country = {
    enable = true;
    mode = "allow";
    countries = [ "US" "CA" ];
    failOpen = false;
  };
};
```

### 8.3 Deny selected countries only on selected ports

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 8443 ];
  country = {
    enable = true;
    countries = [ "RU" "CN" ];
    portDeny = {
      enable = true;
      countries = [ "RU" "CN" ];
      tcpPorts = [ 443 ];
    };
  };
};
```

### 8.4 ICMP status

Current module supports `allowICMP = true|false` (global). Per-type/per-rate ICMP policy is planned in `T-017`.

## 9) POC delivery slice

Current cluster-first priority:

1. `T-025` operator mutation workflow PoC (`nix-csfctl`)
2. `T-022` hybrid local-files + remote reconciliation contract
3. `T-023` Netdata monitoring integration (optional story)

Completed:

- `T-026` dynamic escalation policy PoC (`N` temp bans => permanent deny)
