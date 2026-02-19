#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] running flake checks (eval + lint + check definitions)"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] running x86_64 VM test builds (smoke + integration)"
nix build \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-smoke" \
  "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-integration" \
  --print-build-logs

echo "[nix-csf] validation complete"
