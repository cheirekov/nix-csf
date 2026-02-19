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
- Country policy modes (`deny` and `allow`)
- Per-port country deny policy (`country.portDeny`, CSF `CC_DENY_PORTS` style)
- Trusted blocklist source catalog + schema (`blocklists.catalog` + `blocklists.sources`)
- Structured run logs + optional Prometheus textfile metrics (`observability.*`)
- Early boot apply + scheduled refresh via systemd

## Install (flake)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-csf.url = "github:<org>/nix-csf";
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
  "${builtins.fetchTarball "https://github.com/<org>/nix-csf/archive/main.tar.gz"}"
];
```

## Example configuration

```nix
services.nixCsf = {
  enable = true;

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

## Operational notes

- This module expects `networking.firewall.enable = false` (asserted by the module).
- Rule apply service runs before network stack comes up (`network-pre.target`).
- Refresh service runs after network is online and can be periodic via timer.
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

The validation script now runs two x86_64 VM suites:

- `checks.x86_64-linux.nix-csf-smoke` (baseline policy/rendering)
- `checks.x86_64-linux.nix-csf-integration` (fail-closed and legacy-mode integration coverage)

If `/dev/kvm` is unavailable, the VM test falls back to TCG emulation and runs slower.

## Project docs

- Architecture: `docs/ARCHITECTURE.md`
- Delivery board: `docs/DELIVERY_BOARD.md`
- Team rules: `docs/TEAM_OPERATING_RULES.md`
- Roadmap: `docs/ROADMAP.md`
- Blocklist catalog schema: `docs/schemas/blocklist-catalog.schema.json`

## License

MIT (`LICENSE`)
