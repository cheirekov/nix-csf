# Operator Use-Case Catalog

This catalog expands practical deployment examples for `services.nixCsf`.

All snippets assume:

- the module is already imported (flake or non-flake),
- `networking.firewall.enable = false` (required by module assertion),
- validation happens with `sudo systemctl start nix-csf-refresh.service` after deployment.

For centralized dynamic-ban and Docker coexistence design recommendations, see `docs/DYNAMIC_CLUSTER_POC.md`.

## Baseline operator checks

Run these checks for any profile:

```bash
sudo systemctl status nix-csf-apply.service --no-pager
sudo systemctl start nix-csf-refresh.service
sudo systemctl status nix-csf-refresh.service --no-pager
sudo nft list table inet nix_csf
sudo journalctl -u nix-csf-refresh.service -n 80 --no-pager
```

If you run strict mode (`blocklists.failOpen = false`, `clusterPolicy.failOpen = false`, or
`dynamicOffenders.failOpen = false`),
warm caches after deployment:

```bash
sudo systemctl start nix-csf-refresh.service
```

## Threat profile quick-starts (`T-012`)

Use `services.nixCsf.threatProfile` for fast baseline posture, then override only what is host-specific.

```nix
# Server baseline: balanced flood controls + logDrops + hourly refresh.
services.nixCsf.threatProfile = "server";

# Workstation baseline: closes inbound defaults (no open TCP/UDP ports).
services.nixCsf.threatProfile = "workstation";

# Edge baseline: opens 22/443 TCP + 53/51820 UDP with stricter SYN flood control.
services.nixCsf.threatProfile = "edge";
```

Explicit options still win over profile defaults:

```nix
services.nixCsf = {
  enable = true;
  threatProfile = "edge";
  openTCPPorts = [ 8443 ]; # overrides profile openTCPPorts
  logDrops = false;        # overrides profile logDrops=true
};
```

## 1) Public web server with conservative flood controls

Use this when the node serves HTTP/HTTPS directly.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  rateLimits.synFlood = { enable = true; preset = "strict"; };
  rateLimits.connFlood = { enable = true; preset = "balanced"; };
  logDrops = true;
};
```

## 2) SSH bastion with country allow-list and strict failure mode

Use this when only selected countries should reach SSH and you prefer fail-closed behavior if country data cannot be refreshed.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 ];
  country = {
    enable = true;
    mode = "allow";
    countries = [ "US" "CA" ];
    failOpen = false;
  };
};
```

## 3) Port-scoped geo restriction (`CC_DENY_PORTS` style)

Use this when countries should be blocked only for specific exposed ports.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 ];
  country = {
    enable = true;
    countries = [ "RU" "CN" ];
    portDeny = {
      enable = true;
      countries = [ "RU" "CN" ];
      tcpPorts = [ 443 ];
    };
  };
};
```

## 4) Port-scoped country allow (`CC_ALLOW_PORTS` style)

Use this when only selected countries should reach selected ports while other ports remain governed by your normal policy.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 ];
  country = {
    enable = true;
    countries = [ "US" "CA" ];
    portAllow = {
      enable = true;
      countries = [ "US" "CA" ];
      tcpPorts = [ 22 443 ];
      udpPorts = [ 53 ];
    };
  };
};
```

## 5) Governed blocklist ingestion (catalog-only)

Use this when feed governance and auditability matter more than convenience.

```nix
services.nixCsf = {
  enable = true;
  blocklists = {
    enable = true;
    enforceCatalog = true;
    requireHTTPS = true;
    sources = [ "spamhaus-drop-v4" "spamhaus-drop-v6" ];
    failOpen = false;
  };
};
```

## 6) Cluster-wide policy propagation with per-node identity

