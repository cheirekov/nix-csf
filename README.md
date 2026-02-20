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
- Stateful rate-limit presets (`rateLimits.synFlood`, `rateLimits.connFlood`)
- Preset threat profiles (`threatProfile = "server"|"workstation"|"edge"`)
- Country policy modes (`deny` and `allow`)
- Per-port country deny policy (`country.portDeny`, CSF `CC_DENY_PORTS` style)
- Trusted blocklist source catalog + schema (`blocklists.catalog` + `blocklists.sources`)
- Cluster policy propagation overlay (`clusterPolicy.*`)
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
  };

  blocklists = {
    enable = true;
    # Enable trusted catalog entries:
    sources = [ "spamhaus-drop-v4" "spamhaus-drop-v6" ];
    # Optional governance hardening:
    enforceCatalog = true;

    # Optional legacy path (prefer sources/catalog):
    urls = [
      # "https://example.invalid/custom-feed.txt"
    ];
  };

  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
    failOpen = true;
    # Optional node identity and auth:
    # nodeId = "edge-eu-01";
    # authTokenFile = "/run/secrets/nix-csf-cluster-token";
  };

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

### 4) Enable Prometheus textfile metrics

```nix
services.nixCsf = {
  enable = true;
  observability.metrics = {
    enable = true;
    outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
  };
};
```

### 5) Centralized cluster allow/deny propagation

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod-edge.json";
    failOpen = false; # fail refresh if policy is unreachable and no cache exists
    authTokenFile = "/run/secrets/nix-csf-cluster-token";
    nodeId = "edge-eu-01";
  };
};
```

Expected remote JSON structure:

```json
{
  "allowIPv4": ["172.20.0.0/16"],
  "allowIPv6": ["2001:db8:66::/48"],
  "denyIPv4": ["203.0.114.0/24"],
  "denyIPv6": ["2001:db8:bad::/48"]
}
```

## Operational notes

- This module expects `networking.firewall.enable = false` (asserted by the module).
- Rule apply service runs before network stack comes up (`network-pre.target`).
- Refresh service runs after network is online and can be periodic via timer.
- With `blocklists.failOpen = false` or `clusterPolicy.failOpen = false`, `apply` requires cached data.
  Run `sudo systemctl start nix-csf-refresh.service` at least once after network is available.
- Rule evaluation is deny-first for static allow/deny CIDRs (`denyIPv4/denyIPv6` are matched before `allowIPv4/allowIPv6`).
- Generated runtime artifacts live in `/var/lib/nix-csf`.

## Validation

Quick check (evaluation only):

```bash
nix flake check "path:$(pwd)" --all-systems --no-build
```

Full validation (includes x86_64 VM smoke test):

```bash
./scripts/validate.sh
```

The validation script runs:

- `checks.x86_64-linux.version-semver` (VERSION SemVer gate)
- `checks.x86_64-linux.eval-basic` (module evaluation wiring)
- `checks.x86_64-linux.eval-profiles` (profile defaults + override precedence)
- `checks.x86_64-linux.shellcheck` (script lint)
- `checks.x86_64-linux.nix-csf-smoke` (baseline policy/rendering)
- `checks.x86_64-linux.nix-csf-integration` (fail-closed, legacy-mode, and edge-profile integration coverage)

If `/dev/kvm` is unavailable, the VM test falls back to TCG emulation and runs slower.

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
- Operator use-case catalog: `docs/USE_CASES.md`
- Release/compatibility policy: `docs/RELEASE.md`
- Delivery board: `docs/DELIVERY_BOARD.md`
- Team rules: `docs/TEAM_OPERATING_RULES.md`
- Roadmap: `docs/ROADMAP.md`
- Blocklist catalog schema: `docs/schemas/blocklist-catalog.schema.json`

## License

MIT (`LICENSE`)
