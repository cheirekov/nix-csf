{ ... }:
{
  imports = [
    /path/to/nix-csf
  ];

  services.nixCsf = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    openTCPPorts = [ 22 443 ];
    openUDPPorts = [ 53 ];
    country.enable = true;
    country.countries = [ "RU" "CN" ];
  };
}
