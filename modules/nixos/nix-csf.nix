{ config, lib, pkgs, ... }:
let
  inherit (lib)
    all
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    toUpper;

  cfg = config.services.nixCsf;

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
    country = {
      enable = cfg.country.enable;
      countries = map toUpper cfg.country.countries;
      ipv4URLTemplate = cfg.country.ipv4URLTemplate;
      ipv6URLTemplate = cfg.country.ipv6URLTemplate;
      failOpen = cfg.country.failOpen;
      extraIPv4 = cfg.country.extraIPv4;
      extraIPv6 = cfg.country.extraIPv6;
    };
    blocklists = {
      enable = cfg.blocklists.enable;
      urls = cfg.blocklists.urls;
      failOpen = cfg.blocklists.failOpen;
    };
  };

  validCountryCode = cc: builtins.match "^[A-Z]{2}$" (toUpper cc) != null;
in
{
  options.services.nixCsf = {
    enable = mkEnableOption "CSF-inspired nftables firewall with NixOS-native options";

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

    country = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable country-based deny list feeds.";
      };

      countries = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "CN" "RU" ];
        description = "ISO-3166 alpha-2 country codes to deny.";
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
    };

    blocklists = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable remote blocklist URL ingestion.";
      };

      urls = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "https://www.spamhaus.org/drop/drop_v4.txt"
          "https://www.spamhaus.org/drop/drop_v6.txt"
        ];
        description = "Remote blocklist URLs containing CIDR entries.";
      };

      failOpen = mkOption {
        type = types.bool;
        default = true;
        description = "Same behavior as country.failOpen, but for blocklist URLs.";
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

  config = mkIf cfg.enable {
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
        assertion = !cfg.blocklists.enable || cfg.blocklists.urls != [ ];
        message = "services.nixCsf.blocklists.enable requires at least one URL.";
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
  };
}
