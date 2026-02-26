#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/validate-burnin.sh [--runs N]

Description:
  Execute repeated full operator validation runs using ./scripts/validate-capture.sh
  and write a consolidated burn-in summary under .artifacts/validate/.
EOF
}

runs=3

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --runs)
      [[ "$#" -ge 2 ]] || { echo "validate-burnin: --runs requires a value" >&2; exit 2; }
      runs="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "validate-burnin: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "${runs}" =~ ^[0-9]+$ ]] || [[ "${runs}" == "0" ]]; then
  echo "validate-burnin: --runs must be a positive integer" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifacts_dir="${repo_root}/.artifacts/validate"
mkdir -p "${artifacts_dir}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
summary_file="${artifacts_dir}/burnin-${timestamp}-summary.log"

echo "[nix-csf] burn-in start timestamp=${timestamp} runs=${runs}" | tee "${summary_file}"
echo "[nix-csf] repository=${repo_root}" | tee -a "${summary_file}"

run_index=1
while [[ "${run_index}" -le "${runs}" ]]; do
  run_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[nix-csf] burn-in run=${run_index}/${runs} start=${run_ts}" | tee -a "${summary_file}"

  set +e
  output="$("${repo_root}/scripts/validate-capture.sh" 2>&1)"
  status=$?
  set -e

  end_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "${status}" -eq 0 ]]; then
    echo "[nix-csf] burn-in run=${run_index}/${runs} result=success end=${end_ts}" | tee -a "${summary_file}"
  else
    echo "[nix-csf] burn-in run=${run_index}/${runs} result=failed end=${end_ts}" | tee -a "${summary_file}"
    echo "[nix-csf] burn-in first failure output:" | tee -a "${summary_file}"
    printf '%s\n' "${output}" | tee -a "${summary_file}"
    echo "[nix-csf] burn-in failed summary=${summary_file}" | tee -a "${summary_file}"
    exit "${status}"
  fi

  run_index=$(( run_index + 1 ))
done

echo "[nix-csf] burn-in succeeded summary=${summary_file}" | tee -a "${summary_file}"
