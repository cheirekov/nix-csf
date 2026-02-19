{
  description = "nix-csf: CSF-inspired NixOS firewall module (flake + non-flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      nixCsfModule = import ./modules/nixos/nix-csf.nix;
      version = builtins.replaceStrings [ "\r" "\n" ] [ "" "" ] (builtins.readFile ./VERSION);
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        }) systems);
      baseChecks = forAllSystems (system:
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
          version-semver = pkgs.runCommand "nix-csf-version-semver" {
            nativeBuildInputs = [ pkgs.gnugrep ];
          } ''
            printf '%s\n' '${version}' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
            touch "$out"
          '';
          eval-basic = pkgs.runCommand "nix-csf-eval-basic" {
            serviceExec = systemEval.config.systemd.services.nix-csf-apply.serviceConfig.ExecStart;
            moduleVersion = systemEval.config.services.nixCsf.moduleVersion;
            nativeBuildInputs = [ pkgs.gnugrep ];
          } ''
            test -n "$serviceExec"
            printf '%s\n' "$moduleVersion" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
            printf '%s\n' "$serviceExec" > "$out"
          '';
          shellcheck = pkgs.runCommand "nix-csf-shellcheck" {
            nativeBuildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck ${./scripts/nix-csf-apply.sh} ${./scripts/validate.sh} ${./scripts/release.sh}
            touch "$out"
          '';
        });
    in
    {
      nixosModules = {
        default = nixCsfModule;
        nix-csf = nixCsfModule;
      };

      checks = baseChecks // {
        x86_64-linux = baseChecks.x86_64-linux // {
          nix-csf-smoke = import ./tests/smoke.nix {
            pkgs = import nixpkgs { system = "x86_64-linux"; };
            module = nixCsfModule;
          };
          nix-csf-integration = import ./tests/integration.nix {
            pkgs = import nixpkgs { system = "x86_64-linux"; };
            module = nixCsfModule;
          };
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          version = pkgs.writeText "nix-csf-version" "${version}\n";
          validate = pkgs.writeShellApplication {
            name = "nix-csf-validate";
            runtimeInputs = [ pkgs.nix ];
            text = builtins.readFile ./scripts/validate.sh;
          };
          release = pkgs.writeShellApplication {
            name = "nix-csf-release";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.git
              pkgs.gnugrep
              pkgs.nix
            ];
            text = builtins.readFile ./scripts/release.sh;
          };
        }
      );

      templates.default = {
        path = ./templates/basic-flake;
        description = "Basic flake wiring for nix-csf";
      };
    };
}
