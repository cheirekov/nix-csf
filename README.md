# nix-csf

CSF-inspired firewall module for NixOS, built around `nftables` with declarative policy, mutable runtime overlays, and operator-focused tooling.

Works in both modes:

- flake input (`inputs.nix-csf.url = "github:cheirekov/nix-csf"`)
- non-flake import (`imports = [ /path/to/nix-csf ];`)

Current module version source of truth: `VERSION`.

## Quick links

- Start here:
  - Flake example: `examples/flake/test-server-bg-netdata-lfd/flake.nix`
  - Non-flake example: `examples/non-flake/test-server-bg-netdata-import.nix`
- Day-2 operations:
  - Scripts/runbook index: `docs/SCRIPTS_RUNBOOK.md`
  - Security validation runbook: `docs/SECURITY_VALIDATION_RUNBOOK.md`
  - Troubleshooting: `docs/TROUBLESHOOTING.md`
  - Use-case catalog: `docs/USE_CASES.md`
  - Deployment blueprints: `docs/DEPLOYMENT_BLUEPRINTS.md`
  - Authoritative DNS blueprint: `docs/BIND_PRODUCTION_BLUEPRINT.md`
- Security and architecture:
  - Architecture: `docs/ARCHITECTURE.md`
  - Cluster control-plane POC: `docs/CLUSTER_CONTROL_PLANE_POC.md`
  - Control-plane TLS proxy POC: `docs/CONTROL_PLANE_TLS_PROXY_POC.md`
  - Cluster auth token runbook: `docs/CLUSTER_AUTH_TOKENS.md`
  - Dynamic/cluster recommendation: `docs/DYNAMIC_CLUSTER_POC.md`
- Monitoring:
  - Prometheus/Grafana: `docs/MONITORING.md`
  - Netdata integration: `docs/NETDATA.md`
- Migration:
  - Legacy CSF import: `docs/CSF_IMPORT.md`
  - Release hardening gate: `docs/RELEASE_CANDIDATE_HARDENING.md`
  - RC decision package: `docs/RELEASE_CANDIDATE_DECISION.md`

## What is implemented

- Core module: `services.nixCsf`
- Stateful baseline firewall (`nftables`) with strict apply/refresh pipeline
- Static local policy sets: `allow*`, `deny*`, open ports, ICMP profiles
- DNS-focused flood meters with optional trusted-source bypass selectors (`rateLimits.dnsFlood.*`)
- Country controls:
  - full-country deny/allow modes,
  - per-port country deny (`CC_DENY_PORTS` style),
  - per-port country allow (`CC_ALLOW_PORTS` style)
- Feed-backed deny overlays (catalog + source governance)
- Hybrid local file overlays (`localFiles.allow|deny|ignore`)
- Legacy CSF import tool (`nix-csf-import-csf`)
- Cluster policy + dynamic offender snapshots (TTL-aware)
- Optional local control-plane + `nix-csfctl` mutation workflow
- Escalation engine v2 for temp->perm promotion (`controlPlane.escalation.*`: threshold/window/cooldown/reasonClasses + audit IDs)
- Cluster propagation semantics v2 (`controlPlane.propagation.*`: local vs cluster scope defaults, provenance metadata, replay marker)
- Nix-native LFD-like detector framework v2 (explicit `lfdDetector.detectors` or curated `lfdDetector.detectorPack`) and fail2ban adapter
  - built-in templates: `ssh-auth`, `nginx-auth`, `dovecot-auth`, plus opt-in `caddy-auth`, `postfix-sasl`, `control-plane-auth`, and `api-proxy-auth`
- Auth token rotation (`*.authTokenFiles`) for remote snapshots
- Docker coexistence profile (`coexistence.profile = "docker-coexist"`)
- NAT datapath foundation (`nat.*`: IPv4 masquerade + explicit port forwards)
- Forwarding policy matrix (`forwarding.zones` + `forwarding.rules`)
- Optional egress controls (`egress.*`: output policy + destination/interface allow/deny selectors)
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
    propagation = {
      policyDefaultScope = "cluster";
      dynamicDefaultScope = "cluster";
      escalationPromotionScope = "cluster";
      requireNodeForLocalScope = true;
      includeProvenanceMetadata = true;
    };
  };

  lfdDetector = {
    enable = true;
    detectorPack = {
      enable = true;
      profile = "server-web"; # ssh-auth + nginx-auth
      sshAuth.threshold = 5;
      nginxAuth.threshold = 10;
      caddyAuth.enable = true; # optional template
      postfixSasl.enable = true; # optional template
      controlPlaneAuth.enable = true; # optional template
      apiProxyAuth.enable = true; # optional template
    };
    refreshAfterBan = true;
  };
};
```

Offline policy authoring/compile path:

```bash
nix-csfctl --output pretty policy compile --input ./policy-source.json --cluster-output ./cluster-policy.json --dynamic-output ./dynamic-offenders.json
```

### Netdata noise profile (optional)

```nix
services.nixCsf = {
  netdata = {
    enable = true;
    # Reduce non-critical default charts.d module checks while keeping nix_csf charts.
    noiseProfile = "chartsd-minimal"; # off | chartsd-minimal
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

### NAT gateway foundation (Stage 1, IPv4)

```nix
services.nixCsf = {
  nat = {
    enable = true;
    externalInterface = "eth0";
    masquerade = {
      enable = true;
      sourceIPv4 = [ "10.42.0.0/16" ];
    };
    portForwards = [
      {
        protocol = "tcp";
        externalPort = 8080;
        destinationAddress = "10.42.0.10";
        destinationPort = 80;
        sourceIPv4 = [ "198.51.100.0/24" ];
      }
    ];
  };
};
```

### Forwarding policy matrix (Stage 1)

```nix
services.nixCsf = {
  forwardPolicy = "drop";

  forwarding = {
    zones = {
      lan = {
        interfaces = [ "br-lan" ];
        cidrIPv4 = [ "10.42.0.0/16" ];
      };
      wan = {
        interfaces = [ "eth0" ];
      };
    };

    rules = [
      {
        fromZone = "lan";
        toZone = "wan";
        protocol = "tcp";
        destinationPorts = [ 80 443 ];
      }
    ];
  };
};
```

### Optional egress controls (Stage 1)

```nix
services.nixCsf = {
  egress = {
    enable = true;
    defaultPolicy = "drop";
    trustedInterfaces = [ "wg0" ];
    allowIPv4 = [ "198.51.100.0/24" ];
    denyIPv4 = [ "203.0.113.0/24" ];
    allowTCPPorts = [ 53 443 ];
    allowUDPPorts = [ 53 ];
  };
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
nix-csfctl --node-id edge-us-01 policy add deny 203.0.119.140/32 --scope local --source lfd
nix-csfctl ban-temp 203.0.119.10/32 --ttl 900 --reason syn_flood
nix-csfctl ban-temp 203.0.119.142/32 --ttl 600 --reason lfd:ssh_auth --scope local --node-id edge-us-01 --source lfd
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
- Stage-1 NAT is IPv4-focused and not combined with `coexistence.profile = "docker-coexist"`.
- `forwarding.rules` requires `forwardPolicy = "drop"` and is not combined with `coexistence.profile = "docker-coexist"` in Stage 1.
- `egress.enable = false` keeps output policy lockout-safe (`accept`).
- When `egress.enable = true` and `egress.defaultPolicy = "drop"`, define explicit allow selectors (`trustedInterfaces`, allow CIDRs, or allow ports).
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
- `docs/EPIC_FIREWALL_LFD_EXPANSION.md`
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
