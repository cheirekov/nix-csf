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

## Example

```nix
{
  services.netdata.enable = true;

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
```

Check recent collector/alarm logs:

```bash
sudo journalctl -u netdata -n 120 --no-pager
```
