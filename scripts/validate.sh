#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] running flake checks (eval + lint + check definitions)"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] running x86_64 smoke test build"
nix build "path:${ROOT_DIR}#checks.x86_64-linux.nix-csf-smoke" --print-build-logs

echo "[nix-csf] validation complete"
