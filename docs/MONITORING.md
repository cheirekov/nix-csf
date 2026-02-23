# Monitoring Pack

This document defines the `T-019` monitoring pack for `nix-csf`.

## Scope

The pack includes:

- Prometheus alert rules: `docs/monitoring/prometheus-alert-rules.yml`
- Grafana dashboard: `docs/monitoring/grafana-dashboard.json`
- Runbook and triage workflow for firewall operations

## Prerequisites

- `services.nixCsf.observability.metrics.enable = true`
- Metrics file path readable by your node exporter textfile collector
- Prometheus scraping that exporter endpoint

Minimal `nix-csf` metrics setup:

```nix
services.nixCsf = {
  enable = true;
  observability.metrics = {
    enable = true;
    outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
  };
};
```

## Prometheus Rule Wiring (NixOS)

```nix
services.prometheus = {
  enable = true;
  ruleFiles = [
    ./docs/monitoring/prometheus-alert-rules.yml
  ];
};
```

If Prometheus runs outside the firewall host, scrape the node exporter on the host and ensure labels (`instance`, `job`) are stable.

## Grafana Dashboard Wiring

Dashboard JSON source:

- `docs/monitoring/grafana-dashboard.json`

Import options:

1. Grafana UI import.
2. Grafana provisioning from file in your existing deployment workflow.

Recommended datasource: Prometheus.

## Alert Semantics

### `NixCsfRefreshStale`

- Condition: refresh metric timestamp older than 2 hours.
- Meaning: refresh pipeline likely stopped or cannot complete.

### `NixCsfClusterPolicyCacheExpired`

- Condition: cluster policy enabled and cache marked expired.
- Meaning: strict nodes may fail closed.

### `NixCsfDynamicSnapshotExpired`

- Condition: dynamic offender feed enabled and cache marked expired.
- Meaning: strict nodes may fail closed.

### `NixCsfDynamicBanCardinalitySpike`

- Condition: dynamic ban entry count > 20k for at least 10 minutes.
- Meaning: potential abuse spike or detector malfunction.

### `NixCsfAuthFallbackActive`

- Condition: selected auth token slot > 1.
- Meaning: rotation overlap is active or primary token auth is failing.

### `NixCsfRefreshDurationHigh`

- Condition: refresh runtime > 45s for at least 15 minutes.
- Meaning: remote feed latency or host pressure.

## Runbook

For full service/firewall/cache diagnostics beyond monitoring alerts, use:

- `docs/TROUBLESHOOTING.md`
- `nix-csf-triage` command bundle

When alerts fire, run:

```bash
sudo systemctl status nix-csf-apply.service --no-pager
sudo systemctl status nix-csf-refresh.service --no-pager
sudo systemctl status nix-csf-refresh.timer --no-pager
sudo journalctl -u nix-csf-refresh.service -n 120 --no-pager
sudo cat /var/lib/node_exporter/textfile_collector/nix-csf.prom
```

For strict mode incidents (`failOpen = false`):

1. Confirm cache files exist in `/var/lib/nix-csf/cache`.
2. Validate remote endpoint reachability and auth token file permissions.
3. Trigger a manual refresh after remediation:

```bash
sudo systemctl start nix-csf-refresh.service
```

## Netdata Integration (`T-023`)

Netdata integration is now available as an optional module feature.

Design contract:

- keep existing Prometheus/textfile metrics as source of truth,
- map `nix_csf_*` metrics into Netdata charts/alarms via generated `charts.d` + `health.d` files,
- keep alarm semantics aligned with this Prometheus pack to avoid drift.

See `docs/NETDATA.md` for full configuration and operator checks.
