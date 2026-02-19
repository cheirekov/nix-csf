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
| External blocklists | `blocklists.catalog + blocklists.sources` (or legacy `blocklists.urls`) |
| Auto updates (`CC_INTERVAL`) | `autoRefresh.onCalendar` |

## Deferred from CSF parity

- Per-port country allow controls (`CC_ALLOW_PORTS`)
- Login failure daemon behavior (`lfd`)
- IDS/alert integrations
- Application-specific protections

These are planned as follow-up tickets in `docs/DELIVERY_BOARD.md`.
