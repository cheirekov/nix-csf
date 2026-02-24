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
          netdataEval = mkEvalSystem ({ ... }: {
            services.netdata.enable = true;
            services.nixCsf = {
              observability.metrics = {
                enable = true;
                outputFile = "/var/lib/nix-csf/metrics.prom";
              };
              netdata = {
                enable = true;
                installHealthAlarms = true;
              };
            };
          });
          controlPlaneEval = mkEvalSystem ({ ... }: {
            services.nixCsf.controlPlane = {
              enable = true;
              requireAuth = false;
              environment = "lab";
            };
          });
          lfdDetectorEval = mkEvalSystem ({ ... }: {
            services.nixCsf = {
              controlPlane = {
                enable = true;
                requireAuth = false;
                environment = "lab";
              };
              dynamicOffenders = {
                enable = true;
                url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
                requireHTTPS = false;
                failOpen = true;
              };
              lfdDetector = {
                enable = true;
                threshold = 3;
                windowSeconds = 120;
                schedule.onCalendar = "minutely";
              };
            };
          });
          fail2banAdapterEval = mkEvalSystem ({ ... }: {
            services.nixCsf = {
              controlPlane = {
                enable = true;
                requireAuth = false;
                environment = "lab";
              };
              dynamicOffenders = {
                enable = true;
                url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
                requireHTTPS = false;
                failOpen = true;
              };
              fail2banAdapter = {
                enable = true;
                actionName = "nix-csf";
                installActionFile = true;
              };
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
            serverIcmpProfile = serverProfileEval.config.services.nixCsf.icmp.profile;
            serverIcmpRateLimit = boolText serverProfileEval.config.services.nixCsf.icmp.rateLimit.enable;
            workstationTCPCount = toString (builtins.length workstationProfileEval.config.services.nixCsf.openTCPPorts);
            workstationUDPCount = toString (builtins.length workstationProfileEval.config.services.nixCsf.openUDPPorts);
            workstationIcmpProfile = workstationProfileEval.config.services.nixCsf.icmp.profile;
            edgeOverrideTCP = builtins.concatStringsSep "," (map toString edgeOverrideEval.config.services.nixCsf.openTCPPorts);
            edgeOverrideLogDrops = boolText edgeOverrideEval.config.services.nixCsf.logDrops;
            edgeOverrideSynPreset = edgeOverrideEval.config.services.nixCsf.rateLimits.synFlood.preset;
            edgeOverrideOnCalendar = edgeOverrideEval.config.services.nixCsf.autoRefresh.onCalendar;
          } ''
            test "$serverSynEnabled" = "true"
            test "$serverConnEnabled" = "true"
            test "$serverLogDrops" = "true"
            test "$serverOnCalendar" = "hourly"
            test "$serverIcmpProfile" = "safe"
            test "$serverIcmpRateLimit" = "true"
            test "$workstationTCPCount" = "0"
            test "$workstationUDPCount" = "0"
            test "$workstationIcmpProfile" = "diagnostic"
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
          eval-netdata = pkgs.runCommand "nix-csf-eval-netdata" {
            netdataEnabled = boolText netdataEval.config.services.netdata.enable;
            chartsMainConfig = netdataEval.config.services.netdata.configDir."charts.d.conf";
            chartScript = netdataEval.config.services.netdata.configDir."charts.d/nix_csf.chart.sh";
            chartsConfig = netdataEval.config.services.netdata.configDir."charts.d/nix_csf.conf";
            healthConfig = netdataEval.config.services.netdata.configDir."health.d/nix_csf.conf";
            tmpfilesRules = builtins.concatStringsSep "\n" netdataEval.config.systemd.tmpfiles.rules;
            servicePathEntries = builtins.concatStringsSep "\n" (map toString netdataEval.config.systemd.services.netdata.path);
            netdataPackagePath = toString netdataEval.config.services.netdata.package;
          } ''
            test "$netdataEnabled" = "true"
            test -e "$chartsMainConfig"
            test -e "$chartScript"
            test -e "$chartsConfig"
            test -e "$healthConfig"
            grep -Fq 'chartsd=/etc/netdata/conf.d/charts.d' "$chartsMainConfig"
            grep -Fq 'nix_csf=yes' "$chartsMainConfig"
            grep -Fq 'nix_csf_metrics_file=/var/lib/nix-csf/metrics.prom' "$chartsConfig"
            grep -Fq 'alarm: nix_csf_cluster_policy_cache_expired' "$healthConfig"
            grep -Fq 'alarm: nix_csf_dynamic_snapshot_expired' "$healthConfig"
            printf '%s\n' "$tmpfilesRules" | grep -Fq 'd /var/lib/nix-csf 0751 root root -'
            printf '%s\n' "$servicePathEntries" | grep -Fqx "$netdataPackagePath"
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
          eval-lfd-detector = pkgs.runCommand "nix-csf-eval-lfd-detector" {
            lfdDetectorEnabled = boolText lfdDetectorEval.config.services.nixCsf.lfdDetector.enable;
            lfdDetectorExec = lfdDetectorEval.config.systemd.services.nix-csf-lfd-detector.serviceConfig.ExecStart;
            lfdTimerOnCalendar = lfdDetectorEval.config.systemd.timers.nix-csf-lfd-detector.timerConfig.OnCalendar;
          } ''
            test "$lfdDetectorEnabled" = "true"
            test -n "$lfdDetectorExec"
            test "$lfdTimerOnCalendar" = "minutely"
            touch "$out"
          '';
          eval-fail2ban-adapter = pkgs.runCommand "nix-csf-eval-fail2ban-adapter" {
            adapterEnabled = boolText fail2banAdapterEval.config.services.nixCsf.fail2banAdapter.enable;
            actionFile = fail2banAdapterEval.config.environment.etc."fail2ban/action.d/nix-csf.local".source;
          } ''
            test "$adapterEnabled" = "true"
            test -e "$actionFile"
            grep -Fq 'actionban =' "$actionFile"
            grep -Fq 'nix-csf-fail2ban-action ban' "$actionFile"
            grep -Fq 'actionunban =' "$actionFile"
            touch "$out"
          '';
          shellcheck = pkgs.runCommand "nix-csf-shellcheck" {
            nativeBuildInputs = [ pkgs.shellcheck ];
          } ''
            shellcheck \
              ${./scripts/nix-csf-apply.sh} \
              ${./scripts/nix-csf-fail2ban-action.sh} \
              ${./scripts/nix-csf-import-csf.sh} \
              ${./scripts/nix-csf-lfd-detector.sh} \
              ${./scripts/nix-csf-netdata.chart.sh} \
              ${./scripts/nix-csf-triage.sh} \
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
          csf-import-check = pkgs.runCommand "nix-csf-csf-import-check" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep ];
          } ''
            workdir="$(mktemp -d)"
            trap 'rm -rf "$workdir"' EXIT

            cat > "$workdir/csf.allow" <<'EOF'
