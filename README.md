# nix-csf

CSF-inspired firewall module for NixOS, built around `nftables` with a declarative interface.

This project is designed to work in both modes:

- as a flake input (`inputs.nix-csf.url = "github:<org>/nix-csf";`)
- as a classic module import (`imports = [ /path/to/nix-csf ];`)

## Status

Kickoff baseline is implemented:

- NixOS module: `services.nixCsf`
- Static allow/deny rules (IPv4 + IPv6)
- Port policy (`openTCPPorts`, `openUDPPorts`, ICMP toggle)
- ICMP policy profiles (`icmp.profile = legacy|off|safe|diagnostic|open`) with optional rate limit
- Stateful rate-limit presets (`rateLimits.synFlood`, `rateLimits.connFlood`)
- Preset threat profiles (`threatProfile = "server"|"workstation"|"edge"`)
- Country policy modes (`deny` and `allow`)
- Per-port country deny policy (`country.portDeny`, CSF `CC_DENY_PORTS` style)
- Per-port country allow policy (`country.portAllow`, CSF `CC_ALLOW_PORTS` style)
- Trusted blocklist source catalog + schema (`blocklists.catalog` + `blocklists.sources`)
- Hybrid local file overlays (`localFiles.allow|deny|ignore`)
- Legacy CSF list import bridge (`nix-csf-import-csf`)
- Cluster policy propagation overlay (`clusterPolicy.*`)
- Cluster policy schema v2 support (`ignore*`, `schemaVersion`, `revision`, `ttlSeconds`)
- Dynamic offender snapshot propagation with timeout sets (`dynamicOffenders.*`)
- Optional local control-plane snapshot publisher and mutation API (`controlPlane.*`)
- Operator mutation CLI (`nix-csfctl`) for control-plane workflows
- Dynamic escalation (`N` temporary bans => permanent deny via control-plane)
- LFD-like SSH detector pipeline (`lfdDetector.*` -> `ban-temp` write path)
- Auth token lifecycle with ordered rotation fallback (`*.authTokenFiles`)
- Firewall coexistence profiles (`coexistence.profile`, including Docker coexist mode)
- Monitoring pack assets (`docs/MONITORING.md`, Grafana dashboard, Prometheus alert rules)
- Troubleshooting command bundle (`nix-csf-triage` + `docs/TROUBLESHOOTING.md`)
- Structured run logs + optional Prometheus textfile metrics (`observability.*`)
- Early boot apply + scheduled refresh via systemd
- Module/release version source via `VERSION` (SemVer)

