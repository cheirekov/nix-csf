# Script Runbook Index

This page is the single index for repository scripts, when to use them, and
how they fit the agent/operator workflow.

## Script Matrix

| Script | Installed command | Use case | Execution lane |
|---|---|---|---|
| `scripts/nix-csf-apply.sh` | `nix-csf-apply` | Core renderer/applier (`apply`/`refresh`) for nftables policy | Internal (`systemd`) |
| `scripts/nix-csf-control-plane.py` | `nix-csf-control-plane` | Mutable control-plane API for policy lists and dynamic offenders | Internal (`systemd`) or manual debug |
| `scripts/nix-csfctl.sh` | `nix-csfctl` | Operator CLI for control-plane health, policy add/remove, bans, promotions | Operator |
| `scripts/nix-csf-import-csf.sh` | `nix-csf-import-csf` | Import legacy `csf.allow/csf.deny/csf.ignore` into `localFiles` inputs | Operator |
| `scripts/nix-csf-lfd-detector.sh` | `nix-csf-lfd-detector` | LFD-like detector from journal failures to temp bans | Internal (`systemd`) or operator debug |
| `scripts/nix-csf-fail2ban-action.sh` | `nix-csf-fail2ban-action` | Fail2ban action bridge into nix-csf control-plane | fail2ban/internal |
| `scripts/nix-csf-triage.sh` | `nix-csf-triage` | Troubleshooting bundle (services, journals, nft snapshot, metrics) | Operator |
| `scripts/nix-csf-netdata.chart.sh` | generated chart script in `/etc/netdata/conf.d/charts.d/` | Netdata charts.d collector for `nix_csf.*` metrics | Internal (Netdata) |
| `scripts/validate-agent.sh` | n/a | Agent-safe validation (`bash -n`, `py_compile`, `flake check --no-build`) | Agent |
| `scripts/validate-fast.sh` | n/a | Compatibility alias to `validate-agent.sh` | Agent |
| `scripts/validate.sh` | n/a | Full validation (`nix build` checks + VM tests) | Operator (manual) |
| `scripts/validate-capture.sh` | n/a | Full validation with captured logs and summary extraction | Operator (manual) |
| `scripts/validate-burnin.sh` | n/a | Repeated full validation runs with consolidated burn-in summary | Operator (manual) |
| `scripts/release.sh` | n/a | SemVer release commit/tag workflow | Maintainer/operator |

## Per-Script Usage

### `nix-csf-apply`

Used by `nix-csf-apply.service` and `nix-csf-refresh.service`.

```bash
sudo nix-csf-apply --config /etc/nix-csf/config.json --mode apply
sudo nix-csf-apply --config /etc/nix-csf/config.json --mode refresh
```

### `nix-csf-control-plane`

Usually managed by `nix-csf-control-plane.service`. Manual debug run:

```bash
sudo nix-csf-control-plane \
  --bind-address 127.0.0.1 \
  --port 18081 \
  --data-dir /var/lib/nix-csf-control-plane \
  --environment lab
```

### `nix-csfctl`

Health, policy mutation, and offender operations:

```bash
nix-csfctl --output pretty health
nix-csfctl --output pretty policy compile --input ./policy-source.json --cluster-output ./cluster-policy.json --dynamic-output ./dynamic-offenders.json
nix-csfctl policy add deny 203.0.119.9/32
nix-csfctl policy add deny 203.0.119.140/32 --scope local --node-id edge-us-01 --source lfd
nix-csfctl policy remove deny 203.0.119.9/32
nix-csfctl ban-temp 203.0.119.10/32 --ttl 900 --reason ssh_flood
nix-csfctl ban-temp 203.0.119.142/32 --ttl 600 --reason lfd:ssh_auth --scope local --node-id edge-us-01 --source lfd
nix-csfctl unban 203.0.119.142/32 --scope local --node-id edge-us-01
nix-csfctl promotions --limit 20
```

`policy compile` input schema:
- `clusterPolicy.allow|deny|ignore`: arrays of CIDR strings (or top-level aliases `allow|deny|ignore`)
- `dynamicOffenders.ban`: array of CIDR strings or objects with `cidr` and optional `ttlSeconds|expiresAt|reason`

### `nix-csf-import-csf`

Legacy CSF migration:

```bash
nix-csf-import-csf \
  --allow-file /etc/csf/csf.allow \
  --deny-file /etc/csf/csf.deny \
  --ignore-file /etc/csf/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

Strict migration mode:

```bash
nix-csf-import-csf \
  --allow-file /etc/csf/csf.allow \
  --deny-file /etc/csf/csf.deny \
  --ignore-file /etc/csf/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf \
  --strict
