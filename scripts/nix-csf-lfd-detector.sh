#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csf-lfd-detector [options]

Options:
  --sshd-unit UNIT          systemd unit to inspect (default: unset)
  --journal-identifier TAG  syslog identifier to inspect (default: sshd)
  --window-seconds N        rolling detection window in seconds (default: 300)
  --threshold N             failures per source IP required to trigger ban (default: 5)
  --ban-ttl-seconds N       temporary ban TTL in seconds (default: 900)
  --reason TEXT             reason sent to control-plane (default: lfd:sshd_failed_login)
  --endpoint URL            nix-csf control-plane endpoint (default: http://127.0.0.1:18081)
  --auth-token-file PATH    bearer token file for authenticated control-plane APIs
  --refresh-after-ban       start nix-csf-refresh.service when at least one ban changed
  --metrics-file PATH       write detector metrics to Prometheus textfile format
  --lock-file PATH          lock file path to prevent concurrent runs
  -h, --help                show this help
EOF
}

fail() {
  echo "nix-csf-lfd-detector: ERROR: $*" >&2
  exit 1
}

warn() {
  echo "nix-csf-lfd-detector: WARNING: $*" >&2
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" == "0" ]]; then
    fail "${name} must be a positive integer"
  fi
}

normalize_cidr() {
  local ip="$1"
  if [[ "${ip}" == *:* ]]; then
    printf '%s/128\n' "${ip}"
  else
    printf '%s/32\n' "${ip}"
  fi
}

extract_source_ip() {
  local line="$1"
  if [[ "${line}" =~ [Ff]ailed[[:space:]](password|publickey).*[[:space:]]from[[:space:]]([0-9A-Fa-f:.]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "${line}" =~ rhost=([0-9A-Fa-f:.]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

sshd_unit=""
journal_identifier="sshd"
window_seconds="300"
threshold="5"
ban_ttl_seconds="900"
reason="lfd:sshd_failed_login"
endpoint="http://127.0.0.1:18081"
auth_token_file=""
refresh_after_ban="false"
metrics_file=""
lock_file="/run/nix-csf-lfd-detector.lock"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --sshd-unit)
      [[ "$#" -ge 2 ]] || fail "--sshd-unit requires a value"
      sshd_unit="$2"
      shift 2
      ;;
    --journal-identifier)
      [[ "$#" -ge 2 ]] || fail "--journal-identifier requires a value"
      journal_identifier="$2"
      shift 2
      ;;
    --window-seconds)
      [[ "$#" -ge 2 ]] || fail "--window-seconds requires a value"
      window_seconds="$2"
      shift 2
      ;;
    --threshold)
      [[ "$#" -ge 2 ]] || fail "--threshold requires a value"
      threshold="$2"
      shift 2
      ;;
    --ban-ttl-seconds)
      [[ "$#" -ge 2 ]] || fail "--ban-ttl-seconds requires a value"
      ban_ttl_seconds="$2"
      shift 2
      ;;
    --reason)
      [[ "$#" -ge 2 ]] || fail "--reason requires a value"
      reason="$2"
      shift 2
      ;;
    --endpoint)
      [[ "$#" -ge 2 ]] || fail "--endpoint requires a value"
      endpoint="$2"
      shift 2
      ;;
    --auth-token-file)
      [[ "$#" -ge 2 ]] || fail "--auth-token-file requires a value"
      auth_token_file="$2"
      shift 2
      ;;
    --refresh-after-ban)
      refresh_after_ban="true"
      shift
      ;;
    --metrics-file)
      [[ "$#" -ge 2 ]] || fail "--metrics-file requires a value"
      metrics_file="$2"
      shift 2
      ;;
    --lock-file)
      [[ "$#" -ge 2 ]] || fail "--lock-file requires a value"
      lock_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

validate_positive_int "${window_seconds}" "window-seconds"
validate_positive_int "${threshold}" "threshold"
validate_positive_int "${ban_ttl_seconds}" "ban-ttl-seconds"

