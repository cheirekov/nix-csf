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
      allowIPv4 = [ "10.0.0.0/8" ];
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
      observability.metrics = {
        enable = true;
        outputFile = "/var/lib/nix-csf/metrics.prom";
      };
      # Keep metrics assertions deterministic: explicit refresh is triggered in testScript.
      autoRefresh.runOnBoot = false;
    };

    environment.etc."nix-csf-smoke-feed.txt".text = ''
      203.0.113.0/24
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
    machine.succeed("test -s /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_last_run_success{mode=\"apply\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_build_info{version=\"' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_feature_enabled{feature=\"blocklists\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 0' /var/lib/nix-csf/metrics.prom")
    machine.succeed("systemctl start nix-csf-refresh.service")
    machine.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
    machine.succeed("nft list table inet nix_csf | grep -F '203.0.113.0/24'")
    machine.succeed("grep -F 'nix_csf_set_entries{set=\"feed_ipv4\"} 1' /var/lib/nix-csf/metrics.prom")
    machine.succeed("grep -F 'nix_csf_last_run_success{mode=\"refresh\"} 1' /var/lib/nix-csf/metrics.prom")
  '';
}
