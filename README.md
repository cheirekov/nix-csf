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
- Country-based deny feed support (CSF-style inspiration)
- External blocklist feed support
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

  synRateLimit = "50/second";
  logDrops = true;

  country = {
    enable = true;
    countries = [ "RU" "CN" ];
    # Defaults to ipdeny template:
    # ipv4URLTemplate = "https://www.ipdeny.com/ipblocks/data/countries/%s.zone";
  };

  blocklists = {
    enable = true;
    urls = [
      "https://www.spamhaus.org/drop/drop_v4.txt"
      "https://www.spamhaus.org/drop/drop_v6.txt"
    ];
  };

  autoRefresh = {
    enable = true;
    onCalendar = "hourly";
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

If `/dev/kvm` is unavailable, the VM test falls back to TCG emulation and runs slower.

## Project docs

- Architecture: `docs/ARCHITECTURE.md`
- Delivery board: `docs/DELIVERY_BOARD.md`
- Team rules: `docs/TEAM_OPERATING_RULES.md`
- Roadmap: `docs/ROADMAP.md`

## License

MIT (`LICENSE`)
