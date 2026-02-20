#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] running flake checks (eval + lint + check definitions)"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] running x86_64 lightweight checks (version + eval + profile eval + control-plane eval + monitoring eval + shellcheck + control-plane lint + monitoring pack)"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.version-semver" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-basic" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-profiles" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-control-plane" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-monitoring" \
  "path:${ROOT_DIR}#checks.x86_64-linux.shellcheck" \
  "path:${ROOT_DIR}#checks.x86_64-linux.control-plane-lint" \
  "path:${ROOT_DIR}#checks.x86_64-linux.monitoring-pack"

echo "[nix-csf] running x86_64 VM test builds (smoke + integration)"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-smoke" \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-integration" \
  --print-build-logs

echo "[nix-csf] validation complete"
