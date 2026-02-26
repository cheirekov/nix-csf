# Security Validation and Pen-Test Runbook

Last updated: 2026-02-26  
Owners: Security Architect + QA/Release Engineer

Purpose: provide reproducible hardening checks for pre-release and production change validation.

## 1) Scope

This runbook validates:

- exposed ingress surface,
- DNS flood control behavior,
- control-plane auth abuse handling,
- detector pipeline reaction to auth-failure signals,
- CI mutation cleanup safety.

It is intentionally operational and command-driven.

## 2) Preconditions

- `services.nixCsf.enable = true` and host deployed.
- `networking.firewall.enable = false` (nix-csf is the active writer).
- operator has root/sudo access.
- tools available on test runner:
  - `nmap`
  - `hping3`
  - `curl`
  - `jq`

Recommended:

- run from a dedicated lab source host on the same management network.
- keep production pressure tests conservative.

## 3) Baseline evidence snapshot

Run on target host before tests:

```bash
sudo systemctl show -P Result nix-csf-apply.service
sudo systemctl show -P Result nix-csf-refresh.service
sudo nft list table inet nix_csf > /tmp/nix-csf-table-before.txt
sudo cp /var/lib/nix-csf/generated-ruleset.nft /tmp/nix-csf-ruleset-before.nft
sudo cp /var/lib/nix-csf/metrics.prom /tmp/nix-csf-metrics-before.prom
```

Pass condition:

- apply/refresh result is `success`.

## 4) Ingress surface scan (`nmap`)

Run from lab runner:

```bash
nmap -Pn -sS -sU -p 22,53,80,112,443,8448 <target-ip>
```

Pass condition:

- only expected ports are reachable per target policy.
- unexpected open ports are triaged as `P0` or `P1`.

## 5) DNS flood control check (`hping3`)

Run only if DNS service is intentionally exposed.

UDP pressure:

```bash
sudo hping3 --udp -p 53 --flood --rand-source -c 20000 <target-ip>
```

TCP SYN pressure:

```bash
sudo hping3 -S -p 53 --flood --rand-source -c 20000 <target-ip>
```

Target-side checks:

```bash
sudo grep -E 'dns_(udp|tcp)_flood' /var/lib/nix-csf/generated-ruleset.nft
sudo grep -E 'nix_csf_feature_enabled\\{feature="dns_flood"\\} 1' /var/lib/nix-csf/metrics.prom
```

Pass condition:

- DNS flood meter rules are present when enabled.
- no service/systemd instability during test window.

## 6) Control-plane auth abuse replay

Run from lab runner (invalid token):

```bash
curl -sS -o /tmp/cp-auth-fail.out -w '%{http_code}\n' \
  -H 'Authorization: Bearer invalid-token' \
  https://fw-master.example.org/snapshots/prod/cluster-policy.json
```

Expected HTTP status: `401`.

Target-side checks:

```bash
sudo journalctl -u nix-csf-control-plane.service -n 120 --no-pager
sudo systemctl show -P Result nix-csf-control-plane.service
```

Pass condition:

- requests are denied (`401`) with no control-plane crash.

## 7) Detector template auth-failure path (`T-056`)

If detector pack has auth-failure templates enabled:

```nix
services.nixCsf.lfdDetector.detectorPack = {
  enable = true;
  controlPlaneAuth.enable = true;
  apiProxyAuth.enable = true;
};
```

Trigger auth failures (from runner), then run detector:

```bash
sudo systemctl start nix-csf-lfd-detector.service
sudo systemctl show -P Result nix-csf-lfd-detector.service
sudo journalctl -u nix-csf-lfd-detector.service -n 160 --no-pager
```

Pass condition:

- detector service exits successfully,
- auth-failure detectors are evaluated,
- resulting temp ban mutations are visible in control-plane and nft dynamic sets when threshold is met.

## 8) CI temporary allow/remove cleanup test

Dry-run style workflow:

```bash
RUNNER_CIDR="<runner-ip>/32"
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf-control-plane-token policy add allow "${RUNNER_CIDR}" --scope local --node-id ci-test --source ci
nix-csfctl --endpoint https://fw-master.example.org --auth-token-file /run/secrets/nix-csf-control-plane-token policy remove allow "${RUNNER_CIDR}" --scope local --node-id ci-test --source ci
```

Pass condition:

- add/remove both succeed,
- cleanup is idempotent and leaves no stale local CI allow entry.

## 9) Result classification

- `PASS`: all required checks satisfy expected outcomes.
- `FAIL-P0`: lockout or unauthorized exposure.
- `FAIL-P1`: major functional regression without immediate lockout.
- `FAIL-P2`: observability/doc mismatch or non-critical workflow defect.

## 10) Evidence bundle

Store artifacts per run:

```bash
mkdir -p .artifacts/security/$(date -u +%Y%m%dT%H%M%SZ)
```

Minimum attachments:

- `nmap` output,
- `hping3` command transcripts,
- control-plane and detector journal snippets,
- nft ruleset snapshot before/after,
- metrics snapshot before/after.

## 11) Safety notes

- execute flood tests only in controlled windows.
- never run unbounded high-rate tests against shared production links.
- coordinate with DNS/application owners before pressure tests.
