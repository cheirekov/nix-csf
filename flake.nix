{
  description = "nix-csf: CSF-inspired NixOS firewall module (flake + non-flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, ... }: {
    nixosModules = {
      default = import ./modules/nixos/nix-csf.nix;
      nix-csf = import ./modules/nixos/nix-csf.nix;
    };

    templates.default = {
      path = ./templates/basic-flake;
      description = "Basic flake wiring for nix-csf";
    };
  };
}
