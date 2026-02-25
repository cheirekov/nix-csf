# LFD-Like Detector Framework (Nix-native, v2)

This document describes `services.nixCsf.lfdDetector`, a Nix-native detector framework that mimics CSF/LFD behavior while keeping `nix-csf` the single firewall writer.

## Goal

- Detect repeated abusive/auth-failure signals from journal sources.
- Emit temporary bans via `nix-csfctl ban-temp`.
- Keep detector logic separate from nftables rendering/apply.
- Support multiple detector definitions with independent thresholds/windows.

## How It Works

1. `nix-csf-lfd-detector.service` loads detector definitions.
2. For each enabled detector, it scans configured journal sources in a rolling window.
3. Source IPs that meet detector threshold are sent to control-plane as temporary bans.
4. If `refreshAfterBan = true`, detector starts `nix-csf-refresh.service` for faster nft enforcement.
5. Bans appear in:
   - control-plane dynamic snapshot,
   - `/var/lib/nix-csf/cache/dynamic-offenders.json`,
   - nft timeout sets (`dynamic_ban_ipv4`/`dynamic_ban_ipv6`).

## Built-in Detector Pack Example (Recommended)

```nix
services.nixCsf = {
  enable = true;

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false;

    escalation = {
      enable = true;
      tempBanThreshold = 5;
      windowSeconds = 900;
      cooldownSeconds = 1800;
      reasonClasses = [ "lfd" "fail2ban" ];
    };
  };

  dynamicOffenders = {
    enable = true;
    url = "http://127.0.0.1:18081/snapshots/lab/dynamic-offenders.json";
    requireHTTPS = false;
    failOpen = true;
  };

  lfdDetector = {
    enable = true;

    detectorPack = {
      enable = true;
      profile = "server-web"; # ssh-auth + nginx-auth

      # Optional per-detector tuning:
      sshAuth = {
        threshold = 5;
        windowSeconds = 300;
        banTTLSeconds = 900;
      };
      nginxAuth = {
        threshold = 10;
        windowSeconds = 300;
        banTTLSeconds = 900;
      };
    };

    refreshAfterBan = true;

    schedule = {
      onCalendar = "minutely";
      randomDelaySec = "15s";
      persistent = true;
    };

    metrics = {
      enable = true;
      outputFile = "/var/lib/nix-csf/lfd-detector.prom";
    };
  };
};
```

## Custom Detectors Example (Advanced)

Use explicit detector definitions when you need non-curated service patterns.

```nix
services.nixCsf.lfdDetector = {
  enable = true;

  detectors = [
    {
      name = "ssh-auth";
      journalIdentifier = "sshd";
      lineContains = "Failed password";
      threshold = 5;
      windowSeconds = 300;
      banTTLSeconds = 900;
      reason = "lfd:sshd_failed_login";
    }
    {
      name = "app-auth";
      journalIdentifier = "app-auth";
      lineContains = "auth failed";
      extractRegex = "from ([0-9A-Fa-f:.]+)";
      threshold = 10;
      windowSeconds = 300;
      banTTLSeconds = 600;
      reason = "lfd:app_auth_failed";
    }
  ];
};
```

## Legacy Compatibility

Legacy single-detector fields remain supported:

- `lfdDetector.sshdUnit`
- `lfdDetector.journalIdentifier`
- `lfdDetector.windowSeconds`
- `lfdDetector.threshold`
- `lfdDetector.banTTLSeconds`
- `lfdDetector.reason`

When `lfdDetector.detectors` is non-empty, or `lfdDetector.detectorPack.enable = true`,
these legacy fields are fallback-only and ignored for runtime detector generation.

## Operational Checks

```bash
sudo systemctl status nix-csf-lfd-detector.timer --no-pager
sudo systemctl start nix-csf-lfd-detector.service
sudo systemctl status nix-csf-lfd-detector.service --no-pager
sudo journalctl -u nix-csf-lfd-detector.service -n 120 --no-pager
sudo cat /var/lib/nix-csf/lfd-detector.prom
```

Inspect applied runtime state:

```bash
sudo grep -F 'dynamic_ban' /var/lib/nix-csf/generated-ruleset.nft
sudo nft list set inet nix_csf dynamic_ban_ipv4
sudo nft list set inet nix_csf dynamic_ban_ipv6
```

## Assertions/Guardrails

When enabled:

- `services.nixCsf.dynamicOffenders.enable` is required.
- `lfdDetector.detectors` cannot be combined with `lfdDetector.detectorPack.enable = true`.
- at least one enabled detector must resolve.
- each enabled detector requires at least one source:
  - `journalUnit`, or
  - `journalIdentifier`.
- if `lfdDetector.endpoint` is not set, `services.nixCsf.controlPlane.enable = true` is required.

## Notes

- Detector emits mutations only; nft rules are still rendered/applied by `nix-csf`.
- Escalation (`N` temp bans => permanent deny) remains controlled by `services.nixCsf.controlPlane.escalation.*`.
- Escalation audit metadata (promotion `id`, `reasonClass`, `cooldown*`) is available via
  `nix-csfctl promotions --limit N`.
- fail2ban adapter/coexistence is available via `services.nixCsf.fail2banAdapter.*`
  (`docs/FAIL2BAN_ADAPTER.md`).
