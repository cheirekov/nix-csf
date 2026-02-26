# Deployment Blueprints

Last updated: 2026-02-25  
Owners: PM/BA + Security Architect + Nix Module Engineer + QA/Release Engineer

Purpose: provide opinionated end-to-end `services.nixCsf` deployment patterns that can be used as production starting points.

## 1) Gateway host (NAT + forwarding + egress guardrails)

Use when a host routes traffic for internal networks.

```nix
services.nixCsf = {
  enable = true;
  threatProfile = "edge";
  coexistence.profile = "exclusive-firewall";

  nat = {
    enable = true;
    externalInterface = "eth0";
    masquerade = {
      enable = true;
      sourceIPv4 = [ "10.42.0.0/16" ];
    };
    portForwards = [
      {
        name = "web-ingress";
        protocol = "tcp";
        externalPort = 443;
        destinationAddress = "10.42.10.20";
        destinationPort = 8443;
      }
    ];
  };

  forwarding = {
    zones = {
      lan = {
        interfaces = [ "br-lan" ];
        cidrIPv4 = [ "10.42.0.0/16" ];
      };
      wan.interfaces = [ "eth0" ];
    };
    rules = [
      {
        name = "lan-to-wan-web";
        fromZone = "lan";
        toZone = "wan";
        protocol = "tcp";
        destinationPorts = [ 80 443 ];
      }
    ];
  };

  egress = {
    enable = true;
    defaultPolicy = "drop";
    trustedInterfaces = [ "wg0" ];
    allowTCPPorts = [ 53 443 ];
    allowUDPPorts = [ 53 ];
    allowIPv4 = [ "198.51.100.0/24" ];
    denyIPv4 = [ "203.0.113.0/24" ];
  };

  observability.metrics = {
    enable = true;
    outputFile = "/var/lib/nix-csf/metrics.prom";
  };
};
```

## 2) Bastion host (restricted ingress + restricted egress)

Use when only SSH administration is exposed and all outbound traffic is tightly controlled.

```nix
services.openssh = {
  enable = true;
  ports = [ 112 ];
};

services.nixCsf = {
  enable = true;
  threatProfile = "custom";
  openTCPPorts = [ 112 ];

  country.portAllow = {
    enable = true;
    countries = [ "BG" ];
    tcpPorts = [ 112 ];
  };

  egress = {
    enable = true;
    defaultPolicy = "drop";
    allowTCPPorts = [ 53 443 ];
    allowUDPPorts = [ 53 ];
    trustedInterfaces = [ "tailscale0" ];
  };
};
```

## 3) Application host (detector pack + escalation)

Use when services are public and you want Nix-native LFD behavior with automatic promotion path.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 80 443 ];

  controlPlane = {
    enable = true;
    requireAuth = true;
    authTokenFile = "/run/secrets/nix-csf-control-plane-token";
    environment = "prod";

    escalation = {
      enable = true;
      tempBanThreshold = 5;
      windowSeconds = 900;
      cooldownSeconds = 3600;
      reasonClasses = [ "lfd" "fail2ban" "conn_flood" ];
    };
  };

  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/prod/dynamic-offenders.json";
    requireHTTPS = false;
    failOpen = true;
    defaultEntryTTLSeconds = 900;
  };

  lfdDetector = {
    enable = true;
    detectorPack = {
      enable = true;
      profile = "server-web";
    };
    refreshAfterBan = true;
  };
};
```

## 4) Clustered deployment (master + worker nodes)

Use when multiple hosts must share deny/allow/ignore overlays and temporary offender state.

### 4.1 Control-plane master

```nix
services.nixCsf = {
  enable = true;
  controlPlane = {
    enable = true;
    bindAddress = "0.0.0.0";
    port = 18081;
    requireAuth = true;
    authTokenFile = "/run/secrets/nix-csf-control-plane-token";
    environment = "prod";

    propagation = {
      policyDefaultScope = "cluster";
      dynamicDefaultScope = "cluster";
      escalationPromotionScope = "cluster";
      requireNodeForLocalScope = true;
      includeProvenanceMetadata = true;
    };
  };
};
```

### 4.2 Cluster worker

```nix
services.nixCsf = {
  enable = true;
  clusterPolicy = {
    enable = true;
    url = "https://fw-master.example.org/snapshots/prod/cluster-policy.json";
    authTokenFiles = [
      "/run/secrets/nix-csf-cluster-token-current"
      "/run/secrets/nix-csf-cluster-token-next"
    ];
    nodeId = "app-eu-01";
    failOpen = false;
  };

  dynamicOffenders = {
    enable = true;
    url = "https://fw-master.example.org/snapshots/prod/dynamic-offenders.json";
    authTokenFiles = [
      "/run/secrets/nix-csf-dynamic-token-current"
      "/run/secrets/nix-csf-dynamic-token-next"
    ];
    nodeId = "app-eu-01";
    failOpen = false;
    defaultEntryTTLSeconds = 900;
  };
};
```

### 4.3 Operator mutation examples

```bash
# cluster-wide permanent deny
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf-control-plane-token policy add deny 203.0.119.9/32 --scope cluster --source secops

# node-local temporary ban (only visible to app-eu-01 snapshots)
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf-control-plane-token ban-temp 203.0.119.10/32 --ttl 900 --reason lfd:ssh_auth --scope local --node-id app-eu-01 --source lfd
```

### 4.4 TLS reverse-proxy on dedicated API port (non-443)

Use this when you want cluster API exposure on a dedicated port (for example `8448`) instead of 443.

```nix
services.nixCsf = {
  enable = true;
  openTCPPorts = [ 8448 ];

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    requireAuth = true;
    authTokenFile = "/run/secrets/nix-csf-control-plane-token";
    environment = "prod";
  };
};

services.nginx = {
  enable = true;
  virtualHosts."fw-master.example.org" = {
    useACMEHost = "fw-master.example.org";
    forceSSL = false;
    listen = [ { addr = "0.0.0.0"; port = 8448; ssl = true; } ];
    locations."/" = { proxyPass = "http://127.0.0.1:18081"; };
  };
};
```

Worker endpoint shape:

```nix
services.nixCsf.clusterPolicy.url = "https://fw-master.example.org:8448/snapshots/prod/cluster-policy.json";
services.nixCsf.dynamicOffenders.url = "https://fw-master.example.org:8448/snapshots/prod/dynamic-offenders.json";
```

Detailed ACME/internal-PKI guidance:

- `docs/CONTROL_PLANE_TLS_PROXY_POC.md`

Token generation and rotation runbook:

- `docs/CLUSTER_AUTH_TOKENS.md`

Security validation and pen-test runbook:

- `docs/SECURITY_VALIDATION_RUNBOOK.md`

## 5) Rollout checklist

1. Apply config with `nixos-rebuild switch`.
2. Verify `systemctl show -P Result nix-csf-apply.service` is `success`.
3. Run `sudo nft list table inet nix_csf` and confirm expected chains/sets.
4. Trigger `sudo systemctl start nix-csf-refresh.service`.
5. For control-plane deployments, verify:
   - `curl -sf http://127.0.0.1:18081/healthz`,
   - `nix-csfctl --output pretty health`.
6. Run operator lane validation: `./scripts/validate-capture.sh`.
