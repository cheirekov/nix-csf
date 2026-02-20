{ config, lib, pkgs, ... }:
let
  inherit (lib)
    all
    hasPrefix
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    removeSuffix
    unique
    types
    toUpper;

  cfg = config.services.nixCsf;
  moduleVersion = removeSuffix "\n" (builtins.readFile ../../VERSION);

  defaultBlocklistCatalog = {
    "spamhaus-drop-v4" = {
      url = "https://www.spamhaus.org/drop/drop_v4.txt";
      family = "ipv4";
      format = "cidr-text";
      description = "Spamhaus DROP IPv4 list.";
    };
    "spamhaus-drop-v6" = {
      url = "https://www.spamhaus.org/drop/drop_v6.txt";
      family = "ipv6";
      format = "cidr-text";
      description = "Spamhaus DROP IPv6 list.";
    };
  };

  missingBlocklistSources =
    builtins.filter (name: !(builtins.hasAttr name cfg.blocklists.catalog))
      cfg.blocklists.sources;

  selectedCatalogBlocklistURLs =
    map (name: (builtins.getAttr name cfg.blocklists.catalog).url)
      (builtins.filter (name: builtins.hasAttr name cfg.blocklists.catalog)
        cfg.blocklists.sources);

  resolvedBlocklistURLs = unique (selectedCatalogBlocklistURLs ++ cfg.blocklists.urls);

  isHttpsUrl = url: builtins.match "^https://[^[:space:]]+$" url != null;
  catalogBlocklistURLs = map (entry: entry.url) (builtins.attrValues cfg.blocklists.catalog);

  synFloodPresetTable = {
    relaxed = {
      rate = "120/second";
      burst = 240;
    };
    balanced = {
      rate = "60/second";
      burst = 120;
    };
    strict = {
      rate = "25/second";
      burst = 50;
    };
  };

  connFloodPresetTable = {
    relaxed = {
      rate = "200/second";
      burst = 400;
    };
    balanced = {
      rate = "120/second";
      burst = 240;
    };
    strict = {
      rate = "60/second";
      burst = 120;
    };
  };

  synFloodPreset = synFloodPresetTable.${cfg.rateLimits.synFlood.preset};
  connFloodPreset = connFloodPresetTable.${cfg.rateLimits.connFlood.preset};

  applyTool = pkgs.writeShellApplication {
    name = "nix-csf-apply";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      gnugrep
      jq
      nftables
    ];
    text = builtins.readFile ../../scripts/nix-csf-apply.sh;
  };

  runtimeConfigFile = (pkgs.formats.json { }).generate "nix-csf-runtime-config.json" {
    moduleVersion = cfg.moduleVersion;
    threatProfile = cfg.threatProfile;
    defaultPolicy = cfg.defaultPolicy;
    forwardPolicy = cfg.forwardPolicy;
    trustedInterfaces = cfg.trustedInterfaces;
    openTCPPorts = cfg.openTCPPorts;
    openUDPPorts = cfg.openUDPPorts;
    allowICMP = cfg.allowICMP;
    allowIPv4 = cfg.allowIPv4;
    allowIPv6 = cfg.allowIPv6;
    denyIPv4 = cfg.denyIPv4;
    denyIPv6 = cfg.denyIPv6;
    logDrops = cfg.logDrops;
    synRateLimit = cfg.synRateLimit;
    rateLimits = {
      synFlood = {
        enable = cfg.rateLimits.synFlood.enable;
        preset = cfg.rateLimits.synFlood.preset;
        rate = synFloodPreset.rate;
        burst = synFloodPreset.burst;
      };
      connFlood = {
        enable = cfg.rateLimits.connFlood.enable;
        preset = cfg.rateLimits.connFlood.preset;
        rate = connFloodPreset.rate;
        burst = connFloodPreset.burst;
      };
    };
    country = {
      enable = cfg.country.enable;
      mode = cfg.country.mode;
      countries = map toUpper cfg.country.countries;
      ipv4URLTemplate = cfg.country.ipv4URLTemplate;
      ipv6URLTemplate = cfg.country.ipv6URLTemplate;
      failOpen = cfg.country.failOpen;
      extraIPv4 = cfg.country.extraIPv4;
      extraIPv6 = cfg.country.extraIPv6;
      portDeny = {
        enable = cfg.country.portDeny.enable;
        countries = map toUpper cfg.country.portDeny.countries;
        tcpPorts = cfg.country.portDeny.tcpPorts;
        udpPorts = cfg.country.portDeny.udpPorts;
        extraIPv4 = cfg.country.portDeny.extraIPv4;
        extraIPv6 = cfg.country.portDeny.extraIPv6;
      };
    };
    blocklists = {
      enable = cfg.blocklists.enable;
      urls = resolvedBlocklistURLs;
      failOpen = cfg.blocklists.failOpen;
      sources = cfg.blocklists.sources;
      enforceCatalog = cfg.blocklists.enforceCatalog;
      requireHTTPS = cfg.blocklists.requireHTTPS;
    };
    clusterPolicy = {
      enable = cfg.clusterPolicy.enable;
      url = cfg.clusterPolicy.url;
      failOpen = cfg.clusterPolicy.failOpen;
      requireHTTPS = cfg.clusterPolicy.requireHTTPS;
      authTokenFile = cfg.clusterPolicy.authTokenFile;
      nodeId = cfg.clusterPolicy.nodeId;
    };
    observability = {
      structuredLogging = cfg.observability.structuredLogging;
      metrics = {
        enable = cfg.observability.metrics.enable;
        outputFile = cfg.observability.metrics.outputFile;
      };
    };
  };

  validCountryCode = cc: builtins.match "^[A-Z]{2}$" (toUpper cc) != null;

  threatProfileDefaults = {
    custom = { };
    server = {
      services.nixCsf = {
        logDrops = mkDefault true;
        rateLimits.synFlood = {
          enable = mkDefault true;
          preset = mkDefault "balanced";
        };
        rateLimits.connFlood = {
          enable = mkDefault true;
          preset = mkDefault "balanced";
        };
        autoRefresh.onCalendar = mkDefault "hourly";
      };
    };
    workstation = {
      services.nixCsf = {
        openTCPPorts = mkDefault [ ];
        openUDPPorts = mkDefault [ ];
        allowICMP = mkDefault true;
        logDrops = mkDefault true;
      };
    };
    edge = {
      services.nixCsf = {
        openTCPPorts = mkDefault [ 22 443 ];
        openUDPPorts = mkDefault [ 53 51820 ];
        logDrops = mkDefault true;
        rateLimits.synFlood = {
          enable = mkDefault true;
          preset = mkDefault "strict";
        };
        rateLimits.connFlood = {
          enable = mkDefault true;
          preset = mkDefault "balanced";
        };
        autoRefresh.onCalendar = mkDefault "hourly";
      };
    };
  };

