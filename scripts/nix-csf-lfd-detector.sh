#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE_EOF'
Usage:
  nix-csf-lfd-detector [options]

Options:
  --detectors-file PATH      JSON file with detector definitions (v2 framework mode)

Legacy single-detector options (used when --detectors-file is not provided):
  --sshd-unit UNIT           systemd unit to inspect (default: unset)
  --journal-identifier TAG   syslog identifier to inspect (default: sshd)
  --window-seconds N         rolling detection window in seconds (default: 300)
  --threshold N              failures per source IP required to trigger ban (default: 5)
  --ban-ttl-seconds N        temporary ban TTL in seconds (default: 900)
  --reason TEXT              reason sent to control-plane (default: lfd:sshd_failed_login)

Common options:
  --endpoint URL             nix-csf control-plane endpoint (default: http://127.0.0.1:18081)
  --auth-token-file PATH     bearer token file for authenticated control-plane APIs
  --refresh-after-ban        start nix-csf-refresh.service when at least one ban changed
  --metrics-file PATH        write detector metrics to Prometheus textfile format
  --lock-file PATH           lock file path to prevent concurrent runs
  -h, --help                 show this help
USAGE_EOF
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

validate_detector_name() {
  local value="$1"
  if [[ -z "${value}" ]]; then
    fail "detector.name must be non-empty"
  fi
  if [[ ! "${value}" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    fail "detector.name contains invalid token: ${value}"
  fi
}

validate_bool_token() {
  local value="$1"
  local name="$2"
  if [[ "${value}" != "true" && "${value}" != "false" ]]; then
    fail "${name} must be true or false"
  fi
}

validate_regex_token() {
  local regex="$1"
  local name="$2"

  if [[ -z "${regex}" ]]; then
    return 0
  fi

  if [[ "test" =~ ${regex} ]]; then
    return 0
  fi

  local rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    fail "${name} is not a valid regex: ${regex}"
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

extract_source_ip_default() {
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

extract_source_ip_regex() {
  local line="$1"
  local regex="$2"

  if [[ "${line}" =~ ${regex} ]]; then
    if [[ -n "${BASH_REMATCH[1]:-}" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  fi

  return 1
}

escape_prometheus_label() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

detectors_file=""
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
    --detectors-file)
      [[ "$#" -ge 2 ]] || fail "--detectors-file requires a value"
      detectors_file="$2"
      shift 2
      ;;
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

validate_bool_token "${refresh_after_ban}" "refresh-after-ban"

if [[ -n "${detectors_file}" ]]; then
  [[ "${detectors_file}" == /* ]] || fail "--detectors-file must be an absolute path"
  [[ -f "${detectors_file}" ]] || fail "detectors file not found: ${detectors_file}"
  if ! jq -e 'type == "array" and length > 0' "${detectors_file}" >/dev/null 2>&1; then
    fail "--detectors-file must contain a non-empty JSON array"
  fi
  runtime_detectors_file="${detectors_file}"
else
  validate_positive_int "${window_seconds}" "window-seconds"
  validate_positive_int "${threshold}" "threshold"
  validate_positive_int "${ban_ttl_seconds}" "ban-ttl-seconds"

  if [[ -z "${sshd_unit}" && -z "${journal_identifier}" ]]; then
    fail "at least one of --sshd-unit or --journal-identifier must be set"
  fi

  runtime_detectors_file="${tmp_dir}/legacy-detectors.json"
  jq -n \
    --arg unit "${sshd_unit}" \
    --arg identifier "${journal_identifier}" \
    --argjson window "${window_seconds}" \
    --argjson threshold_value "${threshold}" \
    --argjson ttl "${ban_ttl_seconds}" \
    --arg reason_value "${reason}" '
      [
        {
          name: "legacy-sshd",
          enable: true,
          journalUnit: (if $unit == "" then null else $unit end),
          journalIdentifier: (if $identifier == "" then null else $identifier end),
          lineContains: null,
          extractRegex: null,
          windowSeconds: $window,
          threshold: $threshold_value,
          banTTLSeconds: $ttl,
          reason: $reason_value
        }
      ]
    ' > "${runtime_detectors_file}"
fi

now_epoch="$(date +%s)"

declare -a detector_rows=()
mapfile -t detector_rows < <(jq -r '.[] | @base64' "${runtime_detectors_file}")

if [[ "${#detector_rows[@]}" -eq 0 ]]; then
  fail "no detectors were resolved"
fi

total_detectors="0"
enabled_detectors="0"
observed_failures="0"
candidate_ips="0"
ban_requests="0"
ban_changed="0"
ban_failures="0"
escalated_count="0"

# shellcheck disable=SC2034
declare -a per_detector_metrics=()

declare -A detector_name_seen=()

detector_index="0"
for row in "${detector_rows[@]}"; do
  detector_index="$((detector_index + 1))"
  total_detectors="$((total_detectors + 1))"

  detector_json="$(printf '%s' "${row}" | base64 --decode)"
  detector_name="$(jq -r '.name // ""' <<< "${detector_json}")"
  detector_enabled="$(jq -r 'if .enable == null then true else .enable end | tostring' <<< "${detector_json}")"
  detector_journal_unit="$(jq -r '.journalUnit // ""' <<< "${detector_json}")"
  detector_journal_identifier="$(jq -r '.journalIdentifier // ""' <<< "${detector_json}")"
  detector_line_contains="$(jq -r '.lineContains // ""' <<< "${detector_json}")"
  detector_extract_regex="$(jq -r '.extractRegex // ""' <<< "${detector_json}")"
  detector_window_seconds="$(jq -r '(.windowSeconds // 300) | tostring' <<< "${detector_json}")"
  detector_threshold="$(jq -r '(.threshold // 5) | tostring' <<< "${detector_json}")"
  detector_ban_ttl_seconds="$(jq -r '(.banTTLSeconds // 900) | tostring' <<< "${detector_json}")"
  detector_reason="$(jq -r '.reason // "lfd:detector"' <<< "${detector_json}")"

  validate_detector_name "${detector_name}"
  validate_bool_token "${detector_enabled}" "detector.enable (${detector_name})"

  if [[ -n "${detector_name_seen["${detector_name}"]:-}" ]]; then
    fail "duplicate detector name: ${detector_name}"
  fi
  detector_name_seen["${detector_name}"]="1"

  if [[ "${detector_enabled}" != "true" ]]; then
    continue
  fi

  enabled_detectors="$((enabled_detectors + 1))"

  validate_positive_int "${detector_window_seconds}" "detector.windowSeconds (${detector_name})"
  validate_positive_int "${detector_threshold}" "detector.threshold (${detector_name})"
  validate_positive_int "${detector_ban_ttl_seconds}" "detector.banTTLSeconds (${detector_name})"

  if [[ -z "${detector_journal_unit}" && -z "${detector_journal_identifier}" ]]; then
    fail "detector ${detector_name} requires journalUnit and/or journalIdentifier"
  fi

  validate_regex_token "${detector_extract_regex}" "detector.extractRegex (${detector_name})"

  detector_since_epoch="$((now_epoch - detector_window_seconds))"
  detector_journal_file="${tmp_dir}/journal-${detector_index}.log"
  : > "${detector_journal_file}"

  if [[ -n "${detector_journal_unit}" ]]; then
    if ! journalctl --no-pager --quiet --unit "${detector_journal_unit}" --since "@${detector_since_epoch}" -o cat >> "${detector_journal_file}"; then
      warn "detector=${detector_name} failed to read unit journal ${detector_journal_unit}; continuing"
    fi
  fi

  if [[ -n "${detector_journal_identifier}" ]]; then
    if ! journalctl --no-pager --quiet --identifier "${detector_journal_identifier}" --since "@${detector_since_epoch}" -o cat >> "${detector_journal_file}"; then
      warn "detector=${detector_name} failed to read identifier journal ${detector_journal_identifier}; continuing"
    fi
  fi

  declare -A detector_fail_counts=()
  detector_observed_failures="0"

  while IFS= read -r line; do
    if [[ -n "${detector_line_contains}" && "${line}" != *"${detector_line_contains}"* ]]; then
      continue
    fi

    source_ip=""
    if [[ -n "${detector_extract_regex}" ]]; then
      if ! source_ip="$(extract_source_ip_regex "${line}" "${detector_extract_regex}")"; then
        continue
      fi
    else
      if ! source_ip="$(extract_source_ip_default "${line}")"; then
        continue
      fi
    fi

    detector_observed_failures="$((detector_observed_failures + 1))"
    detector_fail_counts["${source_ip}"]="$(( ${detector_fail_counts["${source_ip}"]:-0} + 1 ))"
  done < "${detector_journal_file}"

  detector_candidate_ips="0"
  detector_ban_requests="0"
  detector_ban_changed="0"
  detector_ban_failures="0"
  detector_escalated="0"

  for source_ip in "${!detector_fail_counts[@]}"; do
    if (( detector_fail_counts["${source_ip}"] < detector_threshold )); then
      continue
    fi

    detector_candidate_ips="$((detector_candidate_ips + 1))"
    detector_ban_requests="$((detector_ban_requests + 1))"

    cidr="$(normalize_cidr "${source_ip}")"

    cmd=(nix-csfctl --endpoint "${endpoint}" --output json)
    if [[ -n "${auth_token_file}" ]]; then
      cmd+=(--auth-token-file "${auth_token_file}")
    fi
    cmd+=(ban-temp "${cidr}" --ttl "${detector_ban_ttl_seconds}" --reason "${detector_reason}")

    response_file="${tmp_dir}/ban-${detector_index}-${detector_candidate_ips}.json"
    error_file="${tmp_dir}/ban-${detector_index}-${detector_candidate_ips}.err"

    if "${cmd[@]}" > "${response_file}" 2> "${error_file}"; then
      changed_value="$(jq -r '.changed // false' "${response_file}" 2>/dev/null || echo "false")"
      escalated_value="$(jq -r '.escalation.escalated // false' "${response_file}" 2>/dev/null || echo "false")"

      if [[ "${changed_value}" == "true" ]]; then
        detector_ban_changed="$((detector_ban_changed + 1))"
      fi
      if [[ "${escalated_value}" == "true" ]]; then
        detector_escalated="$((detector_escalated + 1))"
      fi

      echo "nix-csf-lfd-detector: detector=${detector_name} ip=${source_ip} count=${detector_fail_counts["${source_ip}"]} cidr=${cidr} changed=${changed_value} escalated=${escalated_value}"
    else
      detector_ban_failures="$((detector_ban_failures + 1))"
      warn "detector=${detector_name} ban-temp request failed for ${cidr}: $(tr '\n' ' ' < "${error_file}")"
    fi
  done

  observed_failures="$((observed_failures + detector_observed_failures))"
  candidate_ips="$((candidate_ips + detector_candidate_ips))"
  ban_requests="$((ban_requests + detector_ban_requests))"
  ban_changed="$((ban_changed + detector_ban_changed))"
  ban_failures="$((ban_failures + detector_ban_failures))"
  escalated_count="$((escalated_count + detector_escalated))"

  detector_label="$(escape_prometheus_label "${detector_name}")"
  per_detector_metrics+=("nix_csf_lfd_detector_observed_failures_by_detector{detector=\"${detector_label}\"} ${detector_observed_failures}")
  per_detector_metrics+=("nix_csf_lfd_detector_candidate_ips_by_detector{detector=\"${detector_label}\"} ${detector_candidate_ips}")
  per_detector_metrics+=("nix_csf_lfd_detector_ban_requests_by_detector{detector=\"${detector_label}\"} ${detector_ban_requests}")
  per_detector_metrics+=("nix_csf_lfd_detector_ban_changed_by_detector{detector=\"${detector_label}\"} ${detector_ban_changed}")
  per_detector_metrics+=("nix_csf_lfd_detector_ban_failures_by_detector{detector=\"${detector_label}\"} ${detector_ban_failures}")
  per_detector_metrics+=("nix_csf_lfd_detector_escalated_by_detector{detector=\"${detector_label}\"} ${detector_escalated}")
  per_detector_metrics+=("nix_csf_lfd_detector_window_seconds_by_detector{detector=\"${detector_label}\"} ${detector_window_seconds}")
  per_detector_metrics+=("nix_csf_lfd_detector_threshold_by_detector{detector=\"${detector_label}\"} ${detector_threshold}")
done

if [[ "${enabled_detectors}" == "0" ]]; then
  fail "no enabled detectors were resolved"
fi

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

  cat > "${metrics_tmp}" <<METRICS_EOF
# HELP nix_csf_lfd_detector_last_run_success Detector run success status (1=success, 0=errors occurred).
# TYPE nix_csf_lfd_detector_last_run_success gauge
nix_csf_lfd_detector_last_run_success $(if [[ "${ban_failures}" -eq 0 ]]; then echo 1; else echo 0; fi)
# HELP nix_csf_lfd_detector_detectors_total Total detectors resolved for this run.
# TYPE nix_csf_lfd_detector_detectors_total gauge
nix_csf_lfd_detector_detectors_total ${total_detectors}
# HELP nix_csf_lfd_detector_detectors_enabled Enabled detectors evaluated in this run.
# TYPE nix_csf_lfd_detector_detectors_enabled gauge
nix_csf_lfd_detector_detectors_enabled ${enabled_detectors}
# HELP nix_csf_lfd_detector_observed_failures Failure lines observed across all enabled detectors.
# TYPE nix_csf_lfd_detector_observed_failures gauge
nix_csf_lfd_detector_observed_failures ${observed_failures}
# HELP nix_csf_lfd_detector_candidate_ips Source IPs meeting threshold across all enabled detectors.
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
# HELP nix_csf_lfd_detector_observed_failures_by_detector Failure lines observed per detector.
# TYPE nix_csf_lfd_detector_observed_failures_by_detector gauge
# HELP nix_csf_lfd_detector_candidate_ips_by_detector Source IPs meeting threshold per detector.
# TYPE nix_csf_lfd_detector_candidate_ips_by_detector gauge
# HELP nix_csf_lfd_detector_ban_requests_by_detector Ban requests sent per detector.
# TYPE nix_csf_lfd_detector_ban_requests_by_detector gauge
# HELP nix_csf_lfd_detector_ban_changed_by_detector Changed ban requests per detector.
# TYPE nix_csf_lfd_detector_ban_changed_by_detector gauge
# HELP nix_csf_lfd_detector_ban_failures_by_detector Failed ban requests per detector.
# TYPE nix_csf_lfd_detector_ban_failures_by_detector gauge
# HELP nix_csf_lfd_detector_escalated_by_detector Escalated bans per detector.
# TYPE nix_csf_lfd_detector_escalated_by_detector gauge
# HELP nix_csf_lfd_detector_window_seconds_by_detector Observation window per detector.
# TYPE nix_csf_lfd_detector_window_seconds_by_detector gauge
# HELP nix_csf_lfd_detector_threshold_by_detector Trigger threshold per detector.
# TYPE nix_csf_lfd_detector_threshold_by_detector gauge
METRICS_EOF

  for metric_line in "${per_detector_metrics[@]}"; do
    printf '%s\n' "${metric_line}" >> "${metrics_tmp}"
  done

  install -m 0644 "${metrics_tmp}" "${metrics_file}"
fi

echo "nix-csf-lfd-detector: run complete detectors_total=${total_detectors} detectors_enabled=${enabled_detectors} observed_failures=${observed_failures} candidate_ips=${candidate_ips} ban_requests=${ban_requests} ban_changed=${ban_changed} ban_failures=${ban_failures} escalated=${escalated_count}"
