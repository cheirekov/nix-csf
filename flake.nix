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
          mkEvalSystem = extraModule: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              nixCsfModule
              ({ ... }: {
                services.nixCsf.enable = true;
                networking.firewall.enable = false;
                system.stateVersion = "24.11";
              })
              extraModule
            ];
          };
          boolText = value: if value then "true" else "false";
          systemEval = mkEvalSystem ({ ... }: { });
          serverProfileEval = mkEvalSystem ({ ... }: {
            services.nixCsf.threatProfile = "server";
          });
          workstationProfileEval = mkEvalSystem ({ ... }: {
            services.nixCsf.threatProfile = "workstation";
          });
          edgeOverrideEval = mkEvalSystem ({ ... }: {
            services.nixCsf = {
              threatProfile = "edge";
              openTCPPorts = [ 8443 ];
              logDrops = false;
              rateLimits.synFlood = {
                enable = true;
                preset = "relaxed";
              };
              autoRefresh.onCalendar = "weekly";
            };
          });
          monitoringEval = mkEvalSystem ({ ... }: {
            services.prometheus = {
              enable = true;
              ruleFiles = [ ./docs/monitoring/prometheus-alert-rules.yml ];
              scrapeConfigs = [
                {
                  job_name = "node";
                  static_configs = [
                    {
                      targets = [ "127.0.0.1:9100" ];
                      labels = { role = "firewall"; };
                    }
                  ];
                }
              ];
            };
            services.grafana.enable = true;
          });
          controlPlaneEval = mkEvalSystem ({ ... }: {
            services.nixCsf.controlPlane = {
              enable = true;
              requireAuth = false;
              environment = "lab";
            };
          });
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
          eval-profiles = pkgs.runCommand "nix-csf-eval-profiles" {
            serverSynEnabled = boolText serverProfileEval.config.services.nixCsf.rateLimits.synFlood.enable;
            serverConnEnabled = boolText serverProfileEval.config.services.nixCsf.rateLimits.connFlood.enable;
            serverLogDrops = boolText serverProfileEval.config.services.nixCsf.logDrops;
            serverOnCalendar = serverProfileEval.config.services.nixCsf.autoRefresh.onCalendar;
            workstationTCPCount = toString (builtins.length workstationProfileEval.config.services.nixCsf.openTCPPorts);
            workstationUDPCount = toString (builtins.length workstationProfileEval.config.services.nixCsf.openUDPPorts);
            edgeOverrideTCP = builtins.concatStringsSep "," (map toString edgeOverrideEval.config.services.nixCsf.openTCPPorts);
            edgeOverrideLogDrops = boolText edgeOverrideEval.config.services.nixCsf.logDrops;
            edgeOverrideSynPreset = edgeOverrideEval.config.services.nixCsf.rateLimits.synFlood.preset;
            edgeOverrideOnCalendar = edgeOverrideEval.config.services.nixCsf.autoRefresh.onCalendar;
          } ''
            test "$serverSynEnabled" = "true"
            test "$serverConnEnabled" = "true"
            test "$serverLogDrops" = "true"
            test "$serverOnCalendar" = "hourly"
            test "$workstationTCPCount" = "0"
            test "$workstationUDPCount" = "0"
            test "$edgeOverrideTCP" = "8443"
            test "$edgeOverrideLogDrops" = "false"
            test "$edgeOverrideSynPreset" = "relaxed"
            test "$edgeOverrideOnCalendar" = "weekly"
            touch "$out"
          '';
          eval-monitoring = pkgs.runCommand "nix-csf-eval-monitoring" {
            prometheusEnabled = boolText monitoringEval.config.services.prometheus.enable;
            grafanaEnabled = boolText monitoringEval.config.services.grafana.enable;
            ruleFileCount = toString (builtins.length monitoringEval.config.services.prometheus.ruleFiles);
          } ''
            test "$prometheusEnabled" = "true"
            test "$grafanaEnabled" = "true"
            test "$ruleFileCount" = "1"
            touch "$out"
          '';
          eval-control-plane = pkgs.runCommand "nix-csf-eval-control-plane" {
            controlPlaneEnabled = boolText controlPlaneEval.config.services.nixCsf.controlPlane.enable;
            controlPlaneExec = controlPlaneEval.config.systemd.services.nix-csf-control-plane.serviceConfig.ExecStart;
          } ''
            test "$controlPlaneEnabled" = "true"
            test -n "$controlPlaneExec"
            printf '%s\n' "$controlPlaneExec" > "$out"
          '';
          shellcheck = pkgs.runCommand "nix-csf-shellcheck" {
            nativeBuildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck \
              ${./scripts/nix-csf-apply.sh} \
              ${./scripts/nix-csfctl.sh} \
              ${./scripts/validate.sh} \
              ${./scripts/validate-fast.sh} \
              ${./scripts/validate-capture.sh} \
              ${./scripts/release.sh}
            touch "$out"
          '';
          control-plane-lint = pkgs.runCommand "nix-csf-control-plane-lint" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            python3 -m py_compile ${./scripts/nix-csf-control-plane.py}
            touch "$out"
          '';
          monitoring-pack = pkgs.runCommand "nix-csf-monitoring-pack" {
            nativeBuildInputs = [ pkgs.gnugrep pkgs.jq pkgs.yq-go ];
          } ''
            jq -e '
              .uid == "nix-csf-ops" and
              .schemaVersion >= 39 and
              (.panels | length) >= 8 and
              (.templating.list | length) >= 2
            ' ${./docs/monitoring/grafana-dashboard.json} >/dev/null

            yq -e '.groups | length >= 1' ${./docs/monitoring/prometheus-alert-rules.yml} >/dev/null
            yq -e '.groups[].rules[] | select(.alert == "NixCsfClusterPolicyCacheExpired") | .alert' ${./docs/monitoring/prometheus-alert-rules.yml} >/dev/null
            yq -e '.groups[].rules[] | select(.alert == "NixCsfDynamicSnapshotExpired") | .alert' ${./docs/monitoring/prometheus-alert-rules.yml} >/dev/null

            grep -q 'Optional Netdata Story (`T-023`)' ${./docs/MONITORING.md}

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
          nix-csfctl = pkgs.writeShellApplication {
            name = "nix-csfctl";
            runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
            text = builtins.readFile ./scripts/nix-csfctl.sh;
          };
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
