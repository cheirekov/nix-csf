# Netdata Integration

This document defines `T-023` and follow-up hardening (`T-031`, `T-032`, `T-033`) for Netdata integration in `nix-csf`.

## Goal

Map existing `nix_csf_*` metrics to Netdata charts/alarms without adding a second firewall writer.

## What the module installs

When `services.nixCsf.netdata.enable = true`:

- generated `charts.d` main config: `/etc/netdata/conf.d/charts.d.conf`
- generated collector script: `/etc/netdata/conf.d/charts.d/nix_csf.chart.sh`
- generated collector config: `/etc/netdata/conf.d/charts.d/nix_csf.conf`
- generated alarm file (optional): `/etc/netdata/conf.d/health.d/nix_csf.conf`

Collector source of truth remains the existing textfile metrics from `services.nixCsf.observability.metrics.outputFile`.

## Required options

`nix-csf` enforces these guardrails when Netdata integration is enabled:

- `services.netdata.enable = true`
- `services.nixCsf.observability.metrics.enable = true`
- metrics file path is absolute

## Dashboard package note

On some Nixpkgs revisions, `pkgs.netdata` can run agent/API without bundled dashboard files.
If the UI returns `File does not exist, or is not accessible:`, switch to `pkgs.netdataCloud`.

## Example

```nix
{ pkgs, ... }:
{
  services.netdata = {
    enable = true;
    package = pkgs.netdataCloud;
    config.web = {
      "bind to" = "tcp:0.0.0.0:19999";
      # Restrict dashboard/badges to operator CIDRs.
      "allow dashboard from" = "localhost 127.0.0.1 ::1 172.16.0.0/16";
      "allow badges from" = "localhost 127.0.0.1 ::1 172.16.0.0/16";
    };
  };

  services.nixCsf = {
    enable = true;

    observability.metrics = {
      enable = true;
      outputFile = "/var/lib/nix-csf/metrics.prom";
    };

    netdata = {
      enable = true;
      updateEvery = 15;
      installHealthAlarms = true;
      alertRecipient = "sysadmin";
      # Optional: reduce noisy default charts.d module checks (libreswan/opensips/etc.).
      # Keeps nix_csf charts enabled.
      noiseProfile = "chartsd-minimal"; # off | chartsd-minimal
      # metricsFile = "/custom/path/nix-csf.prom"; # optional override
    };
  };
}
```

## Charts

The collector publishes these chart IDs:

- `nix_csf.run_status`
- `nix_csf.cache_expiry`
- `nix_csf.cardinality`
- `nix_csf.auth_slot`

## Alarms

Default generated alarms:

- `nix_csf_refresh_pipeline_failed`
- `nix_csf_cluster_policy_cache_expired`
- `nix_csf_dynamic_snapshot_expired`
- `nix_csf_cluster_auth_fallback`
- `nix_csf_dynamic_auth_fallback`

Semantics are aligned with `docs/monitoring/prometheus-alert-rules.yml`.

## Operator checks

```bash
sudo systemctl status netdata --no-pager
sudo test -f /etc/netdata/conf.d/charts.d.conf
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.chart.sh
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.conf
sudo test -f /etc/netdata/conf.d/health.d/nix_csf.conf
sudo netdatacli ping
curl -sf http://127.0.0.1:19999/v3/ >/dev/null
# Verify netdata user can read nix-csf metrics file.
sudo -u netdata test -r /var/lib/nix-csf/metrics.prom
```

Check recent collector/alarm logs:

```bash
sudo journalctl -u netdata -n 120 --no-pager
```

## Optional noise profile

If Netdata logs are noisy with non-critical `charts.d` module checks (for example
`libreswan` or `opensips` command-not-found checks), enable:

```nix
services.nixCsf.netdata.noiseProfile = "chartsd-minimal";
```

This sets `enable_all_charts="no"` in generated `/etc/netdata/conf.d/charts.d.conf`
and keeps `nix_csf=yes`, so only explicitly enabled `charts.d` collectors run.

## Known failure mode (`systemd-cat-native: command not found`)

If Netdata logs show:

- `charts.d.plugin: ... systemd-cat-native: command not found`

then `charts.d` collectors (including `nix_csf.chart.sh`) are disabled.

Mitigation (if you are not yet on `T-032`):

```nix
{ config, ... }:
{
  systemd.services.netdata.path = [ config.services.netdata.package ];
}
```

If logs show:

- `charts.d.plugin: ... No charts to collect data from`

then `charts.d.plugin` did not discover enabled modules. Ensure these files exist:

- `/etc/netdata/conf.d/charts.d.conf`
- `/etc/netdata/conf.d/charts.d/nix_csf.chart.sh`
- `/etc/netdata/conf.d/charts.d/nix_csf.conf`
