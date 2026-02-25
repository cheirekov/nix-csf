#!/usr/bin/env bash
set -u -o pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csf-triage [--output <path>] [--journal-lines <N>] [--metrics-file <path>] [--artifacts-dir <path>] [--no-nft]

Collects a troubleshooting snapshot for nix-csf services, cache, ruleset, and metrics.

Options:
  --output <path>        Write output to file (also echoed to stdout).
  --journal-lines <N>    Number of journal lines per unit (default: 120).
  --metrics-file <path>  Metrics file path (default: /var/lib/nix-csf/metrics.prom).
  --artifacts-dir <path> Optional validate artifact directory with summary logs.
  --no-nft               Skip 'nft list table inet nix_csf' snapshot.
  -h, --help             Show help.
EOF
}

output_file=""
journal_lines="120"
metrics_file="/var/lib/nix-csf/metrics.prom"
artifacts_dir=""
include_nft="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    --journal-lines)
      journal_lines="${2:-}"
      shift 2
      ;;
    --metrics-file)
      metrics_file="${2:-}"
      shift 2
      ;;
    --artifacts-dir)
      artifacts_dir="${2:-}"
      shift 2
      ;;
    --no-nft)
      include_nft="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "nix-csf-triage: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "${output_file}" ]]; then
  mkdir -p "$(dirname "${output_file}")"
  : > "${output_file}"
  exec > >(tee -a "${output_file}") 2>&1
fi

if ! [[ "${journal_lines}" =~ ^[0-9]+$ ]] || [[ "${journal_lines}" -lt 1 ]]; then
  echo "nix-csf-triage: --journal-lines must be a positive integer" >&2
  exit 1
fi

section() {
  local title="$1"
  printf '\n## %s\n' "${title}"
}

run_shell() {
  local label="$1"
  local cmd="$2"
  local rc

  printf '\n### %s\n' "${label}"
  printf '$ %s\n' "${cmd}"
  bash -o pipefail -c "${cmd}"
  rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    printf '[exit %s]\n' "${rc}"
  fi
}

echo "# nix-csf triage report"
echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "Host"
run_shell "identity" "id"
run_shell "kernel" "uname -a"
run_shell "nix version" "nix --version"

section "Service Status"
run_shell "nix-csf-apply service status" "systemctl status nix-csf-apply.service --no-pager || true"
run_shell "nix-csf-refresh service status" "systemctl status nix-csf-refresh.service --no-pager || true"
run_shell "nix-csf-refresh timer status" "systemctl status nix-csf-refresh.timer --no-pager || true"
run_shell "nix-csf-control-plane service status" "systemctl status nix-csf-control-plane.service --no-pager || true"
run_shell "unit result summary" "for u in nix-csf-apply.service nix-csf-refresh.service nix-csf-control-plane.service; do printf '%s: ' \"\$u\"; systemctl show -P ActiveState -P SubState -P Result -P ExecMainStatus \"\$u\" 2>/dev/null | paste -sd ',' - || true; done"

section "Recent Journals"
run_shell "journal: nix-csf-apply" "journalctl -u nix-csf-apply.service -n ${journal_lines} --no-pager || true"
run_shell "journal: nix-csf-refresh" "journalctl -u nix-csf-refresh.service -n ${journal_lines} --no-pager || true"
run_shell "journal: nix-csf-control-plane" "journalctl -u nix-csf-control-plane.service -n ${journal_lines} --no-pager || true"

section "State Files"
run_shell "state directory listing" "ls -lah /var/lib/nix-csf /var/lib/nix-csf/cache 2>/dev/null || true"
run_shell "cache file timestamps" "for f in /var/lib/nix-csf/cache/*.json; do [ -e \"\$f\" ] || continue; stat -c '%y %s %n' \"\$f\"; done"
run_shell "generated ruleset key lines" "grep -nE 'table ip nix_csf_nat|dnat to|masquerade|chain input|chain forward|chain output|country_port_allow|country_port_deny|country_ipv|feed_ipv|dynamic_ban|egress_|forwarding|coexist' /var/lib/nix-csf/generated-ruleset.nft 2>/dev/null || true"

if [[ "${include_nft}" == "true" ]]; then
  section "NFT Snapshot"
  run_shell "nft list table inet nix_csf" "nft list table inet nix_csf 2>/dev/null || true"
fi

section "Metrics"
run_shell "metrics file metadata" "ls -lah \"${metrics_file}\" 2>/dev/null || true"
run_shell "metrics key lines" "if [[ -r \"${metrics_file}\" ]]; then grep -E 'nix_csf_(last_run_success|last_run_duration_seconds|feature_enabled|set_entries|source_count|cluster_policy_cache_expired|dynamic_snapshot_cache_expired|auth_token_selected_slot)' \"${metrics_file}\" || true; else echo 'metrics file not readable'; fi"

if [[ -n "${artifacts_dir}" ]]; then
  section "Validation Artifacts"
  run_shell "artifact directory listing" "ls -lah \"${artifacts_dir}\" 2>/dev/null || true"
  run_shell "latest summary log tail" "latest=\$(ls -1t \"${artifacts_dir}\"/validate-*-summary.log 2>/dev/null | head -n 1); if [[ -n \"\$latest\" ]]; then echo \"latest_summary=\$latest\"; tail -n 120 \"\$latest\"; else echo 'no summary logs found'; fi"
fi

section "Done"
if [[ -n "${output_file}" ]]; then
  echo "triage_output=${output_file}"
else
  echo "triage_output=stdout"
fi
