# Netdata Integration

This document defines `T-023`: Netdata integration for `nix-csf`.

## Goal

Map existing `nix_csf_*` metrics to Netdata charts/alarms without adding a second firewall writer.

## What the module installs

When `services.nixCsf.netdata.enable = true`:

- Netdata `charts.d` collector plugin `nix_csf.chart.sh`
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