## Install (flake)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Prefer pinning a release tag in production:
    nix-csf.url = "github:<org>/nix-csf?ref=vX.Y.Z";
  };

  outputs = { self, nixpkgs, nix-csf, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-csf.nixosModules.default
        ({ ... }: {
          services.nixCsf = {
            enable = true;
            openTCPPorts = [ 22 80 443 ];
            openUDPPorts = [ 53 ];
            country.enable = true;
            country.countries = [ "RU" "CN" ];
          };
        })
      ];
    };
  };
}
```

## Install (non-flake)

```nix
{ ... }:
{
  imports = [
    /path/to/nix-csf
  ];

  services.nixCsf = {
    enable = true;
    openTCPPorts = [ 22 443 ];
    country.enable = true;
    country.countries = [ "RU" "CN" ];
  };
}
```

For remote tarball usage:

```nix
imports = [
  "${builtins.fetchTarball "https://github.com/<org>/nix-csf/archive/refs/tags/vX.Y.Z.tar.gz"}"
];
```

## Example configuration

```nix
services.nixCsf = {
  enable = true;
  threatProfile = "custom"; # custom | server | workstation | edge

  trustedInterfaces = [ "tailscale0" "wg0" ];
  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 51820 ];
  icmp = {
    profile = "safe"; # legacy | off | safe | diagnostic | open
    rateLimit = {
      enable = true;
      rate = "30/second";
      burst = 120;
    };
  };

  allowIPv4 = [ "10.0.0.0/8" ];
  denyIPv4 = [ "198.51.100.0/24" ];

  rateLimits = {
    synFlood = {
      enable = true;
      preset = "balanced"; # relaxed | balanced | strict
    };
    connFlood = {
      enable = true;
      preset = "balanced"; # relaxed | balanced | strict
    };
  };

  # Legacy one-line SYN limiter (do not combine with rateLimits.synFlood.enable):
  # synRateLimit = "50/second";
  logDrops = true;

  country = {
    enable = true;
    mode = "deny"; # or "allow"
    countries = [ "RU" "CN" ];
    # Defaults to ipdeny template:
    # ipv4URLTemplate = "https://www.ipdeny.com/ipblocks/data/countries/%s.zone";

    # Optional: deny specific ports only for selected countries.
    # Ports should remain present in openTCPPorts/openUDPPorts.
    portDeny = {
      enable = true;
      countries = [ "RU" "CN" ];
      tcpPorts = [ 21 443 ];
      udpPorts = [ ];
    };

    # Optional: allow selected ports only for selected countries.
    # Ports should remain present in openTCPPorts/openUDPPorts.
    portAllow = {
      enable = true;
      countries = [ "US" "CA" ];
      tcpPorts = [ 22 443 ];
      udpPorts = [ 53 ];
    };
  };

  blocklists = {
    enable = true;
    # Enable trusted catalog entries:
    sources = [ "spamhaus-drop-v4" "spamhaus-drop-v6" ];
    # Parser accepts plain CIDR/IP lines and ipset-style lines:
    #   add <set_name> <cidr_or_ip>
    # Optional governance hardening:
    enforceCatalog = true;

    # Optional legacy path (prefer sources/catalog):
    urls = [
      # "https://example.invalid/custom-feed.txt"
    ];
  };

  # Optional local operator-managed files merged at runtime.
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
    failOpen = true;
    # Optional node identity and auth:
    # nodeId = "edge-eu-01";
    # authTokenFile = "/run/secrets/nix-csf-cluster-token";
    # authTokenFiles = [
    #   "/run/secrets/nix-csf-cluster-token-current"
    #   "/run/secrets/nix-csf-cluster-token-next"
    # ];
  };

  dynamicOffenders = {
    enable = true;
    url = "https://policy.example.org/nix-csf/dynamic-offenders.json";
    failOpen = true;
    defaultEntryTTLSeconds = 900;
    maxEntries = 20000;
    # Optional node identity and auth:
    # nodeId = "edge-eu-01";
    # authTokenFile = "/run/secrets/nix-csf-dynamic-token";
    # authTokenFiles = [
    #   "/run/secrets/nix-csf-dynamic-token-current"
    #   "/run/secrets/nix-csf-dynamic-token-next"
    # ];
  };

  # Optional: local mutable control-plane (single-node or master-node mode).
  # Keeps runtime mutable state under /var/lib/nix-csf-control-plane.
  # controlPlane = {
  #   enable = true;
  #   bindAddress = "127.0.0.1";
  #   port = 18081;
  #   environment = "lab";
  #   requireAuth = false; # set true in production and provide authTokenFile
  # };

  # Optional: LFD-like SSH detector (journal signal -> control-plane temp ban).
  # lfdDetector = {
  #   enable = true;
  #   journalIdentifier = "sshd";
  #   # sshdUnit = "sshd.service";
  #   windowSeconds = 300;
  #   threshold = 5;
  #   banTTLSeconds = 900;
  #   refreshAfterBan = true;
  # };

  coexistence.profile = "exclusive-firewall"; # or "docker-coexist" for container hosts

  observability = {
    structuredLogging = true;
    metrics = {
      enable = true;
      outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
    };
  };

  autoRefresh = {
    enable = true;
    onCalendar = "hourly";
  };
};
```

Import helper for legacy CSF lists (`csf.allow/csf.deny/csf.ignore`):

```bash
nix-csf-import-csf \
  --allow-file /etc/csf/csf.allow \
  --deny-file /etc/csf/csf.deny \
  --ignore-file /etc/csf/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

## Use Cases

For a full operator-oriented catalog (including strict/fail-closed and offline patterns), see `docs/USE_CASES.md`.

### Threat profile quick-starts

```nix
# Server baseline: enables balanced flood controls + logDrops + hourly refresh.
services.nixCsf.threatProfile = "server";

# Workstation baseline: no inbound open TCP/UDP ports by default.
services.nixCsf.threatProfile = "workstation";

# Edge baseline: opens 22/443 TCP + 53/51820 UDP and enables stricter flood controls.
services.nixCsf.threatProfile = "edge";
```

### 1) Public web server with conservative DDoS posture

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 80 443 ];
  rateLimits.synFlood = { enable = true; preset = "strict"; };
  rateLimits.connFlood = { enable = true; preset = "balanced"; };
};
```

### 2) Country allow-list for inbound traffic

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 ];
  country = {
    enable = true;
    mode = "allow";
    countries = [ "US" "CA" ];
  };
};
```

### 3) Port-scoped country deny (CSF `CC_DENY_PORTS` style)

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

### 4) Port-scoped country allow (CSF `CC_ALLOW_PORTS` style)

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 22 443 ];
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

### 5) Enable Prometheus textfile metrics

```nix
services.nixCsf = {
  enable = true;
  observability.metrics = {
    enable = true;
    outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
  };
};
```

