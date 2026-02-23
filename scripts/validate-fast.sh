#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] fast validation: flake eval checks"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] fast validation: x86_64 lightweight builds (no VM tests)"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.version-semver" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-basic" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-profiles" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-control-plane" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-lfd-detector" \
  "path:${ROOT_DIR}#checks.x86_64-linux.eval-monitoring" \
  "path:${ROOT_DIR}#checks.x86_64-linux.csf-import-check" \
  "path:${ROOT_DIR}#checks.x86_64-linux.shellcheck" \
  "path:${ROOT_DIR}#checks.x86_64-linux.control-plane-lint" \
  "path:${ROOT_DIR}#checks.x86_64-linux.monitoring-pack"

echo "[nix-csf] fast validation complete"
