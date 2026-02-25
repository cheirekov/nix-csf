#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[nix-csf] validate-fast now delegates to validate-agent (no nix build)"
exec "${ROOT_DIR}/scripts/validate-agent.sh"