### 6) Centralized cluster allow/deny propagation

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
    failOpen = false; # fail refresh if policy is unreachable and no cache exists
    authTokenFiles = [
      "/run/secrets/nix-csf-cluster-token-current"
      "/run/secrets/nix-csf-cluster-token-next"
    ];
    nodeId = "edge-eu-01";
  };
};
```

Expected remote JSON structure:

```json
{
  "schemaVersion": 2,
  "revision": "prod-2026-02-20-01",
  "ttlSeconds": 3600,
  "allowIPv4": ["172.20.0.0/16"],
  "allowIPv6": ["2001:db8:66::/48"],
  "denyIPv4": ["203.0.114.0/24"],
  "denyIPv6": ["2001:db8:bad::/48"],
  "ignoreIPv4": ["203.0.114.7/32"],
  "ignoreIPv6": []
}
```

### 7) Dynamic temporary offender propagation (TTL)

```nix
services.nixCsf = {
  enable = true;
  dynamicOffenders = {
    enable = true;
    url = "https://policy.example.org/nix-csf/dynamic-offenders.json";
    failOpen = false;
    defaultEntryTTLSeconds = 900;
    maxEntries = 20000;
    authTokenFiles = [
      "/run/secrets/nix-csf-dynamic-token-current"
      "/run/secrets/nix-csf-dynamic-token-next"
    ];
    nodeId = "edge-eu-01";
  };
};
```

Expected dynamic snapshot JSON structure:

```json
{
  "schemaVersion": 1,
  "revision": "dyn-2026-02-20-01",
  "ttlSeconds": 300,
  "banIPv4": [
    "203.0.116.8/32",
    { "cidr": "203.0.116.9/32", "ttlSeconds": 600 },
    { "cidr": "203.0.116.10/32", "expiresAt": 1771593600, "reason": "syn_flood" }
  ],
  "banIPv6": []
}
```

### 8) Docker host coexistence profile

```nix
services.nixCsf = {
  enable = true;
  coexistence.profile = "docker-coexist";
  forwardPolicy = "accept"; # required by docker-coexist profile
  denyIPv4 = [ "198.51.100.0/24" ];
};
```

### 9) Local mutable deny/temp-ban workflow (no external cluster required)

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/lab/cluster-policy.json";
    requireHTTPS = false;
    failOpen = true;
  };
  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
    requireHTTPS = false;
    failOpen = true;
  };
  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false;
  };
};
```

Example runtime mutations:

```bash
nix-csfctl policy add deny 203.0.119.9/32

nix-csfctl ban-temp 203.0.119.10/32 --ttl 900 --reason syn_flood

nix-csfctl promotions --limit 20

sudo systemctl start nix-csf-refresh.service
```

When control-plane auth is enabled:

```bash
nix-csfctl --auth-token-file /run/secrets/nix-csf-control-plane-token \
  policy add deny 203.0.120.4/32
```

### 10) LFD-like SSH detector (Nix-native)

```nix
services.nixCsf = {
  enable = true;
  controlPlane = {
    enable = true;
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
    journalIdentifier = "sshd";
    threshold = 5;
    windowSeconds = 300;
    banTTLSeconds = 900;
    refreshAfterBan = true;
  };
};
```

Operator checks:

```bash
sudo systemctl start nix-csf-lfd-detector.service
sudo journalctl -u nix-csf-lfd-detector.service -n 80 --no-pager
sudo cat /var/lib/nix-csf/lfd-detector.prom
```

Detailed runbook: `docs/LFD_DETECTOR.md`.

## Operational notes

- This module expects `networking.firewall.enable = false` (asserted by the module).
- Rule apply service runs before network stack comes up (`network-pre.target`).
- Refresh service runs after network is online and can be periodic via timer.
- With `blocklists.failOpen = false` or `clusterPolicy.failOpen = false`, `apply` requires cached data.
- With `dynamicOffenders.failOpen = false`, `apply` also requires cached dynamic snapshot data.
  Run `sudo systemctl start nix-csf-refresh.service` at least once after network is available.
- Cluster policy cache can be guarded by `ttlSeconds` from the snapshot payload.
  In strict mode (`clusterPolicy.failOpen = false`), expired cached policy fails closed.
- Dynamic snapshots are also guarded by `ttlSeconds`.
  In strict mode (`dynamicOffenders.failOpen = false`), expired cached snapshot fails closed.
- Dynamic bans are evaluated after explicit allow rules, so allow/ignore overlays can override temporary bans.
- Effective ignore precedence is hybrid-aware: `localFiles.ignore` + cluster `ignore*` are merged,
  promoted into allow sets, and subtracted from deny-style overlays.
- `clusterPolicy.authTokenFiles` and `dynamicOffenders.authTokenFiles` allow staged token rotation;
  candidates are tried in order until one succeeds.
- Auth token files are validated strictly at runtime:
  absolute paths, readable files, no group/other permission bits, and no whitespace in token values.
