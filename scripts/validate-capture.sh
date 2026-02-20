#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

OUT_DIR="${1:-${ROOT_DIR}/.artifacts/validate}"
mkdir -p "${OUT_DIR}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="${OUT_DIR}/validate-${STAMP}.log"
SUMMARY_LOG="${OUT_DIR}/validate-${STAMP}-summary.log"

echo "[nix-csf] writing full validation log to ${RUN_LOG}"
set +e
./scripts/validate.sh 2>&1 | tee "${RUN_LOG}"
rc=$?
set -e

if [[ ${rc} -ne 0 ]]; then
  {
    echo "## failure markers"
    rg -n "RequestedAssertionFailed|must succeed:|error: builder for|failed with exit code|nix-csf-controlplanepoc|nix-csf-dockercoexist|nix-csf-tokenrotation" "${RUN_LOG}" || true
    echo
    echo "## suggested next command"
    drv="$(grep -oE '/nix/store/[a-z0-9]{32}-vm-test-run-nix-csf-integration\\.drv' "${RUN_LOG}" | tail -n1 || true)"
    if [[ -n "${drv}" ]]; then
      echo "nix log ${drv}"
    else
      echo "nix log /nix/store/<...>-vm-test-run-nix-csf-integration.drv"
    fi
  } > "${SUMMARY_LOG}"

  echo "[nix-csf] validation failed, summary written to ${SUMMARY_LOG}"
  exit "${rc}"
fi

echo "[nix-csf] validation succeeded"
echo "[nix-csf] full log: ${RUN_LOG}"