Use this to centralize allow/deny overlays across many hosts.

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
    failOpen = false;
    authTokenFiles = [
      "/run/secrets/nix-csf-cluster-token-current"
      "/run/secrets/nix-csf-cluster-token-next"
    ];
    nodeId = "edge-us-01";
  };
};
```

Auth token notes:

- use `authTokenFiles` for staged rotation overlap (first success wins),
- all token files must be readable only by owner (for example `0600` or `0400`),
- legacy `authTokenFile` remains supported for single-token deployments.

Expected JSON keys from the policy endpoint:

- `schemaVersion` (1 or 2)
- `revision` (string/number)
- `ttlSeconds` (non-negative integer)
- `allowIPv4`
- `allowIPv6`
- `denyIPv4`
- `denyIPv6`
- `ignoreIPv4`
- `ignoreIPv6`

If `ttlSeconds` is present and cache age exceeds TTL:

- strict mode (`clusterPolicy.failOpen = false`) fails closed,
- fail-open mode keeps service running but skips cluster merge.

## 7) Offline/lab environment with local files

Use this when internet egress is restricted and feeds are staged locally.

```nix
services.nixCsf = {
  enable = true;
  country = {
    enable = true;
    countries = [ "US" ];
    ipv4URLTemplate = "file:///etc/nix-csf/country/%s.zone";
    failOpen = false;
  };
  blocklists = {
    enable = true;
    requireHTTPS = false;
    urls = [ "file:///etc/nix-csf/feeds/local-v4.txt" ];
    failOpen = false;
  };
  clusterPolicy = {
    enable = true;
    url = "file:///etc/nix-csf/cluster/policy.json";
    requireHTTPS = false;
    failOpen = false;
  };
};
```

Hybrid local + remote reconciliation pattern:

```nix
services.nixCsf = {
  enable = true;
  localFiles = {
    enable = true;
    failOnMissing = true;
    allow = [ "/var/lib/nix-csf/lists/allow.local" ];
    deny = [ "/var/lib/nix-csf/lists/deny.local" ];
    ignore = [ "/var/lib/nix-csf/lists/ignore.local" ];
  };
  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
  };
};
```

Reconciliation contract:

- `localFiles.ignore` and cluster `ignore*` are merged first.
- merged ignore entries are added to allow and removed from deny-style overlays.
- this allows emergency local unblocks without replacing remote cluster policy.

## 8) Dynamic temporary offender propagation (TTL)

Use this when a centralized detector/control-plane publishes temporary bans that should expire automatically.

```nix
services.nixCsf = {
  enable = true;
  dynamicOffenders = {
    enable = true;
    url = "https://policy.example.org/nix-csf/dynamic-offenders.json";
    failOpen = false;
    authTokenFiles = [
      "/run/secrets/nix-csf-dynamic-token-current"
      "/run/secrets/nix-csf-dynamic-token-next"
    ];
    nodeId = "edge-us-01";
    defaultEntryTTLSeconds = 900;
    maxEntries = 20000;
  };
};
```

Expected dynamic snapshot keys:

- `schemaVersion` (1 or 2)
- `revision` (string/number)
- `ttlSeconds` (non-negative integer)
- `banIPv4` (array of CIDR strings or objects with `cidr` + `ttlSeconds`/`expiresAt`)
- `banIPv6` (same format as `banIPv4`)

Runtime notes:

- `ttlSeconds` controls snapshot cache staleness.
- strict mode (`dynamicOffenders.failOpen = false`) fails closed for expired cache.
- temporary dynamic bans are evaluated after explicit allow rules so emergency allow/ignore overrides still work.
- metrics expose auth candidate count and selected slot per source:
  - `nix_csf_auth_token_candidates{source="..."}`,
  - `nix_csf_auth_token_selected_slot{source="..."}`.

Operator mutation examples (control-plane write path):

```bash
nix-csfctl policy add deny 203.0.119.9/32
nix-csfctl ban-temp 203.0.119.10/32 --ttl 900 --reason syn_flood
nix-csfctl promotions --limit 20
sudo systemctl start nix-csf-refresh.service
```

## 9) Docker coexistence host profile

Use this when Docker (or another dynamic firewall daemon) manages forwarding/NAT and you still want nix-csf deny overlays.

```nix
services.nixCsf = {
  enable = true;
  forwardPolicy = "accept";
  coexistence.profile = "docker-coexist";

  # deny-style overlays still apply in forward path:
  denyIPv4 = [ "198.51.100.0/24" ];
  dynamicOffenders = {
    enable = true;
    url = "https://policy.example.org/nix-csf/dynamic-offenders.json";
    failOpen = true;
  };
};
```

Operational checks:

```bash
sudo systemctl status docker.service --no-pager
sudo grep -A25 '^  chain forward {' /var/lib/nix-csf/generated-ruleset.nft
sudo docker network create nixcsf-check
sudo docker network rm nixcsf-check
```

## 10) Prometheus + structured logs for operations

Use this when you need host-level firewall health and source counts in monitoring.

```nix
services.nixCsf = {
  enable = true;
  observability = {
    structuredLogging = true;
    metrics = {
      enable = true;
      outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
    };
  };
};
```

Example checks:

```bash
sudo cat /var/lib/node_exporter/textfile_collector/nix-csf.prom
sudo journalctl -u nix-csf-apply.service -n 50 --no-pager
```

Pack assets shipped in-repo:

- Prometheus alerts: `docs/monitoring/prometheus-alert-rules.yml`
- Grafana dashboard: `docs/monitoring/grafana-dashboard.json`
- Runbook: `docs/MONITORING.md`

## 11) Global opened ports baseline

Use this when you want globally exposed ports independent of geo filters.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 ];
};
```

