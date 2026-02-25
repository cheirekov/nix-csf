# nix-csf

CSF-inspired firewall module for NixOS, built around `nftables` with declarative policy, mutable runtime overlays, and operator-focused tooling.

Works in both modes:

- flake input (`inputs.nix-csf.url = "github:<org>/nix-csf"`)
- non-flake import (`imports = [ /path/to/nix-csf ];`)

Current module version source of truth: `VERSION`.

## Quick links

- Start here:
  - Flake example: `examples/flake/test-server-bg-netdata-lfd/flake.nix`
  - Non-flake example: `examples/non-flake/test-server-bg-netdata-import.nix`
- Day-2 operations:
  - Scripts/runbook index: `docs/SCRIPTS_RUNBOOK.md`
  - Troubleshooting: `docs/TROUBLESHOOTING.md`
  - Use-case catalog: `docs/USE_CASES.md`
- Security and architecture:
  - Architecture: `docs/ARCHITECTURE.md`
  - Cluster control-plane POC: `docs/CLUSTER_CONTROL_PLANE_POC.md`
  - Dynamic/cluster recommendation: `docs/DYNAMIC_CLUSTER_POC.md`
- Monitoring:
  - Prometheus/Grafana: `docs/MONITORING.md`
  - Netdata integration: `docs/NETDATA.md`
- Migration:
  - Legacy CSF import: `docs/CSF_IMPORT.md`

## What is implemented

- Core module: `services.nixCsf`
- Stateful baseline firewall (`nftables`) with strict apply/refresh pipeline
- Static local policy sets: `allow*`, `deny*`, open ports, ICMP profiles
- Country controls:
  - full-country deny/allow modes,
  - per-port country deny (`CC_DENY_PORTS` style),
  - per-port country allow (`CC_ALLOW_PORTS` style)
- Feed-backed deny overlays (catalog + source governance)
- Hybrid local file overlays (`localFiles.allow|deny|ignore`)
- Legacy CSF import tool (`nix-csf-import-csf`)
- Cluster policy + dynamic offender snapshots (TTL-aware)
- Optional local control-plane + `nix-csfctl` mutation workflow
- Nix-native LFD-like detector (`lfdDetector`) and fail2ban adapter
- Auth token rotation (`*.authTokenFiles`) for remote snapshots
- Docker coexistence profile (`coexistence.profile = "docker-coexist"`)
- Structured logs + Prometheus textfile metrics + Netdata integration
- Validation lanes split for agent/operator workflows

## Install

### Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-csf.url = "github:<org>/nix-csf?ref=vX.Y.Z";
  };

  outputs = { nixpkgs, nix-csf, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-csf.nixosModules.default
        ({ ... }: {
          services.nixCsf = {
            enable = true;
            openTCPPorts = [ 22 80 443 ];
          };
        })
      ];
    };
  };
}
```

### Non-flake

```nix
{ ... }:
{
  imports = [
    /path/to/nix-csf
  ];

  services.nixCsf = {
    enable = true;
    openTCPPorts = [ 22 443 ];
  };
}
```

### Remote tarball import (non-flake)

```nix
imports = [
  "${builtins.fetchTarball "https://github.com/<org>/nix-csf/archive/refs/tags/vX.Y.Z.tar.gz"}"
];
```

## Minimal configuration

```nix
services.nixCsf = {
  enable = true;
  threatProfile = "server"; # custom | server | workstation | edge

  openTCPPorts = [ 22 80 443 ];
  openUDPPorts = [ 53 ];

  icmp = {
    profile = "safe"; # legacy | off | safe | diagnostic | open
    rateLimit = {
      enable = true;
      rate = "30/second";
      burst = 120;
    };
  };

  observability.metrics = {
    enable = true;
    outputFile = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
  };

  autoRefresh.onCalendar = "hourly";
};
```

For production-style complete examples (global ports + country-restricted SSH + imported legacy lists + local control-plane + LFD detector), use:

- `examples/flake/test-server-bg-netdata-lfd/flake.nix`
- `examples/non-flake/test-server-bg-netdata-import.nix`

## Feature quick reference

### Country policy

```nix
services.nixCsf.country = {
  enable = true;
  mode = "deny"; # deny | allow
  countries = [ "RU" "CN" ];

  portDeny = {
    enable = true;
    countries = [ "RU" "CN" ];
    tcpPorts = [ 443 ];
  };

  portAllow = {
    enable = true;
    countries = [ "BG" ];
    tcpPorts = [ 112 ];
  };
};
```

### Local + cluster + dynamic overlays

```nix
services.nixCsf = {
  localFiles = {
    enable = true;
    allow = [ "/var/lib/nix-csf/lists/allow.local" ];
    deny = [ "/var/lib/nix-csf/lists/deny.local" ];
    ignore = [ "/var/lib/nix-csf/lists/ignore.local" ];
  };

  clusterPolicy = {
    enable = true;
    url = "https://policy.example.org/nix-csf/prod.json";
    failOpen = true;
  };

  dynamicOffenders = {
    enable = true;
    url = "https://policy.example.org/nix-csf/dynamic-offenders.json";
    defaultEntryTTLSeconds = 900;
    maxEntries = 20000;
    failOpen = true;
  };
};
```

### Local mutable control-plane and LFD-like detector

```nix
services.nixCsf = {
  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false; # lab only
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

### Docker coexistence

```nix
services.nixCsf = {
  coexistence.profile = "docker-coexist";
  forwardPolicy = "accept";
};
```

## Operator commands

### Legacy CSF import

```bash
nix-csf-import-csf \
  --allow-file /etc/csf/csf.allow \
  --deny-file /etc/csf/csf.deny \
  --ignore-file /etc/csf/csf.ignore \
  --output-dir /var/lib/nix-csf/imported \
  --prefix legacy-csf
```

### Control-plane mutations

```bash
nix-csfctl policy add deny 203.0.119.9/32
nix-csfctl ban-temp 203.0.119.10/32 --ttl 900 --reason syn_flood
nix-csfctl promotions --limit 20
sudo systemctl start nix-csf-refresh.service
```

### Quick triage snapshot

```bash
sudo nix-csf-triage --output /tmp/nix-csf-triage-$(date -u +%Y%m%dT%H%M%SZ).log
```

## Validation model

### Agent lane (no `nix build`)

```bash
./scripts/validate-agent.sh
```

Alias:

```bash
./scripts/validate-fast.sh
```

### Operator lane (full checks + VM tests)

```bash
./scripts/validate.sh
```

With captured summary/log handoff:

```bash
./scripts/validate-capture.sh
```

## Operational notes

- Module asserts `networking.firewall.enable = false`.
- Apply service runs before network stack (`network-pre.target`).
- Refresh service runs after network is online.
- `failOpen = false` for feeds/snapshots requires valid cache and can fail closed.
- Dynamic bans are evaluated after explicit allow/ignore overlays.
- Local list conflict audit artifacts are written to:
  - `/var/lib/nix-csf/local-list-audit-summary.tsv`
  - `/var/lib/nix-csf/local-list-conflicts.tsv`
- Runtime-generated state is under `/var/lib/nix-csf` and `/var/lib/nix-csf-control-plane`.

## Versioning and releases

- `VERSION` is source of truth.
- Tags follow `v<semver>`.
- `MAJOR`: breaking changes.
- `MINOR`: backward-compatible features.
- `PATCH`: backward-compatible fixes.

Release commands:

```bash
./scripts/release.sh --version 1.0.3 --dry-run
./scripts/release.sh --version 1.0.3
./scripts/release.sh --version 1.0.3 --push
```

## Documentation map

### Core

- `docs/ARCHITECTURE.md`
- `docs/USE_CASES.md`
- `docs/TROUBLESHOOTING.md`
- `docs/SCRIPTS_RUNBOOK.md`

### Security and policy evolution

- `docs/LFD_NIX_WAY_POC.md`
- `docs/DYNAMIC_CLUSTER_POC.md`
- `docs/CLUSTER_CONTROL_PLANE_POC.md`

### Integrations and observability

- `docs/MONITORING.md`
- `docs/NETDATA.md`
- `docs/FAIL2BAN_ADAPTER.md`
- `docs/LFD_DETECTOR.md`

### Migration and release

- `docs/CSF_IMPORT.md`
- `docs/RELEASE.md`

### Project governance

- `docs/DELIVERY_BOARD.md`
- `docs/SESSION_BRIEF.md`
- `docs/PM_BA_CHANGELOG.md`
- `docs/TEAM_OPERATING_RULES.md`
- `docs/ROADMAP.md`

## License

MIT (`LICENSE`)
