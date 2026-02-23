# LFD-Like Detector (Nix-native)

This document describes `services.nixCsf.lfdDetector`, a Nix-native detector path that mimics core CSF/LFD behavior for SSH brute-force signals.

## Goal

- Detect repeated SSH authentication failures.
- Emit temporary bans via `nix-csfctl ban-temp`.
- Keep `nix-csf` as the single firewall writer.
- Reuse existing control-plane + dynamic snapshot pipeline.

## How It Works

1. `nix-csf-lfd-detector.service` scans journal events in a rolling window.
2. Source IPs that hit `threshold` are sent to control-plane as temporary bans.
3. If `refreshAfterBan = true`, detector starts `nix-csf-refresh.service` to apply updates quickly.
4. Bans appear in:
   - control-plane dynamic snapshot,
   - `/var/lib/nix-csf/cache/dynamic-offenders.json`,
   - nft timeout sets (`dynamic_ban_ipv4`/`dynamic_ban_ipv6`).

## Example

```nix
services.nixCsf = {
  enable = true;

  controlPlane = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 18081;
    environment = "lab";
    requireAuth = false;

    # Optional promotion policy (existing feature):
    escalation = {
      enable = true;
      tempBanThreshold = 5;
      windowSeconds = 900;
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

    # Journal sources (at least one required)
    journalIdentifier = "sshd";
    # sshdUnit = "sshd.service";

    windowSeconds = 300;
    threshold = 5;
    banTTLSeconds = 900;
    reason = "lfd:sshd_failed_login";

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

## Operational Checks

```bash
sudo systemctl status nix-csf-lfd-detector.timer --no-pager
sudo systemctl start nix-csf-lfd-detector.service
sudo systemctl status nix-csf-lfd-detector.service --no-pager
sudo journalctl -u nix-csf-lfd-detector.service -n 80 --no-pager
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
- at least one journal source must be configured:
  - `lfdDetector.sshdUnit`, or
  - `lfdDetector.journalIdentifier`.
- if `lfdDetector.endpoint` is not set, `services.nixCsf.controlPlane.enable = true` is required.

## Notes

- This is detector-only logic; nft rules are still rendered/applied by `nix-csf`.
- Escalation (`N` temp bans => permanent deny) remains controlled by `services.nixCsf.controlPlane.escalation.*`.
- fail2ban adapter/coexistence is available via `services.nixCsf.fail2banAdapter.*`
  (`docs/FAIL2BAN_ADAPTER.md`).
