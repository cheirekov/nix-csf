{ pkgs, module }:
pkgs.testers.runNixOSTest {
  name = "nix-csf-smoke";

  nodes.machine = { ... }: {
    imports = [ module ];

    networking.hostName = "nix-csf-smoke";
    networking.firewall.enable = false;

    services.nixCsf = {
      enable = true;
      openTCPPorts = [ 22 443 ];
      openUDPPorts = [ 53 ];
      allowIPv4 = [ "10.0.0.0/8" "203.0.116.9/32" ];
      denyIPv4 = [ "198.51.100.0/24" ];
      logDrops = true;
      rateLimits = {
        synFlood = {
          enable = true;
          preset = "strict";
        };
        connFlood = {
          enable = true;
          preset = "balanced";
        };
      };
      country = {
        enable = true;
        mode = "allow";
        countries = [ "US" ];
        # Keep smoke test deterministic even if remote country feed is unavailable.
        extraIPv4 = [ "10.0.0.0/8" ];
        failOpen = true;
        portDeny = {
          enable = true;
          countries = [ "US" ];
          tcpPorts = [ 443 ];
          # Keep portDeny deterministic even if remote country feed is unavailable.
          extraIPv4 = [ "10.0.0.0/8" ];
        };
      };
      blocklists = {
        enable = true;
        sources = [ "smoke-local-v4" ];
        requireHTTPS = false;
        catalog = {
          "smoke-local-v4" = {
            url = "file:///etc/nix-csf-smoke-feed.txt";
            family = "ipv4";
            format = "cidr-text";
            description = "Deterministic local smoke feed.";
          };
        };
      };
      clusterPolicy = {
        enable = true;
        url = "file:///etc/nix-csf-cluster-policy.json";
        requireHTTPS = false;
        failOpen = false;
        nodeId = "smoke-node";
      };
      dynamicOffenders = {
        enable = true;
        url = "file:///etc/nix-csf-dynamic-offenders.json";
        requireHTTPS = false;
        failOpen = false;
        defaultEntryTTLSeconds = 1200;
      };
      observability.metrics = {
        enable = true;
        outputFile = "/var/lib/nix-csf/metrics.prom";
      };
      # Keep metrics assertions deterministic: explicit refresh is triggered in testScript.
      autoRefresh.runOnBoot = false;
    };

    # Strict clusterPolicy mode requires cache presence at apply-time.
    # Seed cache from deterministic local fixture so boot apply succeeds.
    systemd.services.nix-csf-apply.preStart = ''
      mkdir -p /var/lib/nix-csf/cache
      install -m 0640 /etc/nix-csf-cluster-policy.json /var/lib/nix-csf/cache/cluster-policy.json
      install -m 0640 /etc/nix-csf-dynamic-offenders.json /var/lib/nix-csf/cache/dynamic-offenders.json
    '';

    environment.etc."nix-csf-smoke-feed.txt".text = ''
      203.0.113.0/24
    '';
    environment.etc."nix-csf-cluster-policy.json".text = ''
      {
        "schemaVersion": 2,
        "revision": "smoke-r1",
        "ttlSeconds": 3600,
        "allowIPv4": [ "172.20.0.0/16" ],
        "denyIPv4": [ "203.0.114.0/24", "203.0.115.0/24" ],
        "ignoreIPv4": [ "203.0.115.0/24" ]
      }
    '';
    environment.etc."nix-csf-dynamic-offenders.json".text = ''
      {
        "schemaVersion": 1,
        "revision": "smoke-dyn-r1",
        "ttlSeconds": 3600,
        "banIPv4": [
          "203.0.116.8/32",
          { "cidr": "203.0.116.9/32", "ttlSeconds": 600 },
          { "cidr": "203.0.116.10/32", "expiresAt": 1 }
        ]
      }
    '';
    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    machine.succeed("nft list table inet nix_csf")
    machine.succeed("nft list table inet nix_csf | grep -F 'ip saddr != @country_ipv4 drop'")
    machine.succeed("nft list table inet nix_csf | grep -E 'ip saddr @country_port_deny_ipv4.*tcp dport'")
    machine.succeed("nft list table inet nix_csf | grep -F 'syn_flood_v4'")
    machine.succeed("nft list table inet nix_csf | grep -F 'conn_flood_v4'")
    machine.succeed("nft list table inet nix_csf | grep -F 'ip saddr @feed_ipv4 drop'")
    machine.succeed("grep -F 'set dynamic_ban_ipv4 {' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F '203.0.116.8/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F '203.0.116.9/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    machine.fail("grep -F '203.0.116.10/32 timeout' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("awk '/ip saddr @allow_ipv4 accept/{allow=NR} /ip saddr @dynamic_ban_ipv4 drop/{dyn=NR} END { exit !(allow > 0 && dyn > 0 && allow < dyn) }' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("test -s /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_last_run_success{mode=\"apply\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_build_info{version=\"' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"blocklists\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"dynamic_offenders\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"dynamic_ban_ipv4\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"dynamic_offender_urls\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_dynamic_snapshot_schema_version 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_dynamic_snapshot_cache_expired 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("systemctl start nix-csf-refresh.service")
    machine.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    machine.succeed("nft list table inet nix_csf | grep -F '203.0.113.0/24'")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_last_run_success{mode=\"refresh\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("nft list set inet nix_csf deny_ipv4 | grep -F '203.0.114.0/24'")
    machine.fail("nft list set inet nix_csf deny_ipv4 | grep -F '203.0.115.0/24'")
    machine.succeed("nft list set inet nix_csf allow_ipv4 | grep -F '203.0.115.0/24'")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"cluster_policy\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"cluster_deny_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"cluster_ignore_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"cluster_policy_urls\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_cluster_policy_schema_version 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_cluster_policy_cache_expired 0' /var/lib/nix-csf/metrics.prom")
  '';
}
