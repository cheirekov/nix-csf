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

If you run strict mode (`blocklists.failOpen = false` or `clusterPolicy.failOpen = false`),
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

## 4) Governed blocklist ingestion (catalog-only)

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

## 5) Cluster-wide policy propagation with per-node identity

Use this to centralize allow/deny overlays across many hosts.

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
    failOpen = false;
    authTokenFile = "/run/secrets/nix-csf-cluster-token";
    nodeId = "edge-us-01";
  };
};
```

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

## 6) Offline/lab environment with local files

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

## 7) Prometheus + structured logs for operations

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

## 8) Global opened ports baseline

Use this when you want globally exposed ports independent of geo filters.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 ];
};
```

## 9) Ports opened only to selected countries

Use country allow-mode with strict behavior.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 ];
  country = {
    enable = true;
    mode = "allow";
    countries = [ "US" "CA" ];
    failOpen = false;
  };
};
```

## 10) ICMP baseline and roadmap

Current module supports global ICMP enable/disable:

```nix
services.nixCsf = {
  enable = true;
  allowICMP = false; # set true if ICMP should be accepted
};
```

Per-type/per-rate ICMP controls are planned in `T-017`.
