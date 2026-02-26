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
    systemd.services.docker = {
      path = [ pkgs.nftables ];
      serviceConfig.TimeoutStartSec = "300s";
    };

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

  nodes.controlplanepoc = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-controlplanepoc";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      localFiles = {
        enable = true;
        failOnMissing = true;
        allow = [ "/etc/nix-csf-controlplanepoc-allow.local" ];
        deny = [ "/etc/nix-csf-controlplanepoc-deny.local" ];
        ignore = [ "/etc/nix-csf-controlplanepoc-ignore.local" ];
      };
      clusterPolicy = {
        enable = true;
        url = "http://127.0.0.1:18081/snapshots/lab/cluster-policy.json";
        requireHTTPS = false;
        failOpen = true;
        nodeId = "node-a";
      };
      dynamicOffenders = {
        enable = true;
        url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
        requireHTTPS = false;
        failOpen = true;
        nodeId = "node-a";
        defaultEntryTTLSeconds = 300;
      };
      controlPlane = {
        enable = true;
        bindAddress = "127.0.0.1";
        port = 18081;
        environment = "lab";
        dataDir = "/var/lib/nix-csf-control-plane";
        requireAuth = false;
        escalation = {
          enable = true;
          tempBanThreshold = 2;
          windowSeconds = 900;
          cooldownSeconds = 3600;
          reasonClasses = [ "lfd" "fail2ban" "conn_flood" ];
          maxAuditEntries = 100;
        };
      };
      lfdDetector = {
        enable = true;
        detectorPack = {
          enable = true;
          profile = "server-web";
          sshAuth = {
            threshold = 2;
            windowSeconds = 600;
            banTTLSeconds = 600;
          };
          nginxAuth = {
            threshold = 2;
            windowSeconds = 600;
            banTTLSeconds = 600;
          };
        };
        refreshAfterBan = true;
        schedule.onCalendar = "hourly";
      };
      fail2banAdapter = {
        enable = true;
        banTTLSeconds = 600;
        reasonPrefix = "fail2ban";
        refreshAfterBan = true;
        refreshAfterUnban = true;
        actionName = "nix-csf";
      };
      observability.metrics = {
        enable = true;
        outputFile = "/var/lib/nix-csf/metrics.prom";
      };
      autoRefresh.runOnBoot = false;
    };

    environment.etc."nix-csf-controlplanepoc-allow.local".text = ''
      203.0.119.50/32
    '';
    environment.etc."nix-csf-controlplanepoc-deny.local".text = ''
      203.0.119.60/32
    '';
    environment.etc."nix-csf-controlplanepoc-ignore.local".text = ''
      203.0.119.9/32
      203.0.119.60/32
    '';

    environment.systemPackages = [ pkgs.nftables pkgs.curl pkgs.jq pkgs.util-linux ];
    system.stateVersion = "24.11";
  };

  nodes.gatewaydetector = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-gatewaydetector";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 ];
      nat = {
        enable = true;
        externalInterface = "eth0";
        masquerade = {
          enable = true;
          sourceIPv4 = [ "10.88.0.0/16" ];
        };
        portForwards = [
          {
            name = "gw-web";
            protocol = "tcp";
            externalPort = 18080;
            destinationAddress = "10.88.0.10";
            destinationPort = 8080;
            sourceIPv4 = [ "198.51.100.0/24" ];
          }
        ];
      };
      forwarding = {
        zones = {
          lan = {
            interfaces = [ "br-lan" ];
            cidrIPv4 = [ "10.88.0.0/16" ];
          };
          wan = {
            interfaces = [ "eth0" ];
          };
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
        allowIPv4 = [ "198.51.100.0/24" ];
        denyIPv4 = [ "203.0.113.0/24" ];
        allowTCPPorts = [ 53 443 ];
        allowUDPPorts = [ 53 ];
      };
      clusterPolicy = {
        enable = true;
        url = "http://127.0.0.1:18081/snapshots/gw/cluster-policy.json";
        requireHTTPS = false;
        failOpen = true;
        nodeId = "gw-a";
      };
      dynamicOffenders = {
        enable = true;
        url = "http://127.0.0.1:18081/snapshots/gw/dynamic-offenders.json";
        requireHTTPS = false;
        failOpen = true;
        nodeId = "gw-a";
        defaultEntryTTLSeconds = 300;
      };
      controlPlane = {
        enable = true;
        bindAddress = "127.0.0.1";
        port = 18081;
        environment = "gw";
        requireAuth = false;
        escalation = {
          enable = true;
          tempBanThreshold = 1;
          windowSeconds = 900;
          cooldownSeconds = 0;
          reasonClasses = [ "lfd" ];
          maxAuditEntries = 100;
        };
      };
      lfdDetector = {
        enable = true;
        journalIdentifier = "sshd";
        threshold = 2;
        windowSeconds = 600;
        banTTLSeconds = 600;
        refreshAfterBan = true;
        schedule.onCalendar = "hourly";
      };
      autoRefresh.runOnBoot = false;
    };

    environment.systemPackages = [ pkgs.nftables pkgs.curl pkgs.jq ];
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
    # Start nodes lazily to reduce host-pressure boot timeouts on /dev/hvc0 and eth1.
    blockapplyfailclosed, clusterexpired, controlplanepoc, dockercoexist, dynamicexpired, failclosed, gatewaydetector, good, profileedge, tokenrotation = machines

    good.start()
    good.wait_for_unit("multi-user.target")
    good.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    good.succeed("nft list table inet nix_csf")
    good.succeed("test -s /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'tcp flags syn ct state new limit rate over 30/second drop' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'iifname \"wg0\" accept' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'type filter hook forward priority filter; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'ip protocol icmp accept' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'ip6 nexthdr ipv6-icmp accept' /var/lib/nix-csf/generated-ruleset.nft")
    good.fail("test -e /var/lib/nix-csf/metrics.prom")

    profileedge.start()
    profileedge.wait_for_unit("multi-user.target")
    profileedge.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    profileedge.succeed("grep -E 'tcp dport .*22' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'tcp dport .*443' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'udp dport .*53' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -E 'udp dport .*51820' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'syn_flood_v4 { ip saddr limit rate over 25/second burst 50 packets } drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'conn_flood_v4 { ip saddr limit rate over 120/second burst 240 packets } drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'log prefix \"nix-csf drop: \" level warn' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("awk '/^[[:space:]]*icmp type \\{/{line=$0} END { exit !(line != \"\" && line ~ /destination-unreachable/ && line ~ /time-exceeded/ && line ~ /parameter-problem/ && line ~ /limit rate 30\\/second burst 120 packets accept/) }' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("awk '/^[[:space:]]*icmpv6 type \\{/{line=$0} END { exit !(line != \"\" && line ~ /destination-unreachable/ && line ~ /packet-too-big/ && line ~ /time-exceeded/ && line ~ /parameter-problem/ && line ~ /nd-router-solicit/ && line ~ /nd-router-advert/ && line ~ /nd-neighbor-solicit/ && line ~ /nd-neighbor-advert/ && line ~ /limit rate 30\\/second burst 120 packets accept/) }' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'ip protocol icmp drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.succeed("grep -F 'ip6 nexthdr ipv6-icmp drop' /var/lib/nix-csf/generated-ruleset.nft")
    profileedge.fail("grep -F 'echo-request' /var/lib/nix-csf/generated-ruleset.nft")

    blockapplyfailclosed.start()
    blockapplyfailclosed.wait_for_unit("multi-user.target")
    blockapplyfailclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    blockapplyfailclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    blockapplyfailclosed.fail("nft list table inet nix_csf")
    blockapplyfailclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'blocklists.failOpen=false and no cached data is available for file:///etc/nix-csf-missing-feed.txt'")

    clusterexpired.start()
    clusterexpired.wait_for_unit("multi-user.target")
    clusterexpired.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    clusterexpired.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    clusterexpired.fail("nft list table inet nix_csf")
    clusterexpired.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'cached cluster policy expired (ttlSeconds=1'")

    dynamicexpired.start()
    dynamicexpired.wait_for_unit("multi-user.target")
    dynamicexpired.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    dynamicexpired.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    dynamicexpired.fail("nft list table inet nix_csf")
    dynamicexpired.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'cached dynamic offenders snapshot expired (ttlSeconds=1'")

    dockercoexist.start()
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

    tokenrotation.start()
    tokenrotation.wait_for_unit("multi-user.target")
    tokenrotation.wait_for_unit("nix-csf-token-fixture.service")
    tokenrotation.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    tokenrotation.succeed("systemctl start nix-csf-refresh.service")
    tokenrotation.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    tokenrotation.succeed("journalctl -u nix-csf-refresh.service -n 80 | grep -F 'cluster policy auth token slot 1 failed; trying next token'")
    tokenrotation.succeed("journalctl -u nix-csf-refresh.service -n 80 | grep -F 'dynamic offenders auth token slot 1 failed; trying next token'")
    tokenrotation.succeed("grep -F '\"revision\": \"auth-r2\"' /var/lib/nix-csf/cache/cluster-policy.json")
    tokenrotation.succeed("grep -F '\"revision\": \"auth-dyn-r2\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    tokenrotation.succeed("nft get element inet nix_csf deny_ipv4 '{ 203.0.118.9 }'")
    tokenrotation.succeed("grep -F '203.0.118.7/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_candidates{source=\"cluster_policy\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_candidates{source=\"dynamic_offenders\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_selected_slot{source=\"cluster_policy\"} 2' /var/lib/nix-csf/metrics.prom")
    tokenrotation.succeed("grep -F 'nix_csf_auth_token_selected_slot{source=\"dynamic_offenders\"} 2' /var/lib/nix-csf/metrics.prom")

    controlplanepoc.start()
    controlplanepoc.wait_for_unit("multi-user.target")
    controlplanepoc.wait_for_unit("nix-csf-control-plane.service")
    controlplanepoc.wait_until_succeeds("systemctl is-active --quiet nix-csf-control-plane.service")
    controlplanepoc.wait_until_succeeds("curl -sf http://127.0.0.1:18081/healthz >/dev/null")
    controlplanepoc.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    controlplanepoc.succeed("command -v nix-csfctl >/dev/null")
    controlplanepoc.succeed("nix-csfctl --output pretty health | jq -e '.status == \"ok\"'")
    controlplanepoc.succeed("nix-csfctl --output pretty policy add deny 203.0.119.9/32 | jq -e '.changed == true'")
    controlplanepoc.succeed("nix-csfctl --output pretty policy add deny 203.0.119.140/32 --scope local --node-id node-a --source lfd | jq -e '.changed == true and .scope == \"local\" and .originNode == \"node-a\"'")
    controlplanepoc.succeed("nix-csfctl --output pretty policy add deny 203.0.119.141/32 --scope local --node-id node-b --source lfd | jq -e '.changed == true and .scope == \"local\" and .originNode == \"node-b\"'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.10/32 --ttl 600 --reason syn_flood | jq -e '.changed == true'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.142/32 --ttl 600 --reason lfd:ssh_auth --scope local --node-id node-a --source lfd | jq -e '.changed == true and .scope == \"local\" and .originNode == \"node-a\"'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.143/32 --ttl 600 --reason lfd:ssh_auth --scope local --node-id node-b --source lfd | jq -e '.changed == true and .scope == \"local\" and .originNode == \"node-b\"'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.11/32 --ttl 600 --reason conn_flood | jq -e '.escalation.enabled == true and .escalation.reasonClass == \"conn_flood\" and .escalation.reasonClassEligible == true and .escalation.escalated == false'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.11/32 --ttl 600 --reason conn_flood | jq -e '.escalation.escalated == true and .escalation.promotionChanged == true and .escalation.cooldownSeconds == 3600'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.122/32 --ttl 600 --reason conn_flood | jq -e '.escalation.escalated == false'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.122/32 --ttl 600 --reason conn_flood | jq -e '.escalation.escalated == true and .escalation.promotionChanged == true'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.122/32 --ttl 600 --reason conn_flood | jq -e '.escalation.escalated == false and .escalation.cooldownActive == true and .escalation.eventCountWindow == 1'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.122/32 --ttl 600 --reason conn_flood | jq -e '.escalation.escalated == false and .escalation.cooldownActive == true and .escalation.eventCountWindow == 2 and .escalation.promotionChanged == false'")
    controlplanepoc.succeed("nix-csfctl --output pretty promotions --limit 20 | jq -e '[.promotions[] | select(.cidr == \"203.0.119.122/32\")] | length == 1'")
    controlplanepoc.succeed("nix-csfctl --output pretty unban 203.0.119.122/32 | jq -e '.changed == true'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.123/32 --ttl 600 --reason syn_flood | jq -e '.escalation.reasonClass == \"syn_flood\" and .escalation.reasonClassEligible == false and .escalation.escalated == false and .escalation.promotionChanged == false'")
    controlplanepoc.succeed("nix-csfctl --output pretty ban-temp 203.0.119.123/32 --ttl 600 --reason syn_flood | jq -e '.escalation.reasonClassEligible == false and .escalation.eventCountWindow == 0'")
    controlplanepoc.succeed("nix-csfctl --output pretty promotions --limit 20 | jq -e '.escalation.cooldownSeconds == 3600 and (.escalation.reasonClasses | index(\"conn_flood\") != null)'")
    controlplanepoc.succeed("nix-csfctl --output pretty promotions --limit 20 | jq -e '.promotions | map(.cidr) | index(\"203.0.119.11/32\") != null'")
    controlplanepoc.succeed("nix-csfctl --output pretty promotions --limit 20 | jq -e '([.promotions[] | select(.cidr == \"203.0.119.11/32\")][0].reasonClass == \"conn_flood\") and ([.promotions[] | select(.cidr == \"203.0.119.11/32\")][0].cooldownSeconds == 3600) and ([.promotions[] | select(.cidr == \"203.0.119.11/32\")][0].id >= 1)'")
    controlplanepoc.succeed("nix-csfctl --output pretty promotions --limit 20 | jq -e '[.promotions[] | select(.cidr == \"203.0.119.123/32\")] | length == 0'")
    controlplanepoc.succeed("logger -t sshd 'Failed password for invalid user root from 203.0.119.120 port 50001 ssh2'")
    controlplanepoc.succeed("logger -t sshd 'Failed password for invalid user root from 203.0.119.120 port 50002 ssh2'")
    controlplanepoc.succeed("logger -t nginx 'user \"bob\": password mismatch, client: 203.0.119.121, server: example.com, request: \"GET /admin HTTP/1.1\", host: \"example.com\"'")
    controlplanepoc.succeed("logger -t nginx 'user \"bob\": password mismatch, client: 203.0.119.121, server: example.com, request: \"GET /admin HTTP/1.1\", host: \"example.com\"'")
    controlplanepoc.succeed("systemctl start nix-csf-lfd-detector.service")
    controlplanepoc.succeed("systemctl show -P Result nix-csf-lfd-detector.service | grep -qx success")
    controlplanepoc.succeed("journalctl -u nix-csf-lfd-detector.service -n 120 | grep -F 'detector=ssh-auth ip=203.0.119.120'")
    controlplanepoc.succeed("journalctl -u nix-csf-lfd-detector.service -n 120 | grep -F 'detector=nginx-auth ip=203.0.119.121'")
    controlplanepoc.succeed("grep -F 'nix_csf_lfd_detector_detectors_enabled 2' /var/lib/nix-csf/lfd-detector.prom")
    controlplanepoc.succeed("grep -F 'nix_csf_lfd_detector_candidate_ips 2' /var/lib/nix-csf/lfd-detector.prom")
    controlplanepoc.succeed("grep -F 'nix_csf_lfd_detector_candidate_ips_by_detector{detector=\"ssh-auth\"} 1' /var/lib/nix-csf/lfd-detector.prom")
    controlplanepoc.succeed("grep -F 'nix_csf_lfd_detector_candidate_ips_by_detector{detector=\"nginx-auth\"} 1' /var/lib/nix-csf/lfd-detector.prom")
    controlplanepoc.succeed("test -s /etc/fail2ban/action.d/nix-csf.local")
    controlplanepoc.succeed("nix-csf-fail2ban-action ban --ip 203.0.119.130 --jail sshd --endpoint http://127.0.0.1:18081 --ban-ttl-seconds 600 --reason-prefix fail2ban --refresh-after-ban")
    controlplanepoc.wait_until_succeeds("grep -F '\"cidr\": \"203.0.119.130/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.wait_until_succeeds("grep -F '203.0.119.130/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("nix-csf-fail2ban-action unban --ip 203.0.119.130 --jail sshd --endpoint http://127.0.0.1:18081 --ban-ttl-seconds 600 --reason-prefix fail2ban --refresh-after-unban")
    controlplanepoc.wait_until_succeeds("! grep -F '\"cidr\": \"203.0.119.130/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.wait_until_succeeds("! grep -F '203.0.119.130/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("systemctl start nix-csf-refresh.service")
    controlplanepoc.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    controlplanepoc.succeed("grep -F '\"203.0.119.9/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("grep -F '\"203.0.119.140/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.fail("grep -F '\"203.0.119.141/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("jq -e '[.denyIPv4Meta[]? | select(.cidr == \"203.0.119.140/32\" and .scope == \"local\" and .originNode == \"node-a\" and .source == \"lfd\" and (.mutationId > 0))] | length == 1' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("jq -e '.lastMutationId | type == \"number\" and . > 0' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("grep -F '\"203.0.119.11/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("grep -F '\"203.0.119.122/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.fail("grep -F '\"203.0.119.123/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    controlplanepoc.succeed("grep -F '\"cidr\": \"203.0.119.10/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("grep -F '\"cidr\": \"203.0.119.142/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.fail("grep -F '\"cidr\": \"203.0.119.143/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("jq -e '[.banIPv4[]? | select(.cidr == \"203.0.119.142/32\" and .scope == \"local\" and .originNode == \"node-a\" and .source == \"lfd\" and (.mutationId > 0))] | length == 1' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("jq -e '.lastMutationId | type == \"number\" and . > 0' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("curl -sf -H 'X-Nix-Csf-Node: node-b' http://127.0.0.1:18081/snapshots/lab/cluster-policy.json | jq -e '(.denyIPv4 | index(\"203.0.119.141/32\") != null) and (.denyIPv4 | index(\"203.0.119.140/32\") == null)'")
    controlplanepoc.succeed("curl -sf -H 'X-Nix-Csf-Node: node-b' http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json | jq -e '([.banIPv4[]?.cidr] | index(\"203.0.119.143/32\") != null) and ([.banIPv4[]?.cidr] | index(\"203.0.119.142/32\") == null)'")
    controlplanepoc.succeed("grep -F '\"cidr\": \"203.0.119.120/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("grep -F '\"cidr\": \"203.0.119.121/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.succeed("grep -F '\"cidr\": \"203.0.119.123/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.fail("grep -F '\"cidr\": \"203.0.119.122/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.fail("grep -F '\"cidr\": \"203.0.119.11/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    controlplanepoc.fail("nft get element inet nix_csf deny_ipv4 '{ 203.0.119.9 }'")
    controlplanepoc.succeed("nft get element inet nix_csf deny_ipv4 '{ 203.0.119.11 }'")
    controlplanepoc.fail("nft get element inet nix_csf deny_ipv4 '{ 203.0.119.60 }'")
    controlplanepoc.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.119.9 }'")
    controlplanepoc.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.119.50 }'")
    controlplanepoc.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.119.60 }'")
    controlplanepoc.succeed("grep -E '203\\.0\\.119\\.9(/32)?' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("grep -E '203\\.0\\.119\\.11(/32)?' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("grep -F '203.0.119.10/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("grep -F '203.0.119.120/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    controlplanepoc.succeed("grep -F '203.0.119.121/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")

    gatewaydetector.start()
    gatewaydetector.wait_for_unit("multi-user.target")
    gatewaydetector.wait_for_unit("nix-csf-control-plane.service")
    gatewaydetector.wait_until_succeeds("systemctl is-active --quiet nix-csf-control-plane.service")
    gatewaydetector.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    gatewaydetector.succeed("nft list table ip nix_csf_nat")
    gatewaydetector.succeed("grep -F 'type nat hook prerouting priority dstnat; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    gatewaydetector.succeed("grep -F 'ip saddr 10.88.0.0/16 oifname \"eth0\" masquerade' /var/lib/nix-csf/generated-ruleset.nft")
    gatewaydetector.succeed("awk '/iifname \"br-lan\"/ && /oifname \"eth0\"/ && /tcp/ && /dport/ && /80/ && /443/ && /ip saddr 10.88.0.0\\/16/ && /accept/ { found = 1 } END { exit !found }' /var/lib/nix-csf/generated-ruleset.nft")
    gatewaydetector.succeed("grep -F 'type filter hook output priority filter; policy drop;' /var/lib/nix-csf/generated-ruleset.nft")
    gatewaydetector.succeed("logger -t sshd 'Failed password for invalid user root from 203.0.119.150 port 50001 ssh2'")
    gatewaydetector.succeed("logger -t sshd 'Failed password for invalid user root from 203.0.119.150 port 50002 ssh2'")
    gatewaydetector.succeed("systemctl start nix-csf-lfd-detector.service")
    gatewaydetector.succeed("systemctl show -P Result nix-csf-lfd-detector.service | grep -qx success")
    gatewaydetector.succeed("journalctl -u nix-csf-lfd-detector.service -n 80 | grep -F 'detector=legacy-sshd ip=203.0.119.150'")
    gatewaydetector.succeed("systemctl start nix-csf-refresh.service")
    gatewaydetector.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    gatewaydetector.succeed("grep -F '\"203.0.119.150/32\"' /var/lib/nix-csf/cache/cluster-policy.json")
    gatewaydetector.fail("grep -F '\"cidr\": \"203.0.119.150/32\"' /var/lib/nix-csf/cache/dynamic-offenders.json")
    gatewaydetector.succeed("nft get element inet nix_csf deny_ipv4 '{ 203.0.119.150 }'")

    failclosed.start()
    failclosed.wait_for_unit("multi-user.target")
    failclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    failclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    failclosed.fail("nft list table inet nix_csf")
    failclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'country mode is allow, but no country data is available'")
  '';
}
