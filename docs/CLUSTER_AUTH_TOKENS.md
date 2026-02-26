# Cluster Auth Token Runbook

Last updated: 2026-02-26  
Owners: Security Architect + Nix Module Engineer + QA/Release Engineer

Purpose: provide one operational runbook for token generation, secure storage, and
rotation for `services.nixCsf.controlPlane`, `clusterPolicy`, and `dynamicOffenders`.

## 1) Token model

- `services.nixCsf.controlPlane.authTokenFile`
  - single active bearer token accepted by control-plane API.
- `services.nixCsf.clusterPolicy.authTokenFiles`
  - ordered candidate tokens for snapshot pull auth (rotation overlap on clients).
- `services.nixCsf.dynamicOffenders.authTokenFiles`
  - ordered candidate tokens for dynamic snapshot pull auth (rotation overlap on clients).

Runtime contract (enforced):

- token paths must be absolute,
- token files must exist and be readable,
- token value must be non-empty and whitespace-free,
- token files must not expose group/other bits.

## 2) Secure token generation

Use `openssl rand` and strict file modes:

```bash
sudo install -d -m 700 /run/secrets/nix-csf
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/control-plane-token'
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/cluster-token-current'
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/dynamic-token-current'
sudo chmod 600 /run/secrets/nix-csf/control-plane-token /run/secrets/nix-csf/cluster-token-current /run/secrets/nix-csf/dynamic-token-current
```

Validation:

```bash
sudo stat -c '%a %U:%G %n' /run/secrets/nix-csf/control-plane-token /run/secrets/nix-csf/cluster-token-current /run/secrets/nix-csf/dynamic-token-current
```

Expected mode is `600`.

## 3) Nix configuration pattern

Control-plane node:

```nix
services.nixCsf.controlPlane = {
  enable = true;
  requireAuth = true;
  authTokenFile = "/run/secrets/nix-csf/control-plane-token";
  environment = "prod";
};
```

Worker node:

```nix
services.nixCsf = {
  clusterPolicy = {
    enable = true;
    url = "https://fw-master.example.org/snapshots/prod/cluster-policy.json";
    authTokenFiles = [
      "/run/secrets/nix-csf/cluster-token-current"
      "/run/secrets/nix-csf/cluster-token-next"
    ];
  };

  dynamicOffenders = {
    enable = true;
    url = "https://fw-master.example.org/snapshots/prod/dynamic-offenders.json";
    authTokenFiles = [
      "/run/secrets/nix-csf/dynamic-token-current"
      "/run/secrets/nix-csf/dynamic-token-next"
    ];
  };
};
```

## 4) Rotation procedure (current implementation)

Current control-plane accepts one token at a time. Rotation is still safe by using
ordered overlap on workers.

1. Generate `next` tokens on workers:

```bash
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/cluster-token-next'
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/dynamic-token-next'
sudo chmod 600 /run/secrets/nix-csf/cluster-token-next /run/secrets/nix-csf/dynamic-token-next
```

2. Deploy workers with:
   - `authTokenFiles = [ current, next ]`.
3. Switch control-plane token to `next` and deploy control-plane host.
4. Trigger worker refresh:

```bash
sudo systemctl start nix-csf-refresh.service
sudo systemctl show -P Result nix-csf-refresh.service
```

5. Verify fallback and selection metrics:

```bash
sudo journalctl -u nix-csf-refresh.service -n 120 --no-pager | grep -F 'auth token slot 1 failed; trying next token' || true
sudo grep -E 'nix_csf_auth_token_(candidates|selected_slot)' /var/lib/nix-csf/metrics.prom
```

6. Finalize by promoting `next` to `current` and removing old token files from config/runtime.

## 5) Operator API usage

Use the same token file with `nix-csfctl`:

```bash
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf/control-plane-token health
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf/control-plane-token policy add deny 203.0.119.9/32 --scope cluster --source secops
```

## 6) Troubleshooting

- `401 unauthorized`:
  - verify token file content matches server token,
  - verify no whitespace/newline artifacts.
- `auth token unavailable or invalid`:
  - check control-plane `authTokenFile` exists and is readable by service.
- repeated fallback to slot `2+`:
  - primary token stale or wrong; complete rotation cleanup.

Related docs:

- `docs/DEPLOYMENT_BLUEPRINTS.md`
- `docs/CONTROL_PLANE_TLS_PROXY_POC.md`
- `docs/TROUBLESHOOTING.md`