## 12) Ports opened only to selected countries

Use `country.portAllow` to constrain selected exposed ports by country while leaving other exposed ports global.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  country = {
    enable = true;
    countries = [ "US" "CA" ];
    portAllow = {
      enable = true;
      countries = [ "US" "CA" ];
      tcpPorts = [ 22 443 ];
    };
  };
};
```

## 13) ICMP profiles (legacy/off/safe/diagnostic/open)

Use modern ICMP profile controls:

```nix
services.nixCsf = {
  enable = true;
  icmp = {
    profile = "safe"; # legacy | off | safe | diagnostic | open
    rateLimit = {
      enable = true;
      rate = "30/second";
      burst = 120;
    };
  };
};
```

Compatibility mode remains available:

```nix
services.nixCsf = {
  enable = true;
  icmp.profile = "legacy";
  allowICMP = false; # broad legacy toggle
};
```

## 14) Import legacy CSF lists (`csf.allow/csf.deny/csf.ignore`)

Use this when migrating from existing CSF deployments and you want to preserve plain CIDR/IP entries.

```bash
nix-csf-import-csf \
  --allow-file /etc/csf/csf.allow \
  --deny-file /etc/csf/csf.deny \
  --ignore-file /etc/csf/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

Then wire generated lists:

```nix
services.nixCsf.localFiles = {
  enable = true;
  failOnMissing = true;
  allow = [ "/var/lib/nix-csf/imported/legacy-csf-allow.local" ];
  deny = [ "/var/lib/nix-csf/imported/legacy-csf-deny.local" ];
  ignore = [ "/var/lib/nix-csf/imported/legacy-csf-ignore.local" ];
};
```

Note:

- advanced CSF rule lines (for example `tcp|in|...`) are reported in `*-unsupported.log`,
- use `--strict` to fail the import if unsupported entries exist.

## 15) LFD-like SSH detector (`lfdDetector.*`)

Use this when you want CSF/LFD-style SSH failure detection while keeping `nix-csf` as the single firewall writer.

```nix
services.nixCsf = {
  enable = true;

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false;
  };

  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
    requireHTTPS = false;
    failOpen = true;
  };

  lfdDetector = {
    enable = true;
    journalIdentifier = "sshd"; # or sshdUnit = "sshd.service";
    threshold = 5;
    windowSeconds = 300;
    banTTLSeconds = 900;
    reason = "lfd:sshd_failed_login";
    refreshAfterBan = true;
    schedule.onCalendar = "minutely";
  };
};
```

Operational checks:

```bash
sudo systemctl status nix-csf-lfd-detector.timer --no-pager
sudo systemctl start nix-csf-lfd-detector.service
sudo systemctl status nix-csf-lfd-detector.service --no-pager
sudo journalctl -u nix-csf-lfd-detector.service -n 80 --no-pager
sudo cat /var/lib/nix-csf/lfd-detector.prom
sudo nft list set inet nix_csf dynamic_ban_ipv4
```

For deeper details and guardrails, see `docs/LFD_DETECTOR.md`.

## 16) fail2ban adapter (`fail2banAdapter.*`)

Use this when fail2ban should remain detector-only and `nix-csf` should remain the firewall authority.

```nix
services.nixCsf = {
  enable = true;

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false;
  };

  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
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
  };
};
```

Generated action file:

- `/etc/fail2ban/action.d/nix-csf.local`

Example jail usage:

```ini
[sshd]
enabled = true
banaction = nix-csf
```

Manual adapter checks:

```bash
sudo test -s /etc/fail2ban/action.d/nix-csf.local
sudo nix-csf-fail2ban-action ban --ip 203.0.113.77 --jail sshd
sudo nix-csf-fail2ban-action unban --ip 203.0.113.77 --jail sshd
```

For deeper details and guardrails, see `docs/FAIL2BAN_ADAPTER.md`.

## 17) Netdata integration (`netdata.*`)

Use this when your host is already running Netdata and you want direct charts/alarms from
the `nix_csf_*` metric surface.

```nix
{ pkgs, ... }:
{
  services.netdata = {
    enable = true;
    package = pkgs.netdataCloud;
    config.web = {
      "bind to" = "tcp:0.0.0.0:19999";
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
    };
  };
}
```

Generated Netdata files:

- `/etc/netdata/conf.d/charts.d.conf`
- `/etc/netdata/conf.d/charts.d/nix_csf.chart.sh`
- `/etc/netdata/conf.d/charts.d/nix_csf.conf`
- `/etc/netdata/conf.d/health.d/nix_csf.conf` (when `installHealthAlarms = true`)

