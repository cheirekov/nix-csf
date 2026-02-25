# CSF List Import Bridge (`T-028`)

This guide shows how to migrate legacy CSF list files into `nix-csf` local overlays.

Supported source files:

- `csf.allow`
- `csf.deny`
- `csf.ignore`

## What is imported

Imported directly:

- IPv4/IPv6 addresses and CIDRs
- ipset-style lines:
  - `add <set> <cidr>`
  - `ipset add <set> <cidr>`
- safe CSF advanced allow subset:
  - `tcp|in|d=<port_or_range>|s=<ip_or_cidr>`
  - `udp|in|d=<port_or_range>|s=<ip_or_cidr>`

Reported as unsupported:

- CSF advanced rules outside the safe subset above (for example outbound direction or ambiguous fields)
- `Include ...` directives
- unknown/unparseable tokens

Unsupported entries are written to a report with line numbers for manual conversion.

Deduplication behavior:

- import outputs (`*.local`) are de-duplicated (`sort -u`),
- apply pipeline de-duplicates merged overlays again before nft rendering.
- apply pipeline also emits deterministic local-list audit artifacts:
  - `/var/lib/nix-csf/local-list-audit-summary.tsv` (duplicate/overlap counts),
  - `/var/lib/nix-csf/local-list-conflicts.tsv` (exact CIDR overlaps across allow/deny/ignore).

Conflict precedence reminder:

- exact overlaps across semantic lists are resolved by runtime precedence:
  - `deny` overrides `allow`,
  - `ignore` removes deny-style enforcement and is promoted into effective allow.

## Command

```bash
nix-csf-import-csf \
  --allow-file /path/to/csf.allow \
  --deny-file /path/to/csf.deny \
  --ignore-file /path/to/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

Outputs:

- `/var/lib/nix-csf/imported/legacy-csf-allow.local`
- `/var/lib/nix-csf/imported/legacy-csf-deny.local`
- `/var/lib/nix-csf/imported/legacy-csf-ignore.local`
- `/var/lib/nix-csf/imported/legacy-csf-unsupported.log`
- `/var/lib/nix-csf/imported/legacy-csf-summary.log`
- `/var/lib/nix-csf/imported/legacy-csf-nixos-localFiles-snippet.nix`

## Strict mode

Use strict mode to fail if any unsupported lines are found:

```bash
nix-csf-import-csf \
  --allow-file /path/to/csf.allow \
  --deny-file /path/to/csf.deny \
  --ignore-file /path/to/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf \
  --strict
```

Exit code is `2` when unsupported entries exist.

## Wire into NixOS config

Use generated snippet or set manually:

```nix
services.nixCsf.localFiles = {
  enable = true;
  failOnMissing = true;
  allow = [ "/var/lib/nix-csf/imported/legacy-csf-allow.local" ];
  deny = [ "/var/lib/nix-csf/imported/legacy-csf-deny.local" ];
  ignore = [ "/var/lib/nix-csf/imported/legacy-csf-ignore.local" ];
};
```

Then apply:

```bash
sudo systemctl start nix-csf-refresh.service
sudo systemctl show -P Result nix-csf-refresh.service
```
