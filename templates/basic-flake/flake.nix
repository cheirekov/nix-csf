{
  description = "Example host using nix-csf";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-csf.url = "github:<org>/nix-csf";
  };

  outputs = { nixpkgs, nix-csf, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-csf.nixosModules.default
        ({ ... }: {
          services.nixCsf = {
            enable = true;
            openTCPPorts = [ 22 443 ];
            country.enable = true;
            country.countries = [ "RU" "CN" ];
          };
        })
      ];
    };
  };
}
