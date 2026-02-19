# Architecture

## Design goals

- Security-first defaults (`drop` inbound/forward by default).
- Declarative module API for NixOS users.
- Runtime feed refresh without rebuilding the system.
- Compatibility with both flake and non-flake module imports.

## Components

- `modules/nixos/nix-csf.nix`
  - NixOS module options and service wiring.
- `scripts/nix-csf-apply.sh`
  - Runtime rule compiler and loader for nftables.
- `systemd` units
  - `nix-csf-apply.service`: early boot apply.
  - `nix-csf-refresh.service`: network-online refresh.
  - `nix-csf-refresh.timer`: periodic refresh schedule.
- Runtime state
  - `/var/lib/nix-csf/cache`: cached remote feeds.
  - `/var/lib/nix-csf/generated-ruleset.nft`: last generated ruleset.

## Data flow

1. Nix evaluation generates a JSON config from module options.
2. Boot-time apply service renders nftables rules from:
   - static config values,
   - cached feed data.
3. Refresh service (manual/timer) downloads latest feed files.
4. Rules are regenerated and atomically re-applied.

## Security boundaries

- `networking.firewall.enable` is asserted off to avoid mixed ownership.
- nftables policy is explicit and auditable in generated output.
- Remote feeds are optional and can run `failOpen` to reduce outage risk.