# mixed allow entries
203.0.113.1
add allow_set 203.0.113.2/32
tcp|in|d=22|s=198.51.100.10
Include /root/custom.allow
EOF

            cat > "$workdir/csf.deny" <<'EOF'
198.51.100.20
ipset add deny_set 198.51.100.21/32
EOF

            cat > "$workdir/csf.ignore" <<'EOF'
2001:db8::1
EOF

            outdir="$workdir/out"

            ${pkgs.bash}/bin/bash ${./scripts/nix-csf-import-csf.sh} \
              --allow-file "$workdir/csf.allow" \
              --deny-file "$workdir/csf.deny" \
              --ignore-file "$workdir/csf.ignore" \
              --output-dir "$outdir" \
              --prefix "fixture"

            test -s "$outdir/fixture-allow.local"
            test -s "$outdir/fixture-deny.local"
            test -s "$outdir/fixture-ignore.local"
            test -s "$outdir/fixture-summary.log"
            test -s "$outdir/fixture-nixos-localFiles-snippet.nix"
            grep -qx '203.0.113.1' "$outdir/fixture-allow.local"
            grep -qx '203.0.113.2/32' "$outdir/fixture-allow.local"
            grep -qx '198.51.100.20' "$outdir/fixture-deny.local"
            grep -qx '198.51.100.21/32' "$outdir/fixture-deny.local"
            grep -qx '2001:db8::1' "$outdir/fixture-ignore.local"
            grep -Fq 'advanced_port_rule' "$outdir/fixture-unsupported.log"
            grep -Fq 'include_directive' "$outdir/fixture-unsupported.log"

            set +e
            ${pkgs.bash}/bin/bash ${./scripts/nix-csf-import-csf.sh} \
              --allow-file "$workdir/csf.allow" \
              --output-dir "$outdir" \
              --prefix "strict-fixture" \
              --strict >/dev/null 2>&1
            strict_rc=$?
            set -e
            test "$strict_rc" -eq 2

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

            grep -q 'Netdata Integration (`T-023`)' ${./docs/MONITORING.md}

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
          nixCsfctlPkg = pkgs.writeShellApplication {
            name = "nix-csfctl";
            runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
            text = builtins.readFile ./scripts/nix-csfctl.sh;
          };
          fail2banActionPkg = pkgs.writeShellApplication {
            name = "nix-csf-fail2ban-action";
            runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.systemd nixCsfctlPkg ];
            text = builtins.readFile ./scripts/nix-csf-fail2ban-action.sh;
          };
        in
        {
          version = pkgs.writeText "nix-csf-version" "${version}\n";
          nix-csfctl = nixCsfctlPkg;
          triage = pkgs.writeShellApplication {
            name = "nix-csf-triage";
            runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.nftables pkgs.systemd ];
            text = builtins.readFile ./scripts/nix-csf-triage.sh;
          };
          csf-import = pkgs.writeShellApplication {
            name = "nix-csf-import-csf";
            runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep ];
            text = builtins.readFile ./scripts/nix-csf-import-csf.sh;
          };
          lfd-detector = pkgs.writeShellApplication {
            name = "nix-csf-lfd-detector";
            runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.systemd pkgs.util-linux nixCsfctlPkg ];
            text = builtins.readFile ./scripts/nix-csf-lfd-detector.sh;
          };
          fail2ban-action = fail2banActionPkg;
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
