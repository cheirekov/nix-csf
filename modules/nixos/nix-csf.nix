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
      url = "https://www.spamhaus.org/drop/drop.txt";
      family = "ipv4";
      format = "cidr-text";
      description = "Spamhaus DROP IPv4 list.";
    };
    "spamhaus-drop-v6" = {
      url = "https://www.spamhaus.org/drop/dropv6.txt";
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
  allLocalPolicyFiles = cfg.localFiles.allow ++ cfg.localFiles.deny ++ cfg.localFiles.ignore;

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

  controlPlaneTool = pkgs.writeShellApplication {
    name = "nix-csf-control-plane";
    runtimeInputs = with pkgs; [ python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../scripts/nix-csf-control-plane.py} "$@"
    '';
  };

  controlPlaneCliTool = pkgs.writeShellApplication {
    name = "nix-csfctl";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = builtins.readFile ../../scripts/nix-csfctl.sh;
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
    icmp = {
      profile = cfg.icmp.profile;
      extraIPv4Types = cfg.icmp.extraIPv4Types;
      extraIPv6Types = cfg.icmp.extraIPv6Types;
      rateLimit = {
        enable = cfg.icmp.rateLimit.enable;
        rate = cfg.icmp.rateLimit.rate;
        burst = cfg.icmp.rateLimit.burst;
      };
    };
    allowIPv4 = cfg.allowIPv4;
    allowIPv6 = cfg.allowIPv6;
    denyIPv4 = cfg.denyIPv4;
    denyIPv6 = cfg.denyIPv6;
    localFiles = {
      enable = cfg.localFiles.enable;
      allow = cfg.localFiles.allow;
      deny = cfg.localFiles.deny;
      ignore = cfg.localFiles.ignore;
      failOnMissing = cfg.localFiles.failOnMissing;
    };
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
      portAllow = {
        enable = cfg.country.portAllow.enable;
        countries = map toUpper cfg.country.portAllow.countries;
        tcpPorts = cfg.country.portAllow.tcpPorts;
        udpPorts = cfg.country.portAllow.udpPorts;
        extraIPv4 = cfg.country.portAllow.extraIPv4;
        extraIPv6 = cfg.country.portAllow.extraIPv6;
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
      authTokenFiles = cfg.clusterPolicy.authTokenFiles;
      nodeId = cfg.clusterPolicy.nodeId;
    };
    dynamicOffenders = {
      enable = cfg.dynamicOffenders.enable;
      url = cfg.dynamicOffenders.url;
      failOpen = cfg.dynamicOffenders.failOpen;
      requireHTTPS = cfg.dynamicOffenders.requireHTTPS;
      authTokenFile = cfg.dynamicOffenders.authTokenFile;
      authTokenFiles = cfg.dynamicOffenders.authTokenFiles;
      nodeId = cfg.dynamicOffenders.nodeId;
      defaultEntryTTLSeconds = cfg.dynamicOffenders.defaultEntryTTLSeconds;
      maxEntries = cfg.dynamicOffenders.maxEntries;
    };
    coexistence = {
      profile = cfg.coexistence.profile;
    };
    observability = {
      structuredLogging = cfg.observability.structuredLogging;
      metrics = {
        enable = cfg.observability.metrics.enable;
        outputFile = cfg.observability.metrics.outputFile;
      };
    };
  };

  controlPlaneExecStart =
    let
      baseArgs = [
        "--bind-address" cfg.controlPlane.bindAddress
        "--port" (toString cfg.controlPlane.port)
        "--data-dir" cfg.controlPlane.dataDir
        "--environment" cfg.controlPlane.environment
        "--cluster-policy-ttl-seconds" (toString cfg.controlPlane.clusterPolicyTTLSeconds)
        "--dynamic-snapshot-ttl-seconds" (toString cfg.controlPlane.dynamicSnapshotTTLSeconds)
        "--default-ban-ttl-seconds" (toString cfg.controlPlane.defaultBanTTLSeconds)
        "--escalation-threshold" (toString cfg.controlPlane.escalation.tempBanThreshold)
        "--escalation-window-seconds" (toString cfg.controlPlane.escalation.windowSeconds)
        "--escalation-max-audit-entries" (toString cfg.controlPlane.escalation.maxAuditEntries)
      ];
      modeArgs =
        (if cfg.controlPlane.escalation.enable then [ "--escalation-enable" ] else [ ]);
      authArgs =
        (if cfg.controlPlane.requireAuth then [ "--require-auth" ] else [ ])
        ++ (if cfg.controlPlane.authTokenFile != null then [ "--auth-token-file" cfg.controlPlane.authTokenFile ] else [ ]);
    in
    "${controlPlaneTool}/bin/nix-csf-control-plane ${lib.escapeShellArgs (baseArgs ++ modeArgs ++ authArgs)}";

  validCountryCode = cc: builtins.match "^[A-Z]{2}$" (toUpper cc) != null;

  threatProfileDefaults = {
    custom = { };
    server = {
      services.nixCsf = {
        logDrops = mkDefault true;
        icmp.profile = mkDefault "safe";
        icmp.rateLimit.enable = mkDefault true;
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
        icmp.profile = mkDefault "diagnostic";
        icmp.rateLimit.enable = mkDefault true;
        logDrops = mkDefault true;
      };
    };
    edge = {
      services.nixCsf = {
        openTCPPorts = mkDefault [ 22 443 ];
        openUDPPorts = mkDefault [ 53 51820 ];
        logDrops = mkDefault true;
        icmp.profile = mkDefault "safe";
        icmp.rateLimit.enable = mkDefault true;
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
        - server: enable balanced flood controls, ICMP safe profile, drop logging, hourly refresh
        - workstation: no inbound open TCP/UDP ports by default, ICMP diagnostic profile
        - edge: stricter flood controls, ICMP safe profile, edge-oriented open ports
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
      description = ''
        Legacy compatibility toggle for broad ICMP/ICMPv6 acceptance.
        Used when `services.nixCsf.icmp.profile = "legacy"`.
      '';
    };

    icmp = {
      profile = mkOption {
        type = types.enum [ "legacy" "off" "safe" "diagnostic" "open" ];
        default = "legacy";
        description = ''
          ICMP policy profile:
          - legacy: use `allowICMP` broad allow/deny behavior
          - off: deny ICMP/ICMPv6 (except conntrack-established traffic)
          - safe: allow essential control/error and IPv6 neighbor discovery types
          - diagnostic: safe + echo request/reply types
          - open: allow all ICMP/ICMPv6 traffic
        '';
      };

      extraIPv4Types = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "echo-request" "redirect" ];
        description = ''
          Additional nftables ICMPv4 type names allowed in safe/diagnostic profiles.
          Ignored in `off`, `open`, and `legacy` profiles.
        '';
      };

      extraIPv6Types = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "echo-request" "echo-reply" ];
        description = ''
          Additional nftables ICMPv6 type names allowed in safe/diagnostic profiles.
          Ignored in `off`, `open`, and `legacy` profiles.
        '';
      };

      rateLimit = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Apply a per-rule ICMP/ICMPv6 accept rate limit for profile-generated rules.
            Does not affect `legacy` profile behavior.
          '';
        };

        rate = mkOption {
          type = types.str;
          default = "30/second";
          example = "120/minute";
          description = "nftables rate expression used when icmp.rateLimit.enable = true.";
        };

        burst = mkOption {
          type = types.ints.positive;
          default = 120;
          description = "Packet burst threshold for ICMP rate-limited accept rules.";
        };
      };
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

    localFiles = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable hybrid runtime reconciliation from local operator-managed files.
          Files are merged with declarative and remote sources during apply/refresh.
        '';
      };

      allow = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/var/lib/nix-csf/lists/allow.local" ];
        description = ''
          Local file paths with CIDR/IP entries merged into allow sets.
          Supports plain CIDR/IP lines and ipset-style `add` lines.
        '';
      };

      deny = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/var/lib/nix-csf/lists/deny.local" ];
        description = ''
          Local file paths with CIDR/IP entries merged into deny sets.
          Supports plain CIDR/IP lines and ipset-style `add` lines.
        '';
      };

      ignore = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/var/lib/nix-csf/lists/ignore.local" ];
        description = ''
          Local file paths with CIDR/IP entries merged into ignore overlays.
          Ignore entries are promoted into allow and subtracted from deny-style overlays.
        '';
      };

      failOnMissing = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If true, missing/unreadable local files fail the run.
          If false, missing files are skipped with warning.
        '';
      };
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

      portAllow = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable port-scoped country allow policy (CSF CC_ALLOW_PORTS style).
            This only allows selected ports for selected countries.
          '';
        };

        countries = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "US" "CA" ];
          description = "ISO-3166 alpha-2 country codes that should be allowed on selected ports.";
        };

        tcpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          example = [ 22 443 ];
          description = "TCP destination ports allowed for sources in country.portAllow.countries.";
        };

        udpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          example = [ 53 ];
          description = "UDP destination ports allowed for sources in country.portAllow.countries.";
        };

        extraIPv4 = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "198.51.100.0/24" ];
          description = "Additional static IPv4 CIDRs added to the port-scoped country allow set.";
        };

        extraIPv6 = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "2001:db8:beef::/48" ];
          description = "Additional static IPv6 CIDRs added to the port-scoped country allow set.";
        };
      };
    };

    blocklists = {
      catalog = mkOption {
        type = types.attrsOf (types.submodule ({ ... }: {
          options = {
            url = mkOption {
              type = types.str;
              example = "https://www.spamhaus.org/drop/drop.txt";
              description = ''
                HTTP(S) endpoint that provides block entries.
                Supported line formats include plain CIDR/IP text and ipset-style `add` lines.
              '';
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
          "https://www.spamhaus.org/drop/drop.txt"
          "https://www.spamhaus.org/drop/dropv6.txt"
        ];
        description = ''
          Additional direct blocklist URLs containing CIDR/IP entries
          (plain text or ipset-style `add` lines).
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
          - ignoreIPv4
          - ignoreIPv6
          and optional metadata:
          - schemaVersion (1|2)
          - revision (string or number)
          - ttlSeconds (non-negative integer; cache age guard)
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

      authTokenFiles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "/run/secrets/nix-csf-cluster-token-current"
          "/run/secrets/nix-csf-cluster-token-next"
        ];
        description = ''
          Ordered bearer token files for cluster policy auth rotation.
          Tokens are tried in order until a request succeeds.
          Cannot be combined with clusterPolicy.authTokenFile.
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

    dynamicOffenders = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable dynamic temporary offender propagation from a remote JSON endpoint.
          Entries are materialized into timeout-based nftables sets.
        '';
      };

      url = mkOption {
        type = types.str;
        default = "";
        example = "https://policy.example.org/nix-csf/dynamic-offenders.json";
        description = ''
          Endpoint that returns a dynamic offender snapshot with optional keys:
          - schemaVersion (1)
          - revision (string or number)
          - ttlSeconds (non-negative integer; snapshot cache-age guard)
          - banIPv4
          - banIPv6

          `banIPv4` and `banIPv6` entries may be:
          - string CIDR (uses defaultEntryTTLSeconds)
          - object:
            - cidr (string, required)
            - ttlSeconds (non-negative integer, optional)
            - expiresAt (unix epoch seconds, optional)
            - reason (string, optional)
        '';
      };

      failOpen = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If true, fetch/schema/cache-age failures are tolerated and dynamic bans are skipped.
          If false, failures are fail-closed when no valid cache is available.
        '';
      };

      requireHTTPS = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Require dynamicOffenders.url to use https://.
          Disable only for controlled local/offline testing.
        '';
      };

      authTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/nix-csf-dynamic-token";
        description = ''
          Optional absolute path to a bearer token file for dynamic offender requests.
          Content is sent as Authorization: Bearer <token>.
        '';
      };

      authTokenFiles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "/run/secrets/nix-csf-dynamic-token-current"
          "/run/secrets/nix-csf-dynamic-token-next"
        ];
        description = ''
          Ordered bearer token files for dynamic offender auth rotation.
          Tokens are tried in order until a request succeeds.
          Cannot be combined with dynamicOffenders.authTokenFile.
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

      defaultEntryTTLSeconds = mkOption {
        type = types.ints.positive;
        default = 900;
        description = ''
          Fallback TTL for dynamic entries that do not provide ttlSeconds/expiresAt.
        '';
      };

      maxEntries = mkOption {
        type = types.ints.positive;
        default = 20000;
        description = ''
          Maximum number of dynamic entries accepted per snapshot (banIPv4 + banIPv6).
        '';
      };
    };

    controlPlane = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable the local nix-csf control-plane PoC service.
          This service stores mutable runtime cluster state outside nixos-rebuild-managed files
          and publishes cluster policy/dynamic offender snapshots for client nodes.
          Installs both `nix-csf-control-plane` and `nix-csfctl` tools into system packages.
        '';
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = "Bind address for the control-plane HTTP service.";
      };

      port = mkOption {
        type = types.port;
        default = 18081;
        description = "TCP port for the control-plane HTTP service.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/nix-csf-control-plane";
        description = ''
          Absolute path where mutable control-plane state is stored.
          This directory is runtime state and is not overwritten by nixos-rebuild.
        '';
      };

      environment = mkOption {
        type = types.str;
        default = "prod";
        example = "lab";
        description = ''
          Snapshot environment namespace expected in request paths:
          /snapshots/<environment>/cluster-policy.json
        '';
      };

      clusterPolicyTTLSeconds = mkOption {
        type = types.ints.positive;
        default = 300;
        description = "ttlSeconds value emitted in cluster policy snapshots.";
      };

      dynamicSnapshotTTLSeconds = mkOption {
        type = types.ints.positive;
        default = 120;
        description = "ttlSeconds value emitted in dynamic offender snapshots.";
      };

      defaultBanTTLSeconds = mkOption {
        type = types.ints.positive;
        default = 900;
        description = "Default TTL for /v1/offenders/ban-temp requests without ttlSeconds.";
      };

      requireAuth = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Require Authorization: Bearer token for snapshot and mutation endpoints.
          /healthz remains unauthenticated.
        '';
      };

      authTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/nix-csf-control-plane-token";
        description = ''
          Absolute path to bearer token used by control-plane API auth.
          Required when controlPlane.requireAuth = true.
        '';
      };

      escalation = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable automatic escalation from repeated temporary bans to permanent deny.
            Promotion target is cluster-policy deny list for the corresponding address family.
          '';
        };

        tempBanThreshold = mkOption {
          type = types.ints.positive;
          default = 5;
          description = ''
            Number of temporary-ban events for the same CIDR required to trigger promotion.
          '';
        };

        windowSeconds = mkOption {
          type = types.ints.positive;
          default = 900;
          description = ''
            Rolling window size for escalation event counting.
          '';
        };

        maxAuditEntries = mkOption {
          type = types.ints.positive;
          default = 5000;
          description = ''
            Maximum number of persisted promotion audit records in control-plane state.
          '';
        };
      };
    };

    coexistence = {
      profile = mkOption {
        type = types.enum [ "exclusive-firewall" "docker-coexist" ];
        default = "exclusive-firewall";
        description = ''
          Firewall ownership/coexistence profile:
          - exclusive-firewall: nix-csf owns host filtering posture.
          - docker-coexist: preserve Docker/dynamic daemon forwarding behavior while
            still enforcing nix-csf deny-style overlays.
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
    (mkIf cfg.controlPlane.enable {
    assertions = [
      {
        assertion = hasPrefix "/" cfg.controlPlane.dataDir;
        message = "services.nixCsf.controlPlane.dataDir must be an absolute path.";
      }
      {
        assertion = cfg.controlPlane.environment != "";
        message = "services.nixCsf.controlPlane.environment must not be empty.";
      }
      {
        assertion = !cfg.controlPlane.requireAuth || cfg.controlPlane.authTokenFile != null;
        message = ''
          services.nixCsf.controlPlane.requireAuth = true requires
          services.nixCsf.controlPlane.authTokenFile.
        '';
      }
      {
        assertion = cfg.controlPlane.authTokenFile == null || hasPrefix "/" cfg.controlPlane.authTokenFile;
        message = "services.nixCsf.controlPlane.authTokenFile must be an absolute path when set.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.controlPlane.dataDir} 0750 root root -"
    ];

    environment.systemPackages = [ controlPlaneTool controlPlaneCliTool ];

    systemd.services.nix-csf-control-plane = {
      description = "nix-csf control-plane snapshot publisher (POC)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "network.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStart = controlPlaneExecStart;
      };
    };
    })
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
        assertion = !cfg.country.portAllow.enable || cfg.country.portAllow.countries != [ ];
        message = "services.nixCsf.country.portAllow.enable requires at least one country code.";
      }
      {
        assertion = all validCountryCode cfg.country.portAllow.countries;
        message = "services.nixCsf.country.portAllow.countries entries must be ISO alpha-2 codes (e.g. US, DE).";
      }
      {
        assertion = !cfg.country.portAllow.enable
          || cfg.country.portAllow.tcpPorts != [ ]
          || cfg.country.portAllow.udpPorts != [ ];
        message = "services.nixCsf.country.portAllow.enable requires at least one TCP or UDP port.";
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
        assertion = all (path: hasPrefix "/" path) cfg.clusterPolicy.authTokenFiles;
        message = "services.nixCsf.clusterPolicy.authTokenFiles entries must be absolute paths.";
      }
      {
        assertion = cfg.clusterPolicy.authTokenFile == null || cfg.clusterPolicy.authTokenFiles == [ ];
        message = ''
          services.nixCsf.clusterPolicy.authTokenFile cannot be combined with
          services.nixCsf.clusterPolicy.authTokenFiles.
        '';
      }
      {
        assertion = !cfg.dynamicOffenders.enable || cfg.dynamicOffenders.url != "";
        message = "services.nixCsf.dynamicOffenders.enable requires dynamicOffenders.url.";
      }
      {
        assertion = !cfg.dynamicOffenders.enable
          || !cfg.dynamicOffenders.requireHTTPS
          || isHttpsUrl cfg.dynamicOffenders.url;
        message = "services.nixCsf.dynamicOffenders.url must use https:// when dynamicOffenders.requireHTTPS = true.";
      }
      {
        assertion = cfg.dynamicOffenders.authTokenFile == null || hasPrefix "/" cfg.dynamicOffenders.authTokenFile;
        message = "services.nixCsf.dynamicOffenders.authTokenFile must be an absolute path when set.";
      }
      {
        assertion = all (path: hasPrefix "/" path) cfg.dynamicOffenders.authTokenFiles;
        message = "services.nixCsf.dynamicOffenders.authTokenFiles entries must be absolute paths.";
      }
      {
        assertion = cfg.dynamicOffenders.authTokenFile == null || cfg.dynamicOffenders.authTokenFiles == [ ];
        message = ''
          services.nixCsf.dynamicOffenders.authTokenFile cannot be combined with
          services.nixCsf.dynamicOffenders.authTokenFiles.
        '';
      }
      {
        assertion = all (path: hasPrefix "/" path) allLocalPolicyFiles;
        message = ''
          services.nixCsf.localFiles allow/deny/ignore entries must be absolute paths.
        '';
      }
      {
        assertion = !cfg.localFiles.enable || allLocalPolicyFiles != [ ];
        message = ''
          services.nixCsf.localFiles.enable requires at least one file in
          services.nixCsf.localFiles.allow/deny/ignore.
        '';
      }
      {
        assertion = cfg.coexistence.profile != "docker-coexist" || cfg.forwardPolicy == "accept";
        message = ''
          services.nixCsf.coexistence.profile = "docker-coexist" requires
          services.nixCsf.forwardPolicy = "accept" to avoid breaking container forwarding.
        '';
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
      {
        assertion = !cfg.country.portAllow.enable
          || cfg.country.ipv4URLTemplate != ""
          || cfg.country.ipv6URLTemplate != null
          || cfg.country.portAllow.extraIPv4 != [ ]
          || cfg.country.portAllow.extraIPv6 != [ ];
        message = ''
          services.nixCsf.country.portAllow.enable requires at least one country data source
          (URL template or portAllow extra CIDRs).
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
