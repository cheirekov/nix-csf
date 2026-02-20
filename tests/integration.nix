{ pkgs, module }:
pkgs.testers.runNixOSTest {
  name = "nix-csf-integration";

  nodes.good = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-good";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      trustedInterfaces = [ "wg0" ];
      openTCPPorts = [ 22 8443 ];
      openUDPPorts = [ 51820 ];
      synRateLimit = "30/second";
      forwardPolicy = "accept";
      logDrops = true;
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  nodes.blockapplyfailclosed = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-blockapplyfailclosed";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      blocklists = {
        enable = true;
        urls = [ "file:///etc/nix-csf-missing-feed.txt" ];
        requireHTTPS = false;
        failOpen = false;
      };
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  nodes.profileedge = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-profileedge";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      threatProfile = "edge";
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  nodes.clusterexpired = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-clusterexpired";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      clusterPolicy = {
        enable = true;
        url = "file:///etc/nix-csf-cluster-policy-expired.json";
        requireHTTPS = false;
        failOpen = false;
      };
      autoRefresh.runOnBoot = false;
    };

    systemd.services.nix-csf-apply.preStart = ''
      mkdir -p /var/lib/nix-csf/cache
      install -m 0640 /etc/nix-csf-cluster-policy-expired.json /var/lib/nix-csf/cache/cluster-policy.json
      touch -d '1970-01-01 00:00:00 UTC' /var/lib/nix-csf/cache/cluster-policy.json
    '';

    environment.etc."nix-csf-cluster-policy-expired.json".text = ''
      {
        "schemaVersion": 2,
        "revision": "expired-r1",
        "ttlSeconds": 1,
        "denyIPv4": [ "198.51.100.0/24" ]
      }
    '';

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  nodes.dynamicexpired = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-dynamicexpired";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      dynamicOffenders = {
        enable = true;
        url = "file:///etc/nix-csf-dynamic-offenders-expired.json";
        requireHTTPS = false;
        failOpen = false;
      };
      autoRefresh.runOnBoot = false;
    };

    systemd.services.nix-csf-apply.preStart = ''
      mkdir -p /var/lib/nix-csf/cache
      install -m 0640 /etc/nix-csf-dynamic-offenders-expired.json /var/lib/nix-csf/cache/dynamic-offenders.json
      touch -d '1970-01-01 00:00:00 UTC' /var/lib/nix-csf/cache/dynamic-offenders.json
    '';

    environment.etc."nix-csf-dynamic-offenders-expired.json".text = ''
      {
        "schemaVersion": 1,
        "revision": "dyn-expired-r1",
        "ttlSeconds": 1,
        "banIPv4": [ "198.51.100.101/32" ]
      }
    '';

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  nodes.dockercoexist = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-dockercoexist";
    networking.firewall.enable = false;

    virtualisation.docker.enable = true;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      denyIPv4 = [ "198.51.100.0/24" ];
      forwardPolicy = "accept";
      coexistence.profile = "docker-coexist";
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables pkgs.docker pkgs.iproute2 ];
    system.stateVersion = "24.11";
  };

  nodes.tokenrotation = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-tokenrotation";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      clusterPolicy = {
        enable = true;
        url = "http://127.0.0.1:18080/cluster-policy";
        requireHTTPS = false;
        failOpen = false;
        authTokenFiles = [
          "/run/secrets/nix-csf-cluster-token-primary"
          "/run/secrets/nix-csf-cluster-token-rotated"
        ];
      };
      dynamicOffenders = {
        enable = true;
        url = "http://127.0.0.1:18080/dynamic-offenders";
        requireHTTPS = false;
        failOpen = false;
        authTokenFiles = [
          "/run/secrets/nix-csf-dynamic-token-primary"
          "/run/secrets/nix-csf-dynamic-token-rotated"
        ];
      };
      observability.metrics = {
        enable = true;
        outputFile = "/var/lib/nix-csf/metrics.prom";
      };
      autoRefresh.runOnBoot = false;
    };

    systemd.services.nix-csf-apply.preStart = ''
      mkdir -p /var/lib/nix-csf/cache /run/secrets
      install -m 0640 /etc/nix-csf-cluster-policy-token-cache.json /var/lib/nix-csf/cache/cluster-policy.json
      install -m 0640 /etc/nix-csf-dynamic-offenders-token-cache.json /var/lib/nix-csf/cache/dynamic-offenders.json
      install -m 0600 /etc/nix-csf-cluster-token-primary /run/secrets/nix-csf-cluster-token-primary
      install -m 0600 /etc/nix-csf-cluster-token-rotated /run/secrets/nix-csf-cluster-token-rotated
      install -m 0600 /etc/nix-csf-dynamic-token-primary /run/secrets/nix-csf-dynamic-token-primary
      install -m 0600 /etc/nix-csf-dynamic-token-rotated /run/secrets/nix-csf-dynamic-token-rotated
    '';

    systemd.services.nix-csf-token-fixture = {
      description = "nix-csf auth-protected fixture server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        ExecStart = "${pkgs.python3}/bin/python3 -u /etc/nix-csf-token-fixture.py";
      };
    };

    environment.etc."nix-csf-token-fixture.py".text = ''
      import json
      from http.server import BaseHTTPRequestHandler, HTTPServer

      CLUSTER_TOKEN = "cluster-rotated-token"
      DYNAMIC_TOKEN = "dynamic-rotated-token"

      CLUSTER_PAYLOAD = {
          "schemaVersion": 2,
          "revision": "auth-r2",
          "ttlSeconds": 3600,
          "denyIPv4": ["203.0.118.0/24"],
      }

      DYNAMIC_PAYLOAD = {
          "schemaVersion": 1,
          "revision": "auth-dyn-r2",
          "ttlSeconds": 3600,
          "banIPv4": ["203.0.118.7/32"],
      }

      class Handler(BaseHTTPRequestHandler):
          def do_GET(self):
              auth = self.headers.get("Authorization", "")

              if self.path == "/cluster-policy":
                  if auth != f"Bearer {CLUSTER_TOKEN}":
                      self.send_response(401)
                      self.end_headers()
                      return
                  payload = CLUSTER_PAYLOAD
              elif self.path == "/dynamic-offenders":
                  if auth != f"Bearer {DYNAMIC_TOKEN}":
                      self.send_response(401)
                      self.end_headers()
                      return
                  payload = DYNAMIC_PAYLOAD
              else:
                  self.send_response(404)
                  self.end_headers()
                  return

              body = json.dumps(payload).encode("utf-8")
              self.send_response(200)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(body)))
              self.end_headers()
              self.wfile.write(body)

          def log_message(self, _fmt, *_args):
              return

      HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
    '';

    environment.etc."nix-csf-cluster-policy-token-cache.json".text = ''
      {
        "schemaVersion": 2,
        "revision": "cache-r1",
        "ttlSeconds": 3600,
        "denyIPv4": [ "198.51.100.250/32" ]
      }
    '';
    environment.etc."nix-csf-dynamic-offenders-token-cache.json".text = ''
      {
        "schemaVersion": 1,
        "revision": "cache-dyn-r1",
        "ttlSeconds": 3600,
        "banIPv4": [ "198.51.100.251/32" ]
      }
    '';
    environment.etc."nix-csf-cluster-token-primary".text = "cluster-old-token\n";
    environment.etc."nix-csf-cluster-token-rotated".text = "cluster-rotated-token\n";
    environment.etc."nix-csf-dynamic-token-primary".text = "dynamic-old-token\n";
    environment.etc."nix-csf-dynamic-token-rotated".text = "dynamic-rotated-token\n";

    environment.systemPackages = [ pkgs.nftables pkgs.curl ];
    system.stateVersion = "24.11";
  };

  nodes.failclosed = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-failclosed";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      country = {
        enable = true;
        mode = "allow";
        countries = [ "US" ];
        ipv4URLTemplate = "file:///etc/missing-country-%s.zone";
        failOpen = false;
      };
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  testScript = ''
    start_all()
    blockapplyfailclosed, clusterexpired, dockercoexist, dynamicexpired, failclosed, good, profileedge, tokenrotation = machines

    good.wait_for_unit("multi-user.target")
    good.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    good.succeed("nft list table inet nix_csf")
    good.succeed("test -s /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'tcp flags syn ct state new limit rate over 30/second drop' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'iifname \"wg0\" accept' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'type filter hook forward priority filter; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    good.fail("test -e /var/lib/nix-csf/metrics.prom")

    profileedge.wait_for_unit("multi-user.target")
    profileedge.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    profileedge.succeed("grep -E 'tcp dport .*22' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'tcp dport .*443' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'udp dport .*53' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'udp dport .*51820' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'syn_flood_v4 { ip saddr limit rate over 25/second burst 50 packets } drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'conn_flood_v4 { ip saddr limit rate over 120/second burst 240 packets } drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'log prefix \"nix-csf drop: \" level warn' /var/lib/nix-csf/generated-ruleset.nft")

    blockapplyfailclosed.wait_for_unit("multi-user.target")
    blockapplyfailclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    blockapplyfailclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    blockapplyfailclosed.fail("nft list table inet nix_csf")
    blockapplyfailclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'blocklists.failOpen=false and no cached data is available for file:///etc/nix-csf-missing-feed.txt'")

    clusterexpired.wait_for_unit("multi-user.target")
    clusterexpired.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    clusterexpired.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    clusterexpired.fail("nft list table inet nix_csf")
    clusterexpired.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'cached cluster policy expired (ttlSeconds=1'")

    dynamicexpired.wait_for_unit("multi-user.target")
    dynamicexpired.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    dynamicexpired.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    dynamicexpired.fail("nft list table inet nix_csf")
    dynamicexpired.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'cached dynamic offenders snapshot expired (ttlSeconds=1'")

    dockercoexist.wait_for_unit("multi-user.target")
    dockercoexist.wait_for_unit("docker.service")
    dockercoexist.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    dockercoexist.succeed("grep -F 'type filter hook forward priority filter; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    dockercoexist.succeed("grep -A25 '^  chain forward {' /var/lib/nix-csf/generated-ruleset.nft | grep -F 'ip saddr @deny_ipv4 drop'")
    dockercoexist.succeed("docker info >/dev/null")
    dockercoexist.succeed("ip link show docker0")
    dockercoexist.succeed("docker network create nixcsf-itest-net >/dev/null")
    dockercoexist.succeed("docker network inspect nixcsf-itest-net >/dev/null")
    dockercoexist.succeed("docker network rm nixcsf-itest-net >/dev/null")

    tokenrotation.wait_for_unit("multi-user.target")
    tokenrotation.wait_for_unit("nix-csf-token-fixture.service")
    tokenrotation.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    tokenrotation.succeed("systemctl start nix-csf-refresh.service")
    tokenrotation.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    tokenrotation.succeed("journalctl -u nix-csf-refresh.service -n 80 | grep -F 'cluster policy auth token slot 1 failed; trying next token'")
    tokenrotation.succeed("journalctl -u nix-csf-refresh.service -n 80 | grep -F 'dynamic offenders auth token slot 1 failed; trying next token'")
    tokenrotation.succeed("grep -F '\"revision\": \"auth-r2\"' /var/lib/nix-csf/cache/cluster-policy.json")
    tokenrotation.succeed("grep -F '\"revision\": \"auth-dyn-r2\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    tokenrotation.succeed("nft list set inet nix_csf deny_ipv4 | grep -F '203.0.118.0/24'")
    tokenrotation.succeed("grep -F '203.0.118.7/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_candidates{source=\"cluster_policy\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_candidates{source=\"dynamic_offenders\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_selected_slot{source=\"cluster_policy\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_selected_slot{source=\"dynamic_offenders\"} 2' /var/lib/nix-csf/metrics.prom")

    failclosed.wait_for_unit("multi-user.target")
    failclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    failclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    failclosed.fail("nft list table inet nix_csf")
    failclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'country mode is allow, but no country data is available'")
  '';
}
