#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] agent validation: shell syntax"
for script in scripts/*.sh; do
  bash -n "${script}"
done

echo "[nix-csf] agent validation: python syntax"
python3 -m py_compile scripts/nix-csf-control-plane.py

echo "[nix-csf] agent validation: flake eval checks (no build)"
nix flake check "path:${ROOT_DIR}" --all-systems --no-build

echo "[nix-csf] agent validation complete"