Operational checks:

```bash
sudo systemctl status netdata --no-pager
sudo test -f /etc/netdata/conf.d/charts.d.conf
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.chart.sh
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.conf
sudo netdatacli ping
curl -sf http://127.0.0.1:19999/v3/ >/dev/null
sudo -u netdata test -r /var/lib/nix-csf/metrics.prom
sudo journalctl -u netdata -n 120 --no-pager
```

For detailed chart/alarm mapping, see `docs/NETDATA.md`.

## 18) Test server profile: global 80/443 + SSH 112 only from Bulgaria + Netdata + legacy CSF list import

Use this when migrating from a legacy CSF host and you want:

- public web ports (80/443) globally reachable,
- SSH moved to TCP/112 and limited to Bulgaria (`BG`),
- Netdata charts/alarms from `nix-csf` metrics,
- existing `csf.allow/csf.deny/csf.ignore` merged as local overlays.

### A) One-time import of legacy CSF files

If your repository is checked out under `/srv/nix-csf` and contains:

- `/srv/nix-csf/references/csf.allow`
- `/srv/nix-csf/references/csf.deny`
- `/srv/nix-csf/references/csf.ignore`

run:

```bash
sudo mkdir -p /var/lib/nix-csf/imported
sudo nix run "github:<org>/nix-csf#csf-import" -- \
  --allow-file /srv/nix-csf/references/csf.allow \
  --deny-file /srv/nix-csf/references/csf.deny \
  --ignore-file /srv/nix-csf/references/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

Review conversion report:

```bash
sudo sed -n '1,120p' /var/lib/nix-csf/imported/legacy-csf-summary.log
sudo sed -n '1,120p' /var/lib/nix-csf/imported/legacy-csf-unsupported.log
```

### B) NixOS configuration

```nix
{ pkgs, ... }:
{
  services.openssh = {
    enable = true;
    ports = [ 112 ];
  };

  services.netdata = {
    enable = true;
    package = pkgs.netdataCloud;
    config.web = {
      "bind to" = "tcp:0.0.0.0:19999";
      "allow dashboard from" = "localhost 127.0.0.1 ::1 172.16.0.0/16";
      "allow badges from" = "localhost 127.0.0.1 ::1 172.16.0.0/16";
    };
  };

  services.nixCsf = {
    enable = true;
    threatProfile = "custom";

    # Public services.
    openTCPPorts = [ 80 443 112 ];

    # Restrict only SSH port 112 to Bulgaria.
    country.portAllow = {
      enable = true;
      countries = [ "BG" ];
      tcpPorts = [ 112 ];
    };

    # Imported legacy CSF overlays.
    localFiles = {
      enable = true;
      failOnMissing = true;
      allow = [ "/var/lib/nix-csf/imported/legacy-csf-allow.local" ];
      deny = [ "/var/lib/nix-csf/imported/legacy-csf-deny.local" ];
      ignore = [ "/var/lib/nix-csf/imported/legacy-csf-ignore.local" ];
    };

    # Required for Netdata mapping.
    observability.metrics = {
      enable = true;
      outputFile = "/var/lib/nix-csf/metrics.prom";
    };

    netdata = {
      enable = true;
      updateEvery = 15;
      installHealthAlarms = true;
      alertRecipient = "sysadmin";
    };

    autoRefresh.onCalendar = "hourly";
  };
}
```

### C) Apply and verify

```bash
sudo nixos-rebuild switch
sudo systemctl show -P Result nix-csf-apply.service
sudo systemctl status netdata --no-pager
sudo test -f /etc/netdata/conf.d/charts.d.conf
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.chart.sh
sudo test -f /etc/netdata/conf.d/charts.d/nix_csf.conf
curl -sf http://127.0.0.1:19999/v3/ >/dev/null
sudo -u netdata test -r /var/lib/nix-csf/metrics.prom
sudo nft list table inet nix_csf
```

Important operator note:

- Do not cut over remote SSH access to port 112 until you confirm your current admin source IP is geolocated to `BG`.
- Keep console/out-of-band access available during first rollout.

### D) Flake equivalent with Nix-native LFD temp+permanent ban path

Use:

- `examples/flake/test-server-bg-netdata-lfd/flake.nix`

This example adds:

- `controlPlane.escalation.enable = true` for promotion from repeated temp bans to permanent deny,
- `lfdDetector.enable = true` to monitor sshd journal failures and emit temp bans,
- local `clusterPolicy` + `dynamicOffenders` URLs so both permanent and temporary ban sets are rendered.
