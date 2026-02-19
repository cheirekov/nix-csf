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
    failclosed, good = machines

    good.wait_for_unit("multi-user.target")
    good.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    good.succeed("nft list table inet nix_csf")
    good.succeed("test -s /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'tcp flags syn ct state new limit rate over 30/second drop' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'iifname \"wg0\" accept' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'type filter hook forward priority filter; policy accept;' /var/lib/nix-csf/generated-ruleset.nft")
    good.succeed("grep -F 'ip saddr @feed_ipv4 drop' /var/lib/nix-csf/generated-ruleset.nft")
    good.fail("test -e /var/lib/nix-csf/metrics.prom")
    good.fail("systemctl start nix-csf-refresh.service")
    good.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx exit-code")
    good.succeed("journalctl -u nix-csf-refresh.service -n 20 | grep -F 'failed to fetch file:///etc/nix-csf-missing-feed.txt'")

    failclosed.wait_for_unit("multi-user.target")
    failclosed.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx exit-code")
    failclosed.fail("test -e /var/lib/nix-csf/generated-ruleset.nft")
    failclosed.fail("nft list table inet nix_csf")
    failclosed.succeed("journalctl -u nix-csf-apply.service -n 30 | grep -F 'country mode is allow, but no country data is available'")
  '';
}
