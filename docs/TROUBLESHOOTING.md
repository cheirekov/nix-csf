# Troubleshooting Runbook (`T-013`)

This runbook provides a standard command set for fast triage of `services.nixCsf`.

## Quick Capture (Recommended)

Collect one snapshot and share it for analysis:

```bash
sudo nix-csf-triage --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
```

If you run from repository scripts instead of installed tools:

```bash
sudo ./scripts/nix-csf-triage.sh --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
```

When validating from repo artifacts:

```bash
sudo ./scripts/nix-csf-triage.sh \
  --artifacts-dir /home/<user>/work/nix-csf/.artifacts/validate \
  --output /tmp/nix-csf-triage-with-validate.log
```

## Core Command Set

```bash
sudo systemctl status nix-csf-apply.service --no-pager
sudo systemctl status nix-csf-refresh.service --no-pager
sudo systemctl status nix-csf-refresh.timer --no-pager
sudo journalctl -u nix-csf-apply.service -n 120 --no-pager
sudo journalctl -u nix-csf-refresh.service -n 120 --no-pager
sudo nft list table inet nix_csf
sudo ls -lah /var/lib/nix-csf /var/lib/nix-csf/cache
sudo cat /var/lib/nix-csf/metrics.prom
```

## Symptom-to-Action

## 1) Boot apply failed (`nix-csf-apply.service`)

Check:

```bash
sudo systemctl show -P Result nix-csf-apply.service
sudo journalctl -u nix-csf-apply.service -n 120 --no-pager
```

Frequent signatures and fixes:

- `country mode is allow, but no country data is available`
  - seed cache or set reachable country source,
  - or set `services.nixCsf.country.failOpen = true`.
- `country.portDeny is enabled, but no country data is available`
  - add reachable country source or `country.portDeny.extraIPv4/extraIPv6`,
  - or set `country.failOpen = true`.
- `country.portAllow is enabled, but no country data is available`
  - add reachable country source or `country.portAllow.extraIPv4/extraIPv6`,
  - or set `country.failOpen = true`.
- `blocklists.failOpen=false and no cached data is available`
  - ensure feed URL is reachable and run one successful refresh.

## 2) Refresh failures (`nix-csf-refresh.service`)

Check:

```bash
sudo systemctl start nix-csf-refresh.service
sudo systemctl show -P Result nix-csf-refresh.service
sudo journalctl -u nix-csf-refresh.service -n 160 --no-pager
```

Frequent signatures and fixes:

- `cached cluster policy expired` / `cached dynamic offenders snapshot expired`
  - restore endpoint reachability,
  - refresh cache, or temporarily use fail-open.
- `auth token slot 1 failed; trying next token`
  - rotation fallback is active,
  - verify primary token is still valid and permissions are correct.

## 3) `nix-csfctl` cannot reach control-plane

Check:

```bash
sudo systemctl status nix-csf-control-plane.service --no-pager
nix-csfctl health
curl -sf http://127.0.0.1:18081/healthz
```

If using auth:

- verify `controlPlane.authTokenFile` path and file permissions,
- confirm matching `Authorization: Bearer` token in caller.

## 4) Docker or dynamic firewall daemon coexistence issues

Check:

```bash
sudo nft list table inet nix_csf | sed -n '/chain forward {/,/}/p'
sudo docker info
sudo ip link show docker0
```

Required profile contract:

- `services.nixCsf.coexistence.profile = "docker-coexist"`
- `services.nixCsf.forwardPolicy = "accept"`

## 5) Expected IP not blocked/allowed

Check membership directly:

```bash
sudo nft get element inet nix_csf deny_ipv4 '{ 203.0.113.7 }'
sudo nft get element inet nix_csf allow_ipv4 '{ 203.0.113.7 }'
sudo nft get element inet nix_csf dynamic_ban_ipv4 '{ 203.0.113.7 }'
```

Inspect generated rules:

```bash
sudo grep -nE 'country_port_allow|country_port_deny|dynamic_ban|feed_ipv4' /var/lib/nix-csf/generated-ruleset.nft
```

## Validation lane triage

For CI/local VM failures:

```bash
./scripts/validate-capture.sh
```

Then share only:

- latest `.artifacts/validate/*-summary.log`,
- and full `nix log /nix/store/<...>-vm-test-run-nix-csf-(smoke|integration).drv` if requested.
