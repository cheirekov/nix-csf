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
    };

    environment.systemPackages = [ pkgs.nftables ];
    system.stateVersion = "24.11";
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl show -P Result nix-csf-apply.service | grep -qx success")
    machine.succeed("nft list table inet nix_csf")
    machine.succeed("systemctl start nix-csf-refresh.service")
    machine.succeed("systemctl show -P Result nix-csf-refresh.service | grep -qx success")
  '';
}
