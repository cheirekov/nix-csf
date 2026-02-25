#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] full validation lane (operator/manual): includes nix build + VM tests"

echo "[nix-csf] running flake checks (eval + lint + check definitions)"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] running x86_64 lightweight checks (version + eval + profile eval + netdata eval + control-plane eval + lfd detector eval + fail2ban adapter eval + monitoring eval + csf import check + shellcheck + control-plane lint + monitoring pack)"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.version-semver" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-basic" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-profiles" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-netdata" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-control-plane" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-lfd-detector" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-fail2ban-adapter" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-monitoring" \
  "path:${ROOT_DIR}#checks.x86_64-linux.csf-import-check" \
  "path:${ROOT_DIR}#checks.x86_64-linux.shellcheck" \
  "path:${ROOT_DIR}#checks.x86_64-linux.control-plane-lint" \
  "path:${ROOT_DIR}#checks.x86_64-linux.monitoring-pack"

echo "[nix-csf] running x86_64 VM test builds (smoke + integration)"
echo "[nix-csf] running x86_64 smoke VM test build"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-smoke" \
  --print-build-logs \
  --max-jobs 1

echo "[nix-csf] running x86_64 integration VM test build"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-integration" \
  --print-build-logs \
  --max-jobs 1

echo "[nix-csf] validation complete"