in
{
  options.services.nixCsf = {
    enable = mkEnableOption "CSF-inspired nftables firewall with NixOS-native options";

    threatProfile = mkOption {
      type = types.enum [ "custom" "server" "workstation" "edge" ];
      default = "custom";
      example = "server";
      description = ''
        Preset threat profile that applies `mkDefault` values to related options.
        Explicit option values always override profile defaults.
        - custom: keep module baseline defaults
        - server: enable balanced flood controls, drop logging, hourly refresh
        - workstation: no inbound open TCP/UDP ports by default
        - edge: stricter flood controls and edge-oriented open ports
      '';
    };

    moduleVersion = mkOption {
      type = types.str;
      readOnly = true;
      default = moduleVersion;
      description = ''
        nix-csf module release version from the repository VERSION file.
        This value is exported into runtime metadata and metrics.
      '';
    };

    defaultPolicy = mkOption {
      type = types.enum [ "drop" "accept" ];
      default = "drop";
      description = "Default policy for inbound traffic.";
    };

    forwardPolicy = mkOption {
      type = types.enum [ "drop" "accept" ];
      default = "drop";
      description = "Default policy for forwarded traffic.";
    };

    trustedInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "tailscale0" "wg0" ];
      description = "Interfaces that are always accepted for inbound traffic.";
    };

    openTCPPorts = mkOption {
      type = types.listOf types.port;
      default = [ 22 ];
      example = [ 22 80 443 ];
      description = "TCP ports allowed from non-blocked sources.";
    };

    openUDPPorts = mkOption {
      type = types.listOf types.port;
      default = [ ];
      example = [ 53 51820 ];
      description = "UDP ports allowed from non-blocked sources.";
    };

    allowICMP = mkOption {
      type = types.bool;
      default = true;
      description = "Allow ICMP/ICMPv6 traffic.";
    };

    allowIPv4 = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.0.0.0/8" "203.0.113.5" ];
      description = "IPv4 addresses or CIDRs that are always allowed.";
    };

    allowIPv6 = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "2001:db8::/32" ];
      description = "IPv6 addresses or CIDRs that are always allowed.";
    };

    denyIPv4 = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "198.51.100.0/24" ];
      description = "IPv4 addresses or CIDRs that are always denied.";
    };

    denyIPv6 = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "2001:db8:bad::/48" ];
      description = "IPv6 addresses or CIDRs that are always denied.";
    };

    logDrops = mkOption {
      type = types.bool;
      default = false;
      description = "Log dropped packets from the final drop/reject rule.";
    };

    synRateLimit = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "25/second";
      description = ''
        Optional nftables rate expression for new TCP SYN packets.
        Example values: "25/second", "300/minute".
      '';
    };

    rateLimits = {
      synFlood = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable per-source SYN flood protection preset.";
        };

        preset = mkOption {
          type = types.enum [ "relaxed" "balanced" "strict" ];
          default = "balanced";
          description = ''
            SYN flood preset profile:
            - relaxed: higher threshold, lower false positives
            - balanced: general server default
            - strict: lower threshold, stronger burst control
          '';
        };
      };

      connFlood = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable per-source new-connection flood protection preset.";
        };

        preset = mkOption {
          type = types.enum [ "relaxed" "balanced" "strict" ];
          default = "balanced";
          description = ''
            New-connection flood preset profile:
            - relaxed: higher threshold
            - balanced: general server default
            - strict: lower threshold
          '';
        };
      };
    };

    country = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable country-based deny list feeds.";
      };

      mode = mkOption {
        type = types.enum [ "deny" "allow" ];
        default = "deny";
        description = ''
          Country policy mode:
          - "deny": block source IPs from configured country sets.
          - "allow": allow only configured country sets for inbound traffic.
        '';
      };

      countries = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "CN" "RU" ];
        description = ''
          ISO-3166 alpha-2 country codes used by country.mode.
          In "deny" mode these countries are blocked.
          In "allow" mode only these countries are permitted.
        '';
      };

      ipv4URLTemplate = mkOption {
        type = types.str;
        default = "https://www.ipdeny.com/ipblocks/data/countries/%s.zone";
        example = "https://www.ipdeny.com/ipblocks/data/countries/%s.zone";
        description = ''
          URL template for country IPv4 CIDR data.
          `%s` is replaced with a lowercase country code.
        '';
      };

      ipv6URLTemplate = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://example.invalid/country-ipv6/%s.zone";
        description = ''
          Optional URL template for country IPv6 CIDR data.
          `%s` is replaced with a lowercase country code.
        '';
      };

      failOpen = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If true, refresh failures are tolerated when no cached data is available.
          If false, refresh fails hard when data cannot be fetched and cache is empty.
        '';
      };

      extraIPv4 = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "192.0.2.0/24" ];
        description = "Additional static IPv4 CIDRs added to the country deny set.";
      };

      extraIPv6 = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "2001:db8:ffff::/48" ];
        description = "Additional static IPv6 CIDRs added to the country deny set.";
      };

      portDeny = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable port-scoped country deny policy (CSF CC_DENY_PORTS style).
            This only denies selected ports for selected countries.
          '';
        };

        countries = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "RU" "CN" ];
          description = "ISO-3166 alpha-2 country codes that should be denied on selected ports.";
        };

        tcpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          example = [ 21 25 ];
          description = "TCP destination ports denied for sources in country.portDeny.countries.";
        };

        udpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          example = [ 53 ];
          description = "UDP destination ports denied for sources in country.portDeny.countries.";
        };

        extraIPv4 = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "203.0.113.0/24" ];
          description = "Additional static IPv4 CIDRs added to the port-scoped country deny set.";
        };

        extraIPv6 = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "2001:db8:abcd::/48" ];
          description = "Additional static IPv6 CIDRs added to the port-scoped country deny set.";
        };
      };
    };

    blocklists = {
      catalog = mkOption {
        type = types.attrsOf (types.submodule ({ ... }: {
          options = {
            url = mkOption {
              type = types.str;
              example = "https://www.spamhaus.org/drop/drop_v4.txt";
              description = "HTTP(S) endpoint that provides CIDR lines.";
            };

            family = mkOption {
              type = types.enum [ "ipv4" "ipv6" "mixed" ];
              default = "mixed";
              description = "Declared address-family expectation for this source.";
            };

            format = mkOption {
              type = types.enum [ "cidr-text" ];
              default = "cidr-text";
              description = "Parser format identifier for this source.";
            };

            description = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable source notes for governance/audit.";
            };
          };
        }));
        default = defaultBlocklistCatalog;
        description = ''
          Trusted blocklist source catalog.
          Use blocklists.sources to enable one or more entries.
        '';
      };

      sources = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "spamhaus-drop-v4" "spamhaus-drop-v6" ];
        description = ''
          Source IDs selected from blocklists.catalog.
          Selected source URLs are merged with blocklists.urls.
        '';
      };

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable remote blocklist URL ingestion.";
      };

      enforceCatalog = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If true, direct blocklists.urls entries are disallowed.
          Only blocklists.sources + blocklists.catalog may define URLs.
        '';
      };

      requireHTTPS = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Require all blocklist URLs (catalog and direct) to use https://.
          Disable only for controlled local/offline feeds.
        '';
      };

      urls = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "https://www.spamhaus.org/drop/drop_v4.txt"
          "https://www.spamhaus.org/drop/drop_v6.txt"
        ];
        description = ''
          Additional direct blocklist URLs containing CIDR entries.
          Prefer blocklists.catalog + blocklists.sources for governed source selection.
        '';
      };

      failOpen = mkOption {
        type = types.bool;
        default = true;
        description = "Same behavior as country.failOpen, but for blocklist URLs.";
      };
    };

    clusterPolicy = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable centralized cluster policy propagation from a remote JSON endpoint.
          The downloaded policy is merged into local allow/deny CIDR sets.
        '';
      };

      url = mkOption {
        type = types.str;
        default = "";
        example = "https://policy.example.org/nix-csf/edge-west.json";
        description = ''
          Endpoint that returns a JSON policy document with optional arrays:
          - allowIPv4
          - allowIPv6
          - denyIPv4
          - denyIPv6
        '';
      };

      failOpen = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If true, refresh failures are tolerated when no cached cluster policy exists.
          If false, refresh fails hard when policy cannot be fetched and cache is empty.
        '';
      };

      requireHTTPS = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Require clusterPolicy.url to use https://.
          Disable only for controlled local/offline testing.
        '';
      };

      authTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/nix-csf-cluster-token";
        description = ''
          Optional absolute path to a bearer token file for cluster policy requests.
          Content is sent as Authorization: Bearer <token>.
        '';
      };

      nodeId = mkOption {
        type = types.str;
        default = "";
        example = "web-eu-01";
        description = ''
          Optional node identifier sent as HTTP header:
          X-Nix-Csf-Node: <nodeId>.
        '';
      };
    };

    observability = {
      structuredLogging = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Emit structured key-value logs from apply/refresh runs.
          Useful for journal parsing and incident timelines.
        '';
      };

      metrics = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Export runtime snapshot metrics in Prometheus textfile format.";
        };

        outputFile = mkOption {
          type = types.str;
          default = "/var/lib/nix-csf/metrics.prom";
          example = "/var/lib/node_exporter/textfile_collector/nix-csf.prom";
          description = ''
            Destination file for Prometheus textfile metrics.
            Parent directory is created automatically at runtime.
          '';
        };
      };
    };

    autoRefresh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable periodic refresh of remote country and blocklist feeds.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "daily";
        example = "hourly";
        description = "systemd timer schedule for automatic feed refresh.";
      };

      randomDelaySec = mkOption {
        type = types.str;
        default = "15m";
        description = "Randomized delay for the refresh timer.";
      };

      persistent = mkOption {
        type = types.bool;
        default = true;
        description = "Run missed timer executions at next boot.";
      };

      runOnBoot = mkOption {
        type = types.bool;
        default = true;
        description = "Run a refresh once per boot after network is online.";
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.threatProfile == "server") threatProfileDefaults.server)
    (mkIf (cfg.enable && cfg.threatProfile == "workstation") threatProfileDefaults.workstation)
    (mkIf (cfg.enable && cfg.threatProfile == "edge") threatProfileDefaults.edge)
    (mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.networking.firewall.enable;
        message = "services.nixCsf requires networking.firewall.enable = false (or unset).";
      }
      {
        assertion = !cfg.country.enable || cfg.country.countries != [ ];
        message = "services.nixCsf.country.enable requires at least one country code.";
      }
      {
        assertion = all validCountryCode cfg.country.countries;
        message = "services.nixCsf.country.countries entries must be ISO alpha-2 codes (e.g. US, DE).";
      }
      {
        assertion = !cfg.country.portDeny.enable || cfg.country.portDeny.countries != [ ];
        message = "services.nixCsf.country.portDeny.enable requires at least one country code.";
      }
      {
        assertion = all validCountryCode cfg.country.portDeny.countries;
        message = "services.nixCsf.country.portDeny.countries entries must be ISO alpha-2 codes (e.g. US, DE).";
      }
      {
        assertion = !cfg.country.portDeny.enable
          || cfg.country.portDeny.tcpPorts != [ ]
          || cfg.country.portDeny.udpPorts != [ ];
        message = "services.nixCsf.country.portDeny.enable requires at least one TCP or UDP port.";
      }
      {
        assertion = !(cfg.synRateLimit != null && cfg.rateLimits.synFlood.enable);
        message = ''
          services.nixCsf.synRateLimit cannot be combined with rateLimits.synFlood.enable.
          Use either the legacy explicit synRateLimit or the synFlood preset.
        '';
      }
      {
        assertion = missingBlocklistSources == [ ];
        message = ''
          services.nixCsf.blocklists.sources contains unknown catalog IDs:
          ${builtins.concatStringsSep ", " missingBlocklistSources}
        '';
      }
      {
        assertion = !cfg.blocklists.enable || resolvedBlocklistURLs != [ ];
        message = "services.nixCsf.blocklists.enable requires at least one URL or catalog source.";
      }
      {
        assertion = !cfg.blocklists.enforceCatalog || cfg.blocklists.urls == [ ];
        message = ''
          services.nixCsf.blocklists.enforceCatalog = true forbids blocklists.urls.
          Use blocklists.sources with blocklists.catalog entries instead.
        '';
      }
      {
        assertion = !cfg.blocklists.requireHTTPS || all isHttpsUrl cfg.blocklists.urls;
        message = "services.nixCsf.blocklists.urls must use https:// when blocklists.requireHTTPS = true.";
      }
      {
        assertion = !cfg.blocklists.requireHTTPS || all isHttpsUrl catalogBlocklistURLs;
        message = ''
          services.nixCsf.blocklists.catalog.<name>.url must use https:// when
          blocklists.requireHTTPS = true.
        '';
      }
      {
        assertion = !cfg.clusterPolicy.enable || cfg.clusterPolicy.url != "";
        message = "services.nixCsf.clusterPolicy.enable requires clusterPolicy.url.";
      }
      {
        assertion = !cfg.clusterPolicy.enable
          || !cfg.clusterPolicy.requireHTTPS
          || isHttpsUrl cfg.clusterPolicy.url;
        message = "services.nixCsf.clusterPolicy.url must use https:// when clusterPolicy.requireHTTPS = true.";
      }
      {
        assertion = cfg.clusterPolicy.authTokenFile == null || hasPrefix "/" cfg.clusterPolicy.authTokenFile;
        message = "services.nixCsf.clusterPolicy.authTokenFile must be an absolute path when set.";
      }
      {
        assertion = !cfg.observability.metrics.enable || hasPrefix "/" cfg.observability.metrics.outputFile;
        message = "services.nixCsf.observability.metrics.outputFile must be an absolute path.";
      }
      {
        assertion = !(cfg.country.enable && cfg.country.mode == "allow")
          || cfg.country.ipv4URLTemplate != ""
          || cfg.country.ipv6URLTemplate != null
          || cfg.country.extraIPv4 != [ ]
          || cfg.country.extraIPv6 != [ ];
        message = ''
          services.nixCsf.country.mode = "allow" requires at least one country data source
          (URL template or extra country CIDRs).
        '';
      }
      {
        assertion = !cfg.country.portDeny.enable
          || cfg.country.ipv4URLTemplate != ""
          || cfg.country.ipv6URLTemplate != null
          || cfg.country.portDeny.extraIPv4 != [ ]
          || cfg.country.portDeny.extraIPv6 != [ ];
        message = ''
          services.nixCsf.country.portDeny.enable requires at least one country data source
          (URL template or portDeny extra CIDRs).
        '';
      }
    ];

    networking.firewall.enable = mkDefault false;
    boot.kernelModules = [ "nf_tables" ];

    environment.systemPackages = [ applyTool ];

    systemd.tmpfiles.rules = [
      "d /var/lib/nix-csf 0750 root root -"
      "d /var/lib/nix-csf/cache 0750 root root -"
    ];

    systemd.services.nix-csf-apply = {
      description = "Apply nix-csf nftables rules";
      wantedBy = [ "network-pre.target" ];
      before = [ "network-pre.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${applyTool}/bin/nix-csf-apply --config ${runtimeConfigFile} --mode apply";
      };
    };

    systemd.services.nix-csf-refresh = {
      description = "Refresh nix-csf remote feeds and re-apply rules";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = lib.optionals cfg.autoRefresh.runOnBoot [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${applyTool}/bin/nix-csf-apply --config ${runtimeConfigFile} --mode refresh";
      };
    };

    systemd.timers.nix-csf-refresh = mkIf cfg.autoRefresh.enable {
      description = "Periodic refresh timer for nix-csf feeds";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.autoRefresh.onCalendar;
        RandomizedDelaySec = cfg.autoRefresh.randomDelaySec;
        Persistent = cfg.autoRefresh.persistent;
      };
    };
    })
  ];
}
