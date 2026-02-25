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
      nat = {
        enable = true;
        externalInterface = "eth0";
        masquerade = {
          enable = true;
          sourceIPv4 = [ "10.42.0.0/16" ];
        };
        portForwards = [
          {
            name = "smoke-web";
            protocol = "tcp";
            externalPort = 8080;
            destinationAddress = "10.42.0.10";
            destinationPort = 80;
            sourceIPv4 = [ "198.51.100.0/24" ];
          }
          {
            name = "smoke-dns";
            protocol = "udp";
            externalPort = 5353;
            destinationAddress = "10.42.0.53";
          }
        ];
      };
      forwarding = {
        zones = {
          lan = {
            interfaces = [ "br-lan" ];
            cidrIPv4 = [ "10.42.0.0/16" ];
          };
          wan = {
            interfaces = [ "eth0" ];
          };
          dmz = {
            interfaces = [ "br-dmz" ];
            cidrIPv4 = [ "10.43.0.0/16" ];
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
          {
            name = "wan-to-dmz-admin";
            fromZone = "wan";
            toZone = "dmz";
            protocol = "tcp";
            destinationPorts = [ 8443 ];
            sourceIPv4 = [ "198.51.100.0/24" ];
            destinationIPv4 = [ "10.43.0.10/32" ];
          }
        ];
      };
      egress = {
        enable = true;
        defaultPolicy = "drop";
        trustedInterfaces = [ "wg0" ];
        allowIPv4 = [ "198.51.100.0/24" ];
        allowIPv6 = [ "2001:db8::/32" ];
        denyIPv4 = [ "203.0.113.0/24" ];
        denyIPv6 = [ "2001:db8:dead::/48" ];
        allowTCPPorts = [ 53 443 ];
        allowUDPPorts = [ 53 ];
      };
      allowIPv4 = [ "10.0.0.0/8" "203.0.116.9/32" ];
      denyIPv4 = [ "198.51.100.0/24" ];
      localFiles = {
        enable = true;
        failOnMissing = true;
        allow = [ "/etc/nix-csf-local-allow.txt" ];
        deny = [ "/etc/nix-csf-local-deny.txt" ];
        ignore = [ "/etc/nix-csf-local-ignore.txt" ];
      };
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
        ipv4URLTemplate = "file:///etc/nix-csf-country-%s.zone";
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
        portAllow = {
          enable = true;
          countries = [ "US" ];
          tcpPorts = [ 22 ];
          udpPorts = [ 53 ];
          # Keep portAllow deterministic even if remote country feed is unavailable.
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
      ; deterministic local fixture
      203.0.113.0/24 ; smoke-feed
      add smoke_feed 203.0.118.10/32 timeout 3600
    '';
    environment.etc."nix-csf-country-us.zone".text = ''
      # deterministic local country fixture
      203.0.117.0/24 ; smoke-country-us
    '';
    environment.etc."nix-csf-local-allow.txt".text = ''
      203.0.120.1/32
      203.0.120.1/32
      tcp|in|d=12000|s=203.0.120.2/32
    '';
    environment.etc."nix-csf-local-deny.txt".text = ''
      203.0.120.0/24
    '';
    environment.etc."nix-csf-local-ignore.txt".text = ''
      203.0.114.0/24
      203.0.120.0/24
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
    machine.succeed("nft list table ip nix_csf_nat")
    machine.succeed("nft list table inet nix_csf | grep -F 'ip saddr != @country_ipv4 drop'")
    machine.succeed("grep -F 'type nat hook prerouting priority dstnat; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip saddr 198.51.100.0/24 iifname \"eth0\" tcp dport 8080 dnat to 10.42.0.10:80' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'iifname \"eth0\" udp dport 5353 dnat to 10.42.0.53:5353' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip saddr 10.42.0.0/16 oifname \"eth0\" masquerade' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip saddr 10.42.0.0/16 oifname \"eth0\" accept' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip saddr 198.51.100.0/24 iifname \"eth0\" ip daddr 10.42.0.10 tcp dport 80 accept' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("awk '/iifname \"br-lan\"/ && /oifname \"eth0\"/ && /tcp/ && /dport/ && /80/ && /443/ && /ip saddr 10.42.0.0\\/16/ && /accept/ { found = 1 } END { exit !found }' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("awk '/iifname \"eth0\"/ && /oifname \"br-dmz\"/ && /tcp/ && /dport 8443/ && /ip saddr 198.51.100.0\\/24/ && /ip daddr/ && /10.43.0.0\\/16/ && /10.43.0.10\\/32/ && /accept/ { found = 1 } END { exit !found }' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("nft list table inet nix_csf | grep -E 'ip saddr @country_port_deny_ipv4.*tcp dport'")
    machine.succeed("nft list table inet nix_csf | grep -E 'ip saddr != @country_port_allow_ipv4.*tcp dport'")
    machine.succeed("nft list table inet nix_csf | grep -E 'ip saddr != @country_port_allow_ipv4.*udp dport'")
    machine.succeed("grep -F 'type filter hook output priority filter; policy drop;' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'oifname \"wg0\" accept' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip daddr @egress_deny_ipv4 drop' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'ip daddr @egress_allow_ipv4 accept' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("awk '/tcp dport \\{/{ if ($0 ~ /53/ && $0 ~ /443/ && $0 ~ /accept/) found=1 } END { exit !found }' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("grep -F 'udp dport { 53 } accept' /var/lib/nix-csf/generated-ruleset.nft")
    machine.succeed("nft list table inet nix_csf | grep -F 'syn_flood_v4'")
    machine.succeed("nft list table inet nix_csf | grep -F 'conn_flood_v4'")
    machine.succeed("nft list table inet nix_csf | grep -F 'ip saddr @feed_ipv4 drop'")
    machine.succeed("grep -F 'ip saddr 203.0.120.2/32 tcp dport 12000 accept' /var/lib/nix-csf/generated-ruleset.nft")
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
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"nat\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"nat_masquerade\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"nat_port_forward\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"forwarding_matrix\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"egress\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"local_files\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"local_allow_port_rules\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"country_port_allow\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"icmp_rate_limit\"} 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_icmp_profile{profile=\"legacy\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_egress_policy{policy=\"drop\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"dynamic_ban_ipv4\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"egress_allow_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"egress_allow_ipv6\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"egress_deny_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"egress_deny_ipv6\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"local_allow_port_rules\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_local_list_duplicates{role=\"allow\",family=\"ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_local_list_overlaps{pair=\"deny_ignore\",family=\"ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"dynamic_offender_urls\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"nat_masquerade_sources\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"nat_port_forwards\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"forwarding_zones\"} 3' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"forwarding_rules\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"forwarding_rules_expanded\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"egress_trusted_interfaces\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"egress_allow_tcp_ports\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"egress_allow_udp_ports\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_dynamic_snapshot_schema_version 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_dynamic_snapshot_cache_expired 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("awk -F '\\t' '$1 == \"duplicate\" && $2 == \"ipv4\" && $3 == \"allow\" && $4 == \"1\" { found = 1 } END { exit !found }' /var/lib/nix-csf/local-list-audit-summary.tsv")
    machine.succeed("awk -F '\\t' '$1 == \"overlap\" && $2 == \"ipv4\" && $3 == \"deny_ignore\" && $4 == \"1\" { found = 1 } END { exit !found }' /var/lib/nix-csf/local-list-audit-summary.tsv")
    machine.succeed("awk -F '\\t' '$1 == \"ipv4\" && $2 == \"203.0.120.0/24\" && $3 == \"deny_ignore\" && $4 == \"ignore_removes_deny\" { found = 1 } END { exit !found }' /var/lib/nix-csf/local-list-conflicts.tsv")
    machine.succeed("systemctl start nix-csf-refresh.service")
    machine.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    machine.succeed("nft list table inet nix_csf | grep -F '203.0.113.0/24'")
    machine.succeed("nft list set inet nix_csf feed_ipv4 | grep -E '203\\.0\\.118\\.10(/32)?'")
    machine.succeed("nft list set inet nix_csf country_ipv4 | grep -F '203.0.117.0/24'")
    machine.succeed("nft list set inet nix_csf country_port_allow_ipv4 | grep -F '203.0.117.0/24'")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"country_port_allow_ipv4\"} 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"local_allow_files\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"local_deny_files\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"local_ignore_files\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"effective_ignore_ipv4\"} 3' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_last_run_success{mode=\"refresh\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.fail("nft get element inet nix_csf deny_ipv4 '{ 203.0.114.1 }'")
    machine.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.114.1 }'")
    machine.fail("nft get element inet nix_csf deny_ipv4 '{ 203.0.115.1 }'")
    machine.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.115.1 }'")
    machine.fail("nft get element inet nix_csf deny_ipv4 '{ 203.0.120.1 }'")
    machine.succeed("nft get element inet nix_csf allow_ipv4 '{ 203.0.120.1 }'")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"cluster_policy\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"cluster_deny_ipv4\"} 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"cluster_ignore_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_source_count{source=\"cluster_policy_urls\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_cluster_policy_schema_version 2' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_cluster_policy_cache_expired 0' /var/lib/nix-csf/metrics.prom")
  '';
}