if [[ -n "${auth_token_file}" ]]; then
  [[ "${auth_token_file}" == /* ]] || fail "--auth-token-file must be an absolute path"
  [[ -f "${auth_token_file}" ]] || fail "token file not found: ${auth_token_file}"
fi

if [[ -n "${metrics_file}" ]]; then
  [[ "${metrics_file}" == /* ]] || fail "--metrics-file must be an absolute path"
fi

mkdir -p "$(dirname "${lock_file}")"
exec 9>"${lock_file}"
if ! flock -n 9; then
  echo "nix-csf-lfd-detector: another run is active; skipping"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

now_epoch="$(date +%s)"
since_epoch="$((now_epoch - window_seconds))"
journal_file="${tmp_dir}/journal.log"

if [[ -z "${sshd_unit}" && -z "${journal_identifier}" ]]; then
  fail "at least one of --sshd-unit or --journal-identifier must be set"
fi
: > "${journal_file}"
if [[ -n "${sshd_unit}" ]]; then
  if ! journalctl --no-pager --quiet --unit "${sshd_unit}" --since "@${since_epoch}" -o cat >> "${journal_file}"; then
    warn "failed to read journal for unit ${sshd_unit}; continuing"
  fi
fi
if [[ -n "${journal_identifier}" ]]; then
  if ! journalctl --no-pager --quiet --identifier "${journal_identifier}" --since "@${since_epoch}" -o cat >> "${journal_file}"; then
    warn "failed to read journal for identifier ${journal_identifier}; continuing"
  fi
fi

declare -A fail_counts=()
observed_failures="0"

while IFS= read -r line; do
  source_ip=""
  if source_ip="$(extract_source_ip "${line}")"; then
    observed_failures="$((observed_failures + 1))"
    fail_counts["${source_ip}"]="$(( ${fail_counts["${source_ip}"]:-0} + 1 ))"
  fi
done < "${journal_file}"

candidate_ips="0"
ban_requests="0"
ban_changed="0"
ban_failures="0"
escalated_count="0"

for source_ip in "${!fail_counts[@]}"; do
  if (( fail_counts["${source_ip}"] < threshold )); then
    continue
  fi

  candidate_ips="$((candidate_ips + 1))"
  cidr="$(normalize_cidr "${source_ip}")"
  ban_requests="$((ban_requests + 1))"

  cmd=(nix-csfctl --endpoint "${endpoint}" --output json)
  if [[ -n "${auth_token_file}" ]]; then
    cmd+=(--auth-token-file "${auth_token_file}")
  fi
  cmd+=(ban-temp "${cidr}" --ttl "${ban_ttl_seconds}" --reason "${reason}")

  response_file="${tmp_dir}/ban-${candidate_ips}.json"
  error_file="${tmp_dir}/ban-${candidate_ips}.err"
  if "${cmd[@]}" > "${response_file}" 2> "${error_file}"; then
    changed_value="$(jq -r '.changed // false' "${response_file}" 2>/dev/null || echo "false")"
    escalated_value="$(jq -r '.escalation.escalated // false' "${response_file}" 2>/dev/null || echo "false")"

    if [[ "${changed_value}" == "true" ]]; then
      ban_changed="$((ban_changed + 1))"
    fi
    if [[ "${escalated_value}" == "true" ]]; then
      escalated_count="$((escalated_count + 1))"
    fi

    echo "nix-csf-lfd-detector: unit=${sshd_unit:-none} identifier=${journal_identifier:-none} ip=${source_ip} count=${fail_counts["${source_ip}"]} cidr=${cidr} changed=${changed_value} escalated=${escalated_value}"
  else
    ban_failures="$((ban_failures + 1))"
    warn "ban-temp request failed for ${cidr}: $(tr '\n' ' ' < "${error_file}")"
  fi
done

if [[ "${refresh_after_ban}" == "true" && "${ban_changed}" -gt 0 ]]; then
  if systemctl start nix-csf-refresh.service; then
    echo "nix-csf-lfd-detector: started nix-csf-refresh.service after ${ban_changed} changed ban(s)"
  else
    warn "failed to start nix-csf-refresh.service after detector updates"
  fi
fi

if [[ -n "${metrics_file}" ]]; then
  mkdir -p "$(dirname "${metrics_file}")"
  metrics_tmp="${tmp_dir}/metrics.prom"
  cat > "${metrics_tmp}" <<EOF
# HELP nix_csf_lfd_detector_last_run_success Detector run success status (1=success, 0=errors occurred).
# TYPE nix_csf_lfd_detector_last_run_success gauge
nix_csf_lfd_detector_last_run_success $(if [[ "${ban_failures}" -eq 0 ]]; then echo 1; else echo 0; fi)
# HELP nix_csf_lfd_detector_observed_failures SSH failure lines observed in the scan window.
# TYPE nix_csf_lfd_detector_observed_failures gauge
nix_csf_lfd_detector_observed_failures ${observed_failures}
# HELP nix_csf_lfd_detector_candidate_ips Source IPs meeting threshold.
# TYPE nix_csf_lfd_detector_candidate_ips gauge
nix_csf_lfd_detector_candidate_ips ${candidate_ips}
# HELP nix_csf_lfd_detector_ban_requests Ban requests sent to control-plane.
# TYPE nix_csf_lfd_detector_ban_requests gauge
nix_csf_lfd_detector_ban_requests ${ban_requests}
# HELP nix_csf_lfd_detector_ban_changed Ban requests that changed dynamic state.
# TYPE nix_csf_lfd_detector_ban_changed gauge
nix_csf_lfd_detector_ban_changed ${ban_changed}
# HELP nix_csf_lfd_detector_ban_failures Ban requests that failed.
# TYPE nix_csf_lfd_detector_ban_failures gauge
nix_csf_lfd_detector_ban_failures ${ban_failures}
# HELP nix_csf_lfd_detector_escalated Bans that returned escalation=true.
# TYPE nix_csf_lfd_detector_escalated gauge
nix_csf_lfd_detector_escalated ${escalated_count}
# HELP nix_csf_lfd_detector_window_seconds Detector scan window in seconds.
# TYPE nix_csf_lfd_detector_window_seconds gauge
nix_csf_lfd_detector_window_seconds ${window_seconds}
# HELP nix_csf_lfd_detector_threshold Detector threshold used for this run.
# TYPE nix_csf_lfd_detector_threshold gauge
nix_csf_lfd_detector_threshold ${threshold}
EOF
  install -m 0644 "${metrics_tmp}" "${metrics_file}"
fi

echo "nix-csf-lfd-detector: run complete unit=${sshd_unit:-none} identifier=${journal_identifier:-none} observed_failures=${observed_failures} candidate_ips=${candidate_ips} ban_requests=${ban_requests} ban_changed=${ban_changed} ban_failures=${ban_failures} escalated=${escalated_count}"
