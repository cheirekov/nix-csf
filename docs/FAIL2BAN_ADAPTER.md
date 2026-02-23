# fail2ban Adapter (Single-Writer Firewall Model)

This document describes `services.nixCsf.fail2banAdapter`, which integrates fail2ban as a detector while keeping `nix-csf` as the only firewall writer.

## Goal

- Keep fail2ban detection logic (jails/filters).
- Route ban and unban actions through `nix-csfctl` to control-plane APIs.
- Avoid independent fail2ban nftables chains that can conflict with Docker or other dynamic daemons.

## Model

1. fail2ban detects an offender in a jail.
2. fail2ban action runs `nix-csf-fail2ban-action`.
3. Adapter calls control-plane API (`ban-temp`/`unban`) via `nix-csfctl`.
4. `nix-csf-refresh.service` is triggered (optional, enabled by default).
5. `nix-csf` applies updated dynamic sets.

## Nix Configuration Example

```nix
services.nixCsf = {
  enable = true;

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "prod";
    requireAuth = false;
  };

  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/prod/dynamic-offenders.json";
    requireHTTPS = false;
    failOpen = true;
  };

  fail2banAdapter = {
    enable = true;
    actionName = "nix-csf";
    banTTLSeconds = 900;
    reasonPrefix = "fail2ban";
    refreshAfterBan = true;
    refreshAfterUnban = true;

    # Optional when not using local controlPlane defaults:
    # endpoint = "https://policy.example.org";
    # authTokenFile = "/run/secrets/nix-csf-control-plane-token";
  };
};
```

With `installActionFile = true` (default), this generates:

- `/etc/fail2ban/action.d/<actionName>.local`

Default path:

- `/etc/fail2ban/action.d/nix-csf.local`

## fail2ban Jail Snippet

Use the generated action name in your fail2ban jail config:

```ini
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
backend = systemd
banaction = nix-csf
```

For multiple jails you can reuse the same `banaction = nix-csf` so all jail events flow through the same control-plane path.

## Manual Adapter Checks

```bash
sudo systemctl start nix-csf-refresh.service
sudo test -s /etc/fail2ban/action.d/nix-csf.local

sudo nix-csf-fail2ban-action ban --ip 203.0.113.77 --jail sshd
sudo nix-csf-fail2ban-action unban --ip 203.0.113.77 --jail sshd

sudo journalctl -u nix-csf-refresh.service -n 80 --no-pager
sudo grep -F 'dynamic_ban' /var/lib/nix-csf/generated-ruleset.nft
```

## Guardrails

When `services.nixCsf.fail2banAdapter.enable = true`:

- `services.nixCsf.dynamicOffenders.enable` is required.
- either control-plane must be enabled locally or explicit `fail2banAdapter.endpoint` must be set.
- adapter auth token path must be absolute when configured.

## Notes

- `fail2ban` remains detector-only in this model.
- `nix-csf` remains single firewall writer and owns nftables rendering.
- This reduces conflict risk with `coexistence.profile = "docker-coexist"` and other dynamic daemons.
