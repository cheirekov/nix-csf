# BIND Production Blueprint (Main + Backup)

This blueprint targets authoritative DNS on NixOS with `nix-csf` as the only firewall writer.

## 1) Baseline stance

- Keep DNS public on both transports:
  - `openUDPPorts = [ 53 ]`
  - `openTCPPorts = [ 53 ]`
- Keep SSH non-public when possible (management network, bastion, or scoped country policy).
- Use `coexistence.profile = "exclusive-firewall"` unless a dynamic daemon requires coexistence.

## 2) DDoS/flood posture (current capabilities)

Use `nix-csf` flood controls plus BIND-native controls together:

- `services.nixCsf.rateLimits.synFlood.*` for TCP SYN floods.
- `services.nixCsf.rateLimits.connFlood.*` for per-source new-connection/packet pressure.
- `services.nixCsf.rateLimits.dnsFlood.*` for DNS-port-specific UDP/TCP per-source meters with optional trusted-source bypass lists.
- `services.nixCsf.dynamicOffenders` + detector/fail2ban paths for repeated abusive sources.
- BIND response rate limiting (RRL) in named itself for DNS amplification/abuse handling.

Recommended `nix-csf` baseline:

```nix
services.nixCsf = {
  enable = true;
  threatProfile = "edge";
  openUDPPorts = [ 53 ];
  openTCPPorts = [ 53 ];

  rateLimits.synFlood = {
    enable = true;
    preset = "strict";
  };
  rateLimits.connFlood = {
    enable = true;
    preset = "balanced";
  };

  rateLimits.dnsFlood = {
    enable = true;
    udpRate = "400/second";
    udpBurst = 800;
    tcpRate = "120/second";
    tcpBurst = 240;
    udpPorts = [ 53 ];
    tcpPorts = [ 53 ];
    # Optional trusted resolver/peer bypass selectors:
    allowIPv4 = [ "192.0.2.0/24" ];
    allowIPv6 = [ "2001:db8:53::/48" ];
  };
};
```

## 3) Root NS and ignore lists

Do not put the global root-server IP ranges into `ignore` by default.

Reason:
- authoritative servers do not need blanket trust of root-server addresses,
- `ignore` entries remove deny-style controls and promote allow precedence,
- broad ignore reduces security signal and increases bypass surface.

Use `ignore` only for tightly-scoped operational exceptions, for example:
- your DNS secondary/hidden-primary transfer peers,
- trusted monitoring probes,
- emergency unblocks with explicit ownership.

## 4) Main/backup cluster with auth

Use authenticated snapshot pull from control-plane with token rotation overlap.
For dedicated reverse-proxy API ports (for example `8448`) and ACME/internal PKI
patterns, see `docs/CONTROL_PLANE_TLS_PROXY_POC.md`.

Baseline snapshot pull shape:

```nix
services.nixCsf = {
  clusterPolicy = {
    enable = true;
    url = "https://cp.example.net/snapshots/prod-dns/cluster-policy.json";
    requireHTTPS = true;
    failOpen = true;
    authTokenFiles = [
      "/run/secrets/nix-csf-cluster-token-current"
      "/run/secrets/nix-csf-cluster-token-next"
    ];
    nodeId = "dns-main-01"; # unique per node
  };

  dynamicOffenders = {
    enable = true;
    url = "https://cp.example.net/snapshots/prod-dns/dynamic-offenders.json";
    requireHTTPS = true;
    failOpen = true;
    authTokenFiles = [
      "/run/secrets/nix-csf-dynamic-token-current"
      "/run/secrets/nix-csf-dynamic-token-next"
    ];
    nodeId = "dns-main-01"; # unique per node
    defaultEntryTTLSeconds = 900;
  };
};
```

Repeat on backup with a different `nodeId` (for local-scope filtering and provenance).

## 5) CI/CD temporary SSH access (GitHub Actions)

Use short-lived policy mutation via authenticated control-plane API:

- add runner CIDR before deploy,
- run deploy,
- always remove CIDR in cleanup/finally.

Recommended pattern:

```bash
set -euo pipefail

RUNNER_IP="$(curl -fsS https://api.ipify.org)"
RUNNER_CIDR="${RUNNER_IP}/32"

nix-csfctl \
  --endpoint "https://cp.example.net" \
  --auth-token-file /run/secrets/nix-csf-control-plane-token \
  --output json \
  policy add allow "${RUNNER_CIDR}" \
  --scope local \
  --node-id dns-main-01 \
  --source ci

cleanup() {
  nix-csfctl \
    --endpoint "https://cp.example.net" \
    --auth-token-file /run/secrets/nix-csf-control-plane-token \
    --output json \
    policy remove allow "${RUNNER_CIDR}" \
    --scope local \
    --node-id dns-main-01 \
    --source ci || true
}
trap cleanup EXIT

# deploy command here
nixos-rebuild switch --flake .#dns-main-01 --target-host root@dns-main-01
```

### Alternative variants

1. Preferred: management overlay network (`tailscale0`/`wg0`) in `trustedInterfaces`, no CI IP mutations.
2. Bastion-only SSH path with static allowlists and short-lived SSH certs.
3. Direct CI IP mutation (above) only when overlay/bastion is unavailable.

## 6) Cluster/API security and monitoring

- Keep control-plane API private (management network or reverse proxy ACL).
- Require auth (`controlPlane.requireAuth = true`) outside lab.
- Rotate tokens with overlap (`authTokenFiles`).
- Keep `nodeId` unique per node.
- Monitor:
  - `nix_csf_auth_token_selected_slot{source=...}`
  - refresh failures and cache expiry metrics
  - detector/fail2ban ban rates
- For auth-abuse signal coverage, enable detector-pack templates:
  - `lfdDetector.detectorPack.controlPlaneAuth`
  - `lfdDetector.detectorPack.apiProxyAuth`

## 7) Pen-test baseline (pre-release)

Run at least:

1. UDP/TCP DNS pressure tests against port 53 (safe lab limits).
2. SSH auth-abuse simulation and verify detector/escalation behavior.
3. Control-plane auth failure replay (invalid token) and metric/log verification.
4. CI mutation path test (allow add/remove) with failure cleanup confirmation.

Formal procedure and evidence checklist:
- `docs/SECURITY_VALIDATION_RUNBOOK.md`