```

### `nix-csf-lfd-detector`

Manual detector run for debugging:

```bash
cat >/tmp/nix-csf-detectors.json <<'JSON'
[
  {
    "name": "ssh-auth",
    "enable": true,
    "journalIdentifier": "sshd",
    "lineContains": "Failed password",
    "windowSeconds": 300,
    "threshold": 5,
    "banTTLSeconds": 900,
    "reason": "lfd:sshd_failed_login"
  }
]
JSON

sudo nix-csf-lfd-detector \
  --detectors-file /tmp/nix-csf-detectors.json \
  --endpoint http://127.0.0.1:18081 \
  --refresh-after-ban \
  --metrics-file /var/lib/nix-csf/lfd-detector.prom
```

### `nix-csf-fail2ban-action`

Fail2ban action command examples:

```bash
sudo nix-csf-fail2ban-action ban --ip 203.0.113.77 --jail sshd
sudo nix-csf-fail2ban-action unban --ip 203.0.113.77 --jail sshd
```

### `nix-csf-triage`

Collect troubleshooting snapshot:

```bash
sudo nix-csf-triage --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
```

### Validation scripts

Agent lane:

```bash
./scripts/validate-agent.sh
./scripts/validate-fast.sh
```

Operator lane:

```bash
./scripts/validate.sh
./scripts/validate-capture.sh
./scripts/validate-burnin.sh --runs 3
```

### `release.sh`

Release flow:

```bash
./scripts/release.sh --version 1.0.2 --dry-run
./scripts/release.sh --version 1.0.2
./scripts/release.sh --version 1.0.2 --push
```

## Operator Workflows

### 1. Daily development loop (team split)

```bash
# Agent lane
./scripts/validate-agent.sh

# Operator lane
./scripts/validate-capture.sh
```

Share either:
- `[nix-csf] validation succeeded`
- `.artifacts/validate/*-summary.log`

### 2. Legacy CSF migration

```bash
nix-csf-import-csf --allow-file /etc/csf/csf.allow --deny-file /etc/csf/csf.deny --ignore-file /etc/csf/csf.ignore --output-dir /var/lib/nix-csf/imported --prefix legacy-csf
sudo systemctl start nix-csf-refresh.service
sudo systemctl show -P Result nix-csf-refresh.service
```

Audit outputs to review after apply/refresh:
- `/var/lib/nix-csf/local-list-audit-summary.tsv`
- `/var/lib/nix-csf/local-list-conflicts.tsv`

### 3. Mutable control-plane operations

```bash
nix-csfctl --output pretty health
nix-csfctl --output pretty policy compile --input ./policy-source.json --cluster-output ./cluster-policy.json --dynamic-output ./dynamic-offenders.json
nix-csfctl policy add deny 203.0.119.9/32
nix-csfctl policy add deny 203.0.119.140/32 --scope local --node-id edge-us-01 --source lfd
nix-csfctl ban-temp 203.0.119.10/32 --ttl 600 --reason syn_flood
nix-csfctl ban-temp 203.0.119.142/32 --ttl 600 --reason lfd:ssh_auth --scope local --node-id edge-us-01 --source lfd
sudo systemctl start nix-csf-refresh.service
```

### 4. Incident triage workflow

```bash
sudo nix-csf-triage --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
sudo journalctl -u nix-csf-apply.service -n 120 --no-pager
sudo nft list table inet nix_csf
```

### 5. Release workflow

```bash
./scripts/release.sh --version <semver> --dry-run
./scripts/release.sh --version <semver>
```

### 6. Cluster auth token lifecycle

```bash
sudo install -d -m 700 /run/secrets/nix-csf
sudo sh -c 'umask 077; openssl rand -hex 32 > /run/secrets/nix-csf/control-plane-token'
sudo chmod 600 /run/secrets/nix-csf/control-plane-token

nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf/control-plane-token health
sudo systemctl start nix-csf-refresh.service
sudo grep -E 'nix_csf_auth_token_(candidates|selected_slot)' /var/lib/nix-csf/metrics.prom
```

Full runbook:
- `docs/CLUSTER_AUTH_TOKENS.md`

### 7. Security validation and pen-test workflow

Baseline command:

```bash
./scripts/validate-capture.sh
```

Full hardening and abuse-replay procedure:
- `docs/SECURITY_VALIDATION_RUNBOOK.md`