- `coexistence.profile = "docker-coexist"` keeps forward policy in accept mode so Docker/dynamic daemons can manage forwarding,
  while nix-csf still applies deny-style overlays in the forward hook.
- Rule evaluation is deny-first for static allow/deny CIDRs (`denyIPv4/denyIPv6` are matched before `allowIPv4/allowIPv6`).
- Generated runtime artifacts live in `/var/lib/nix-csf`.
- `services.nixCsf.controlPlane.dataDir` (default `/var/lib/nix-csf-control-plane`) is runtime mutable state
  and is not overwritten by `nixos-rebuild`.
- Enabling `services.nixCsf.controlPlane.enable = true` installs both:
  `nix-csf-control-plane` and `nix-csfctl`.
- Enabling `services.nixCsf.lfdDetector.enable = true` installs `nix-csf-lfd-detector`
  and creates `nix-csf-lfd-detector.timer`.

## Validation

Fast iteration check (no VM tests):

```bash
./scripts/validate-fast.sh
```

Full validation (includes x86_64 VM smoke + integration):

```bash
./scripts/validate.sh
```

Full validation with log capture (recommended for operator handoff):

```bash
./scripts/validate-capture.sh
```

The validation script runs:

- `checks.x86_64-linux.version-semver` (VERSION SemVer gate)
- `checks.x86_64-linux.eval-basic` (module evaluation wiring)
- `checks.x86_64-linux.eval-profiles` (profile defaults + override precedence)
- `checks.x86_64-linux.eval-control-plane` (control-plane service wiring evaluation)
- `checks.x86_64-linux.eval-lfd-detector` (LFD-like detector service/timer wiring evaluation)
- `checks.x86_64-linux.eval-monitoring` (Prometheus/Grafana wiring evaluation)
- `checks.x86_64-linux.csf-import-check` (legacy CSF import bridge behavior)
- `checks.x86_64-linux.shellcheck` (script lint)
- `checks.x86_64-linux.control-plane-lint` (control-plane script syntax)
- `checks.x86_64-linux.monitoring-pack` (Grafana JSON + Prometheus alert rule lint)
- `checks.x86_64-linux.nix-csf-smoke` (baseline policy/rendering)
- `checks.x86_64-linux.nix-csf-integration` (fail-closed paths, edge-profile checks, dynamic snapshot TTL expiry, Docker coexistence, auth-token rotation fallback, and LFD-like detector flow)

If `/dev/kvm` is unavailable, the VM test falls back to TCG emulation and runs slower.

Suggested collaboration loop:

1. Agent runs `./scripts/validate-fast.sh` after each implementation step.
2. Operator runs `./scripts/validate-capture.sh` for VM/full checks.
3. If failing, share `*.summary.log` from `.artifacts/validate` for focused triage.

Quick host troubleshooting bundle:

```bash
sudo nix-csf-triage --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
```

## Versioning and releases

- `VERSION` is the source of truth for module/project version.
- Release tags follow `v<semver>` (for example `v0.2.0`).
- Compatibility policy:
  - `MAJOR`: breaking module API/behavior changes.
  - `MINOR`: backward-compatible features.
  - `PATCH`: backward-compatible fixes/docs/tests.

Release workflow (maintainer):

```bash
# Preview checks only (no commit/tag):
./scripts/release.sh --version 0.2.0 --dry-run

# Create release commit + annotated tag:
./scripts/release.sh --version 0.2.0

# Create and push in one step:
./scripts/release.sh --version 0.2.0 --push
```

Consumers can pin by tag:

- flake: `github:<org>/nix-csf?ref=v0.2.0`
- non-flake tarball: `.../archive/refs/tags/v0.2.0.tar.gz`

## Project docs

- Architecture: `docs/ARCHITECTURE.md`
- LFD Nix-way POC plan: `docs/LFD_NIX_WAY_POC.md`
- Dynamic cluster POC recommendation: `docs/DYNAMIC_CLUSTER_POC.md`
- Cluster control-plane retro/POC: `docs/CLUSTER_CONTROL_PLANE_POC.md`
- Operator use-case catalog: `docs/USE_CASES.md`
- CSF list migration guide: `docs/CSF_IMPORT.md`
- Monitoring pack and runbook: `docs/MONITORING.md`
- Troubleshooting command set/runbook: `docs/TROUBLESHOOTING.md`
- Release/compatibility policy: `docs/RELEASE.md`
- Delivery board: `docs/DELIVERY_BOARD.md`
- Team rules: `docs/TEAM_OPERATING_RULES.md`
- Roadmap: `docs/ROADMAP.md`
- Blocklist catalog schema: `docs/schemas/blocklist-catalog.schema.json`

## License

MIT (`LICENSE`)
