# Control-Plane TLS Reverse-Proxy POC (Dedicated Port)

Last updated: 2026-02-26  
Owners: Security Architect + Nix Module Engineer + QA/Release Engineer

## Goal

Expose the `nix-csf` control-plane API securely on a dedicated node/API port (not 80/443) while keeping:

- `nix-csf-control-plane` bound to localhost,
- TLS and access-control at reverse proxy,
- token-based API auth enabled.

## Team decision

For production:

1. Keep control-plane service local-only (`127.0.0.1:18081`).
2. Publish external API through reverse proxy TLS.
3. Use a dedicated API port (example: `8448`) if you do not want 443.
4. Keep `controlPlane.requireAuth = true`.

## ACME notes for non-80/443 API ports

- You can still run API on `8448` (or any chosen port).
- Certificate issuance method matters:
  - HTTP-01/TLS-ALPN-01 challenges typically need 80/443 reachability.
  - DNS-01 challenge is preferred when the API itself is not on 80/443.

If public ACME is not feasible for your topology, use internal PKI (step-ca/Vault/corporate CA).

## POC: main node (reverse proxy on 8448)

```nix
{ config, pkgs, ... }:
{
  services.nixCsf = {
    enable = true;

    # Expose only reverse-proxy port, not the raw control-plane port.
    openTCPPorts = [ 8448 ];

    controlPlane = {
      enable = true;
      bindAddress = "127.0.0.1";
      port = 18081;
      environment = "prod";
      requireAuth = true;
      authTokenFile = "/run/secrets/nix-csf-control-plane-token";
    };
  };

  # ACME account + cert (DNS-01 style shown as placeholder).
  security.acme = {
    acceptTerms = true;
    defaults.email = "secops@example.org";

    certs."fw-main.example.org" = {
      # Example for DNS challenge integrations; adapt provider and credentials.
      dnsProvider = "rfc2136";
      credentialsFile = "/run/secrets/acme-dns.env";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."fw-main.example.org" = {
      useACMEHost = "fw-main.example.org";
      forceSSL = false;

      # Dedicated API port (not 443).
      listen = [
        {
          addr = "0.0.0.0";
          port = 8448;
          ssl = true;
        }
      ];

      # Optional network ACL at proxy layer.
      extraConfig = ''
        allow 198.51.100.0/24;
        allow 203.0.113.0/24;
        deny all;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:18081";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_http_version 1.1;
        '';
      };
    };
  };
}
```

## POC: backup worker node (snapshot pull over 8448)

```nix
{
  services.nixCsf = {
    enable = true;

    clusterPolicy = {
      enable = true;
      url = "https://fw-main.example.org:8448/snapshots/prod/cluster-policy.json";
      requireHTTPS = true;
      failOpen = true;
      authTokenFiles = [
        "/run/secrets/nix-csf-cluster-token-current"
        "/run/secrets/nix-csf-cluster-token-next"
      ];
      nodeId = "dns-backup-01";
    };

    dynamicOffenders = {
      enable = true;
      url = "https://fw-main.example.org:8448/snapshots/prod/dynamic-offenders.json";
      requireHTTPS = true;
      failOpen = true;
      authTokenFiles = [
        "/run/secrets/nix-csf-dynamic-token-current"
        "/run/secrets/nix-csf-dynamic-token-next"
      ];
      nodeId = "dns-backup-01";
    };
  };
}
```

## Operator checks

On main:

```bash
sudo systemctl status nix-csf-control-plane.service --no-pager
sudo systemctl status nginx.service --no-pager
curl -skf https://fw-main.example.org:8448/healthz | jq .
```

On backup:

```bash
sudo systemctl start nix-csf-refresh.service
sudo systemctl show -P Result nix-csf-refresh.service
sudo grep -F 'cluster_policy_meta' /var/log/journal/*/* 2>/dev/null || true
```

## Security checklist

1. `controlPlane.bindAddress = "127.0.0.1"` on exposed nodes.
2. `controlPlane.requireAuth = true` with `0600` token file.
3. Reverse proxy ACL limits who can reach API port.
4. `clusterPolicy.requireHTTPS = true` and `dynamicOffenders.requireHTTPS = true`.
5. Use `authTokenFiles` for rotation overlap.
6. Keep unique `nodeId` per cluster node.
