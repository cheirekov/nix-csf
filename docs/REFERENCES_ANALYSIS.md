# References Analysis

Reference used:

- `references/csf` (CSF source/config examples)
- `references/csf-firewall-v15.08-helpers`

## Feature mapping (initial)

| CSF concept | nix-csf baseline |
|---|---|
| `TCP_IN`, `UDP_IN` | `services.nixCsf.openTCPPorts`, `openUDPPorts` |
| `csf.allow`, `csf.deny` | `allowIPv4/allowIPv6`, `denyIPv4/denyIPv6` |
| `CC_DENY` | `country.enable + country.countries` |
| `CC_DENY_PORTS` | `country.portDeny` (`countries` + `tcpPorts`/`udpPorts`) |
| `CC_ALLOW_PORTS` | `country.portAllow` (`countries` + `tcpPorts`/`udpPorts`) |
| External blocklists | `blocklists.catalog + blocklists.sources` (or legacy `blocklists.urls`) |
| Auto updates (`CC_INTERVAL`) | `autoRefresh.onCalendar` |

## Deferred from CSF parity

- Login failure daemon behavior (`lfd`) -> baseline implemented via `T-029` (`services.nixCsf.lfdDetector.*`)
- fail2ban detector integration -> baseline implemented via `T-030` (`services.nixCsf.fail2banAdapter.*`)
- IDS/alert integrations
- Application-specific protections

## Migration Notes From Real CSF Lists (2026-02-23)

- `csf.deny` and `csf.ignore` are mostly direct CIDR/IP data sources and map well to `localFiles.deny` / `localFiles.ignore`.
- `csf.allow` includes mixed content:
  - direct CIDR/IP entries (compatible),
  - CSF advanced per-port expressions (for example `tcp|in|d=12000|s=...`) that need explicit conversion rules.
- Dedicated migration bridge (`T-028`) implemented as `nix-csf-import-csf` (`docs/CSF_IMPORT.md`).

These are planned as follow-up tickets in `docs/DELIVERY_BOARD.md`.
