{
  description = "nix-csf: CSF-inspired NixOS firewall module (flake + non-flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      nixCsfModule = import ./modules/nixos/nix-csf.nix;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        }) systems);
    in
    {
      nixosModules = {
        default = nixCsfModule;
        nix-csf = nixCsfModule;
      };

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          systemEval = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              nixCsfModule
              ({ ... }: {
                services.nixCsf.enable = true;
                networking.firewall.enable = false;
                system.stateVersion = "24.11";
              })
            ];
          };
        in
        {
          eval-basic = pkgs.runCommand "nix-csf-eval-basic" {
            serviceExec = systemEval.config.systemd.services.nix-csf-apply.serviceConfig.ExecStart;
          } ''
            test -n "$serviceExec"
            printf '%s\n' "$serviceExec" > "$out"
          '';
          shellcheck = pkgs.runCommand "nix-csf-shellcheck" {
            nativeBuildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck ${./scripts/nix-csf-apply.sh}
            touch "$out"
          '';
        }
      ) // {
        x86_64-linux.nix-csf-smoke = import ./tests/smoke.nix {
          pkgs = import nixpkgs { system = "x86_64-linux"; };
          module = nixCsfModule;
        };
        x86_64-linux.nix-csf-integration = import ./tests/integration.nix {
          pkgs = import nixpkgs { system = "x86_64-linux"; };
          module = nixCsfModule;
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          validate = pkgs.writeShellApplication {
            name = "nix-csf-validate";
            runtimeInputs = [ pkgs.nix ];
            text = builtins.readFile ./scripts/validate.sh;
          };
        }
      );

      templates.default = {
        path = ./templates/basic-flake;
        description = "Basic flake wiring for nix-csf";
      };
    };
}
