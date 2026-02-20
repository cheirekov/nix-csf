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
    blockapplyfailclosed, clusterexpired, failclosed, good, profileedge = machines

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

    failclosed.wait_for_unit("multi-user.target")
    failclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    failclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    failclosed.fail("nft list table inet nix_csf")
    failclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'country mode is allow, but no country data is available'")
  '';
}
