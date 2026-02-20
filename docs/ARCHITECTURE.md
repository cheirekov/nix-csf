# Architecture

## Design goals

- Security-first defaults (`drop` inbound/forward by default).
- Declarative module API for NixOS users.
- Runtime feed refresh without rebuilding the system.
- Compatibility with both flake and non-flake module imports.
- Profile-driven onboarding (`threatProfile`) with explicit override precedence.
- Governed remote blocklist ingestion through a source catalog schema.
- Centralized cluster policy propagation for multi-host allow/deny overlays.
- Cluster policy schema v2 governance (`allow`/`deny`/`ignore` + revision/TTL).
- Clear separation between declarative policy state and runtime dynamic offender state.
- Coexistence strategy for hosts that run additional firewall mutators (for example Docker).
- Repeatable SemVer-based release lifecycle.

## Components

- `modules/nixos/nix-csf.nix`
  - NixOS module options and service wiring.
- `scripts/nix-csf-apply.sh`
  - Runtime rule compiler and loader for nftables.
- `VERSION`
  - Single source of truth for module/project SemVer.
- `scripts/release.sh`
  - Maintainer release automation (validate, version bump, tag flow).
- `systemd` units
  - `nix-csf-apply.service`: early boot apply.
  - `nix-csf-refresh.service`: network-online refresh.
  - `nix-csf-refresh.timer`: periodic refresh schedule.
- Runtime state
  - `/var/lib/nix-csf/cache`: cached remote feeds.
  - `/var/lib/nix-csf/generated-ruleset.nft`: last generated ruleset.
  - optional Prometheus textfile metrics output (default: `/var/lib/nix-csf/metrics.prom`).

## Data flow

1. Nix evaluation generates a JSON config from module options.
   Profile presets are resolved at eval-time through `mkDefault` so explicit per-host values still win.
2. Module version metadata (`services.nixCsf.moduleVersion`) is injected from `VERSION`.
3. Boot-time apply service renders nftables rules from:
   - static config values,
   - cached feed data.
4. Refresh service (manual/timer) downloads latest feed files and optional cluster policy overlay JSON.
5. Cluster policy cache metadata (schema/revision/TTL) is validated before merge.
6. Rules are regenerated and atomically re-applied.
7. Optional observability export writes:
   - structured event logs to journald,
   - snapshot metrics in Prometheus textfile format (including build/version metadata).

## Security boundaries

- `networking.firewall.enable` is asserted off to avoid mixed ownership.
- nftables policy is explicit and auditable in generated output.
- Remote feeds are optional and can run `failOpen` to reduce outage risk.
- In strict mode (`failOpen = false`), `apply` requires cache presence for remote sources and fails closed when cache is absent.
- Blocklist sources can be governed by catalog IDs (`blocklists.sources`) with schema-backed metadata.
- Cluster ignore overlays can explicitly subtract CIDRs from deny-style sources.

## Centralized dynamic POC

See `docs/DYNAMIC_CLUSTER_POC.md` for the team recommendation on:

- CSF-style dynamic temporary bans,
- hybrid local-files + remote cluster list workflows,
- token lifecycle handling for cluster auth,
- Grafana/Prometheus operational model,
- Docker and other dynamic-firewall coexistence strategy.
