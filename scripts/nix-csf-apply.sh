#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csf-apply --config <json-file> [--mode apply|refresh]

Modes:
  apply    Apply nftables rules using static configuration and cached remote data.
  refresh  Refresh remote data sources (country/blocklists) and re-apply rules.
EOF
}

CONFIG_FILE=""
MODE="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "nix-csf: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
  echo "nix-csf: --config must point to a valid file" >&2
  exit 1
fi

if [[ "$MODE" != "apply" && "$MODE" != "refresh" ]]; then
  echo "nix-csf: --mode must be one of: apply, refresh" >&2
  exit 1
fi

STATE_DIR="/var/lib/nix-csf"
CACHE_DIR="${STATE_DIR}/cache"
RULESET_FILE="${STATE_DIR}/generated-ruleset.nft"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${STATE_DIR}" "${CACHE_DIR}"

run_started_epoch="$(date +%s)"
structured_logging="false"
metrics_enabled="false"
metrics_output_file="/var/lib/nix-csf/metrics.prom"
declare -a cluster_policy_auth_token_files=()
declare -a cluster_policy_auth_tokens=()
declare -a dynamic_offenders_auth_token_files=()
declare -a dynamic_offenders_auth_tokens=()
cluster_policy_auth_token_candidate_count="0"
cluster_policy_auth_token_selected_slot="0"
dynamic_offenders_auth_token_candidate_count="0"
dynamic_offenders_auth_token_selected_slot="0"
auth_selected_slot_result="0"

log_event() {
  local sink="$1"
  local level="$2"
  local event="$3"
  shift 3

  if [[ "${structured_logging}" != "true" ]]; then
    return 0
  fi

  local ts line
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="nix-csf: ts=${ts} level=${level} event=${event} mode=${MODE}"
  for field in "$@"; do
    line="${line} ${field}"
  done

  if [[ "${sink}" == "stderr" ]]; then
    echo "${line}" >&2
  else
    echo "${line}"
  fi
}

say() {
  echo "nix-csf: $*"
}

warn() {
  echo "nix-csf: WARNING: $*" >&2
  log_event "stderr" "warn" "warning"
}

fail() {
  echo "nix-csf: ERROR: $*" >&2
  log_event "stderr" "error" "failure"
  exit 1
}

normalize_cidrs() {
  local in_file="$1"
  local out_v4="$2"
  local out_v6="$3"

  awk '
    {
      gsub(/\r/, "", $0);
      sub(/#.*/, "", $0);
      sub(/;.*/, "", $0);
      gsub(/^[ \t]+|[ \t]+$/, "", $0);
      if ($0 == "") next;

      token = $0;
      # Support ipset-like feed lines:
      #   add <set_name> <cidr_or_ip>
      #   ipset add <set_name> <cidr_or_ip>
      if (match($0, /^add[ \t]+[^ \t]+[ \t]+([^ \t]+)/, m)) {
        token = m[1];
      } else if (match($0, /^ipset[ \t]+add[ \t]+[^ \t]+[ \t]+([^ \t]+)/, m)) {
        token = m[1];
      }

      gsub(/^[ \t]+|[ \t]+$/, "", token);
      if (token != "") print token;
    }
  ' "${in_file}" > "${TMP_DIR}/_normalized.txt"

  grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' "${TMP_DIR}/_normalized.txt" > "${out_v4}" || true
  grep -E '^[0-9A-Fa-f:]+(/[0-9]{1,3})?$' "${TMP_DIR}/_normalized.txt" | grep ':' > "${out_v6}" || true
}

sort_unique() {
  local in_file="$1"
  local out_file="$2"
  if [[ -s "${in_file}" ]]; then
    sort -u "${in_file}" > "${out_file}"
  else
    : > "${out_file}"
  fi
}

merge_sorted_overlay() {
  local base_file="$1"
  local overlay_file="$2"

  if [[ -s "${overlay_file}" ]]; then
    cat "${base_file}" "${overlay_file}" > "${TMP_DIR}/_merge-overlay.txt"
    sort_unique "${TMP_DIR}/_merge-overlay.txt" "${base_file}"
  fi
}

subtract_sorted_overlay() {
  local base_file="$1"
  local overlay_file="$2"

  if [[ -s "${base_file}" && -s "${overlay_file}" ]]; then
    comm -23 "${base_file}" "${overlay_file}" > "${TMP_DIR}/_subtract-overlay.txt"
    install -m 0640 "${TMP_DIR}/_subtract-overlay.txt" "${base_file}"
  fi
}

append_if_exists() {
  local source_file="$1"
  local target_file="$2"
  if [[ -s "${source_file}" ]]; then
    cat "${source_file}" >> "${target_file}"
  fi
}

append_local_policy_file() {
  local list_name="$1"
  local path="$2"
  local target_raw="$3"
  local fail_on_missing="$4"

  if [[ -r "${path}" ]]; then
    cat "${path}" >> "${target_raw}"
    return 0
  fi

  if [[ "${fail_on_missing}" == "true" ]]; then
    fail "localFiles.${list_name} source is missing or unreadable: ${path}"
  fi

  warn "localFiles.${list_name} source is missing or unreadable; skipping: ${path}"
  return 0
}

fetch_to_cache() {
  local url="$1"
  local cache_file="$2"
  local tmp_file="${TMP_DIR}/download.txt"

  if curl --fail --location --silent --show-error --max-time 40 "${url}" -o "${tmp_file}"; then
    install -m 0640 "${tmp_file}" "${cache_file}"
    return 0
  fi
  return 1
}

validate_auth_token_file() {
  local source_label="$1"
  local token_file="$2"
  local raw_mode mode_value group_perm other_perm

  if [[ ! -f "${token_file}" ]]; then
    fail "${source_label} auth token file does not exist: ${token_file}"
  fi

  if [[ ! -r "${token_file}" ]]; then
    fail "${source_label} auth token file is not readable: ${token_file}"
  fi

  raw_mode="$(stat -c '%a' "${token_file}")" || fail "${source_label} auth token file mode check failed: ${token_file}"
  mode_value="$((10#${raw_mode}))"
  group_perm="$(( (mode_value / 10) % 10 ))"
  other_perm="$(( mode_value % 10 ))"

  if (( group_perm != 0 || other_perm != 0 )); then
    fail "${source_label} auth token file must not grant group/other permissions: ${token_file} (mode ${raw_mode})"
  fi
}

load_auth_tokens_from_files() {
  local source_label="$1"
  local -n token_files_ref="$2"
  local -n token_values_ref="$3"
  local token_file token_value

  token_values_ref=()

  for token_file in "${token_files_ref[@]}"; do
    validate_auth_token_file "${source_label}" "${token_file}"

    token_value="$(tr -d '\r\n' < "${token_file}")"
    if [[ -z "${token_value}" ]]; then
      fail "${source_label} auth token file is empty: ${token_file}"
    fi
    if [[ "${token_value}" =~ [[:space:]] ]]; then
      fail "${source_label} auth token file must not contain whitespace: ${token_file}"
    fi

    token_values_ref+=("${token_value}")
  done
}

fetch_json_with_auth_candidates() {
  local source_tag="$1"
  local source_label="$2"
  local url="$3"
  local output_file="$4"
  local node_id="$5"
  local -n auth_tokens_ref="$6"
  local -a base_curl_args=(--fail --location --silent --show-error --max-time 40)
  local -a curl_args
  local token_count slot auth_token

  auth_selected_slot_result="0"
  token_count="${#auth_tokens_ref[@]}"

  if [[ -n "${node_id}" ]]; then
    base_curl_args+=(-H "X-Nix-Csf-Node: ${node_id}")
  fi

  if [[ "${token_count}" -eq 0 ]]; then
    if curl "${base_curl_args[@]}" "${url}" -o "${output_file}"; then
      return 0
    fi
    return 1
  fi

  slot=0
  for auth_token in "${auth_tokens_ref[@]}"; do
    slot=$(( slot + 1 ))
    curl_args=("${base_curl_args[@]}" -H "Authorization: Bearer ${auth_token}")

    if curl "${curl_args[@]}" "${url}" -o "${output_file}"; then
      auth_selected_slot_result="${slot}"
      if [[ "${slot}" -gt 1 ]]; then
        log_event "stdout" "info" "auth_fallback_success" \
          "source=${source_tag}" \
          "selected_slot=${slot}" \
          "candidate_count=${token_count}"
      fi
      return 0
    fi

    if [[ "${slot}" -lt "${token_count}" ]]; then
      warn "${source_label} auth token slot ${slot} failed; trying next token"
    fi
  done

  return 1
}

fetch_cluster_policy_to_cache() {
  local url="$1"
  local cache_file="$2"
  local tmp_file="${TMP_DIR}/cluster-policy-download.json"

  if fetch_json_with_auth_candidates \
    "cluster_policy" \
    "cluster policy" \
    "${url}" \
    "${tmp_file}" \
    "${cluster_policy_node_id}" \
    cluster_policy_auth_tokens; then
    cluster_policy_auth_token_selected_slot="${auth_selected_slot_result}"
    if ! jq -e . "${tmp_file}" >/dev/null 2>&1; then
      return 2
    fi
    if ! validate_cluster_policy_schema "${tmp_file}"; then
      return 3
    fi
    install -m 0640 "${tmp_file}" "${cache_file}"
    return 0
  fi

  return 1
}

fetch_dynamic_offenders_to_cache() {
  local url="$1"
  local cache_file="$2"
  local tmp_file="${TMP_DIR}/dynamic-offenders-download.json"

  if fetch_json_with_auth_candidates \
    "dynamic_offenders" \
    "dynamic offenders" \
    "${url}" \
    "${tmp_file}" \
    "${dynamic_offenders_node_id}" \
    dynamic_offenders_auth_tokens; then
    dynamic_offenders_auth_token_selected_slot="${auth_selected_slot_result}"
    if ! jq -e . "${tmp_file}" >/dev/null 2>&1; then
      return 2
    fi
    if ! validate_dynamic_offenders_schema "${tmp_file}"; then
      return 3
    fi
    install -m 0640 "${tmp_file}" "${cache_file}"
    return 0
  fi

  return 1
}

validate_cluster_policy_schema() {
  local policy_file="$1"

  jq -e '
    type == "object"
    and (
      (.schemaVersion? == null)
      or (.schemaVersion == 1)
      or (.schemaVersion == "1")
      or (.schemaVersion == 2)
      or (.schemaVersion == "2")
    )
    and (
      (.revision? == null)
      or ((.revision | type) == "string")
      or ((.revision | type) == "number")
    )
    and (
      (.ttlSeconds? == null)
      or (
        (.ttlSeconds | type) == "number"
        and ((.ttlSeconds | floor) == .ttlSeconds)
        and (.ttlSeconds >= 0)
      )
    )
    and (
      (.allowIPv4? == null)
      or ((.allowIPv4 | type) == "array" and all(.allowIPv4[]; type == "string"))
    )
    and (
      (.allowIPv6? == null)
      or ((.allowIPv6 | type) == "array" and all(.allowIPv6[]; type == "string"))
    )
    and (
      (.denyIPv4? == null)
      or ((.denyIPv4 | type) == "array" and all(.denyIPv4[]; type == "string"))
    )
    and (
      (.denyIPv6? == null)
      or ((.denyIPv6 | type) == "array" and all(.denyIPv6[]; type == "string"))
    )
    and (
      (.ignoreIPv4? == null)
      or ((.ignoreIPv4 | type) == "array" and all(.ignoreIPv4[]; type == "string"))
    )
    and (
      (.ignoreIPv6? == null)
      or ((.ignoreIPv6 | type) == "array" and all(.ignoreIPv6[]; type == "string"))
    )
  ' "${policy_file}" >/dev/null 2>&1
}

validate_dynamic_offenders_schema() {
  local policy_file="$1"

  jq -e '
    def is_nonneg_int:
      (type == "number")
      and ((floor) == .)
      and (. >= 0);

    def offender_entry_ok:
      (type == "string")
      or (
        type == "object"
        and ((.cidr? | type) == "string")
        and (
          (.ttlSeconds? == null)
          or ((.ttlSeconds | is_nonneg_int))
        )
        and (
          (.expiresAt? == null)
          or ((.expiresAt | is_nonneg_int))
        )
        and (
          (.reason? == null)
          or ((.reason | type) == "string")
        )
      );

    type == "object"
    and (
      (.schemaVersion? == null)
      or (.schemaVersion == 1)
      or (.schemaVersion == "1")
      or (.schemaVersion == 2)
      or (.schemaVersion == "2")
    )
    and (
      (.revision? == null)
      or ((.revision | type) == "string")
      or ((.revision | type) == "number")
    )
    and (
      (.ttlSeconds? == null)
      or ((.ttlSeconds | is_nonneg_int))
    )
    and (
      (.banIPv4? == null)
      or ((.banIPv4 | type) == "array" and all(.banIPv4[]; offender_entry_ok))
    )
    and (
      (.banIPv6? == null)
      or ((.banIPv6 | type) == "array" and all(.banIPv6[]; offender_entry_ok))
    )
  ' "${policy_file}" >/dev/null 2>&1
}

sanitize_dynamic_entry_pairs() {
  local in_file="$1"
  local out_file="$2"

  awk -F'|' '
    {
      cidr = $1;
      ttl = $2;
      gsub(/\r/, "", cidr);
      sub(/#.*/, "", cidr);
      gsub(/^[ \t]+|[ \t]+$/, "", cidr);
      gsub(/^[ \t]+|[ \t]+$/, "", ttl);
      if (cidr != "" && ttl ~ /^[0-9]+$/ && ttl > 0) {
        printf "%s|%s\n", cidr, ttl;
      }
    }
  ' "${in_file}" > "${out_file}"
}

build_dynamic_timeout_set_v4() {
  local in_file="$1"
  local out_file="$2"

  if [[ ! -s "${in_file}" ]]; then
    : > "${out_file}"
    return 0
  fi

  awk -F'|' '
    $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/ && $2 ~ /^[0-9]+$/ && $2 > 0 {
      ttl = $2 + 0;
      if (!($1 in best) || ttl > best[$1]) {
        best[$1] = ttl;
      }
    }
    END {
      for (cidr in best) {
        printf "%s timeout %ss\n", cidr, best[cidr];
      }
    }
  ' "${in_file}" | sort > "${out_file}"
}

build_dynamic_timeout_set_v6() {
  local in_file="$1"
  local out_file="$2"

  if [[ ! -s "${in_file}" ]]; then
    : > "${out_file}"
    return 0
  fi

  awk -F'|' '
    $1 ~ /^[0-9A-Fa-f:]+(\/[0-9]{1,3})?$/ && index($1, ":") > 0 && $2 ~ /^[0-9]+$/ && $2 > 0 {
      ttl = $2 + 0;
      if (!($1 in best) || ttl > best[$1]) {
        best[$1] = ttl;
      }
    }
    END {
      for (cidr in best) {
        printf "%s timeout %ss\n", cidr, best[cidr];
      }
    }
  ' "${in_file}" | sort > "${out_file}"
}

fetch_country_data_for_code() {
  local cc_lc="$1"
  local out_v4="$2"
  local out_v6="$3"

  if [[ -n "${country_ipv4_template}" ]]; then
    local v4_url="${country_ipv4_template//%s/${cc_lc}}"
    local v4_cache="${CACHE_DIR}/country-v4-${cc_lc}.txt"

    if [[ "${MODE}" == "refresh" ]]; then
      if ! fetch_to_cache "${v4_url}" "${v4_cache}"; then
        if [[ -s "${v4_cache}" ]]; then
          warn "failed to refresh ${v4_url}; using cached data"
        elif [[ "${country_fail_open}" == "true" ]]; then
          warn "failed to fetch ${v4_url}; continuing due to failOpen"
        else
          fail "failed to fetch ${v4_url} and no cache exists"
        fi
      fi
    fi

    append_if_exists "${v4_cache}" "${out_v4}"
  fi

  if [[ -n "${country_ipv6_template}" ]]; then
    local v6_url="${country_ipv6_template//%s/${cc_lc}}"
    local v6_cache="${CACHE_DIR}/country-v6-${cc_lc}.txt"

    if [[ "${MODE}" == "refresh" ]]; then
      if ! fetch_to_cache "${v6_url}" "${v6_cache}"; then
        if [[ -s "${v6_cache}" ]]; then
          warn "failed to refresh ${v6_url}; using cached data"
        elif [[ "${country_fail_open}" == "true" ]]; then
          warn "failed to fetch ${v6_url}; continuing due to failOpen"
        else
          fail "failed to fetch ${v6_url} and no cache exists"
        fi
      fi
    fi

    append_if_exists "${v6_cache}" "${out_v6}"
  fi
}

emit_set() {
  local name="$1"
  local nft_type="$2"
  local source_file="$3"
  local set_flags="${4:-interval}"

  echo "  set ${name} {"
  echo "    type ${nft_type}"
  echo "    flags ${set_flags}"
  if [[ "${set_flags}" == *"interval"* && "${set_flags}" != *"timeout"* ]]; then
    # Allow overlapping CIDRs from multiple sources (for example /24 + /32)
    # without failing nft ruleset validation.
    echo "    auto-merge"
  fi
  if [[ -s "${source_file}" ]]; then
    echo "    elements = {"
    awk '
      { lines[++n] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          suffix = (i < n) ? "," : ""
          printf("      %s%s\n", lines[i], suffix)
        }
      }
    ' "${source_file}"
    echo "    }"
  fi
  echo "  }"
}

count_file_lines() {
  local file="$1"

  if [[ -s "${file}" ]]; then
    wc -l < "${file}" | tr -d '[:space:]'
  else
    echo "0"
  fi
}

bool_to_num() {
  if [[ "$1" == "true" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

append_unique_value() {
  local -n ref="$1"
  local candidate="$2"
  local existing

  for existing in "${ref[@]}"; do
    if [[ "${existing}" == "${candidate}" ]]; then
      return 0
    fi
  done

  ref+=("${candidate}")
}

validate_icmp_type_name() {
  local family="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[a-z0-9_-]+$ ]]; then
    fail "icmp.${family} contains invalid nft type token: ${value}"
  fi
}

write_metrics() {
  if [[ "${metrics_enabled}" != "true" ]]; then
    return 0
  fi

  local output_dir tmp_metrics now_epoch duration
  output_dir="$(dirname "${metrics_output_file}")"
  tmp_metrics="${TMP_DIR}/metrics.prom"
  now_epoch="$(date +%s)"
  duration=$(( now_epoch - run_started_epoch ))

  mkdir -p "${output_dir}"

  {
    echo "# HELP nix_csf_last_run_timestamp_seconds Unix timestamp of the last successful run."
    echo "# TYPE nix_csf_last_run_timestamp_seconds gauge"
    printf 'nix_csf_last_run_timestamp_seconds{mode="%s"} %s\n' "${MODE}" "${now_epoch}"
    echo "# HELP nix_csf_last_run_success Last run result (1=success)."
    echo "# TYPE nix_csf_last_run_success gauge"
    printf 'nix_csf_last_run_success{mode="%s"} 1\n' "${MODE}"
    echo "# HELP nix_csf_build_info Build/version metadata (always 1)."
    echo "# TYPE nix_csf_build_info gauge"
    printf 'nix_csf_build_info{version="%s"} 1\n' "${module_version}"
    echo "# HELP nix_csf_last_run_duration_seconds Total runtime of the successful run."
    echo "# TYPE nix_csf_last_run_duration_seconds gauge"
    printf 'nix_csf_last_run_duration_seconds{mode="%s"} %s\n' "${MODE}" "${duration}"
    echo "# HELP nix_csf_feature_enabled Feature toggle state (1=enabled, 0=disabled)."
    echo "# TYPE nix_csf_feature_enabled gauge"
    printf 'nix_csf_feature_enabled{feature="country"} %s\n' "$(bool_to_num "${country_enabled}")"
    printf 'nix_csf_feature_enabled{feature="country_port_deny"} %s\n' "$(bool_to_num "${country_port_deny_enabled}")"
    printf 'nix_csf_feature_enabled{feature="blocklists"} %s\n' "$(bool_to_num "${blocklists_enabled}")"
    printf 'nix_csf_feature_enabled{feature="local_files"} %s\n' "$(bool_to_num "${local_files_enabled}")"
    printf 'nix_csf_feature_enabled{feature="cluster_policy"} %s\n' "$(bool_to_num "${cluster_policy_enabled}")"
    printf 'nix_csf_feature_enabled{feature="dynamic_offenders"} %s\n' "$(bool_to_num "${dynamic_offenders_enabled}")"
    printf 'nix_csf_feature_enabled{feature="coexist_docker"} %s\n' "$(bool_to_num "${coexistence_docker_enabled}")"
    printf 'nix_csf_feature_enabled{feature="log_drops"} %s\n' "$(bool_to_num "${log_drops}")"
    printf 'nix_csf_feature_enabled{feature="legacy_syn_rate_limit"} %s\n' "$(bool_to_num "${legacy_syn_rate_limit_enabled}")"
    printf 'nix_csf_feature_enabled{feature="syn_flood"} %s\n' "$(bool_to_num "${syn_flood_enabled}")"
    printf 'nix_csf_feature_enabled{feature="conn_flood"} %s\n' "$(bool_to_num "${conn_flood_enabled}")"
    printf 'nix_csf_feature_enabled{feature="icmp_rate_limit"} %s\n' "$(bool_to_num "${icmp_rate_limit_effective}")"
    echo "# HELP nix_csf_coexistence_profile Active coexistence profile (1 active, 0 inactive)."
    echo "# TYPE nix_csf_coexistence_profile gauge"
    if [[ "${coexistence_profile}" == "exclusive-firewall" ]]; then
      echo 'nix_csf_coexistence_profile{profile="exclusive-firewall"} 1'
      echo 'nix_csf_coexistence_profile{profile="docker-coexist"} 0'
    else
      echo 'nix_csf_coexistence_profile{profile="exclusive-firewall"} 0'
      echo 'nix_csf_coexistence_profile{profile="docker-coexist"} 1'
    fi
    echo "# HELP nix_csf_icmp_profile Active ICMP policy profile (1 active, 0 inactive)."
    echo "# TYPE nix_csf_icmp_profile gauge"
    if [[ "${icmp_profile}" == "legacy" ]]; then
      echo 'nix_csf_icmp_profile{profile="legacy"} 1'
      echo 'nix_csf_icmp_profile{profile="off"} 0'
      echo 'nix_csf_icmp_profile{profile="safe"} 0'
      echo 'nix_csf_icmp_profile{profile="diagnostic"} 0'
      echo 'nix_csf_icmp_profile{profile="open"} 0'
    elif [[ "${icmp_profile}" == "off" ]]; then
      echo 'nix_csf_icmp_profile{profile="legacy"} 0'
      echo 'nix_csf_icmp_profile{profile="off"} 1'
      echo 'nix_csf_icmp_profile{profile="safe"} 0'
      echo 'nix_csf_icmp_profile{profile="diagnostic"} 0'
      echo 'nix_csf_icmp_profile{profile="open"} 0'
    elif [[ "${icmp_profile}" == "safe" ]]; then
      echo 'nix_csf_icmp_profile{profile="legacy"} 0'
      echo 'nix_csf_icmp_profile{profile="off"} 0'
      echo 'nix_csf_icmp_profile{profile="safe"} 1'
      echo 'nix_csf_icmp_profile{profile="diagnostic"} 0'
      echo 'nix_csf_icmp_profile{profile="open"} 0'
    elif [[ "${icmp_profile}" == "diagnostic" ]]; then
      echo 'nix_csf_icmp_profile{profile="legacy"} 0'
      echo 'nix_csf_icmp_profile{profile="off"} 0'
      echo 'nix_csf_icmp_profile{profile="safe"} 0'
      echo 'nix_csf_icmp_profile{profile="diagnostic"} 1'
      echo 'nix_csf_icmp_profile{profile="open"} 0'
    else
      echo 'nix_csf_icmp_profile{profile="legacy"} 0'
      echo 'nix_csf_icmp_profile{profile="off"} 0'
      echo 'nix_csf_icmp_profile{profile="safe"} 0'
      echo 'nix_csf_icmp_profile{profile="diagnostic"} 0'
      echo 'nix_csf_icmp_profile{profile="open"} 1'
    fi
    echo "# HELP nix_csf_set_entries Number of CIDR elements loaded into nft sets."
    echo "# TYPE nix_csf_set_entries gauge"
    printf 'nix_csf_set_entries{set="allow_ipv4"} %s\n' "${allow_v4_count}"
    printf 'nix_csf_set_entries{set="allow_ipv6"} %s\n' "${allow_v6_count}"
    printf 'nix_csf_set_entries{set="deny_ipv4"} %s\n' "${deny_v4_count}"
    printf 'nix_csf_set_entries{set="deny_ipv6"} %s\n' "${deny_v6_count}"
    printf 'nix_csf_set_entries{set="country_ipv4"} %s\n' "${country_v4_count}"
    printf 'nix_csf_set_entries{set="country_ipv6"} %s\n' "${country_v6_count}"
    printf 'nix_csf_set_entries{set="country_port_deny_ipv4"} %s\n' "${country_port_deny_v4_count}"
    printf 'nix_csf_set_entries{set="country_port_deny_ipv6"} %s\n' "${country_port_deny_v6_count}"
    printf 'nix_csf_set_entries{set="feed_ipv4"} %s\n' "${feed_v4_count}"
    printf 'nix_csf_set_entries{set="feed_ipv6"} %s\n' "${feed_v6_count}"
    printf 'nix_csf_set_entries{set="local_allow_ipv4"} %s\n' "${local_allow_v4_count}"
    printf 'nix_csf_set_entries{set="local_allow_ipv6"} %s\n' "${local_allow_v6_count}"
    printf 'nix_csf_set_entries{set="local_deny_ipv4"} %s\n' "${local_deny_v4_count}"
    printf 'nix_csf_set_entries{set="local_deny_ipv6"} %s\n' "${local_deny_v6_count}"
    printf 'nix_csf_set_entries{set="local_ignore_ipv4"} %s\n' "${local_ignore_v4_count}"
    printf 'nix_csf_set_entries{set="local_ignore_ipv6"} %s\n' "${local_ignore_v6_count}"
    printf 'nix_csf_set_entries{set="effective_ignore_ipv4"} %s\n' "${effective_ignore_v4_count}"
    printf 'nix_csf_set_entries{set="effective_ignore_ipv6"} %s\n' "${effective_ignore_v6_count}"
    printf 'nix_csf_set_entries{set="cluster_allow_ipv4"} %s\n' "${cluster_allow_v4_count}"
    printf 'nix_csf_set_entries{set="cluster_allow_ipv6"} %s\n' "${cluster_allow_v6_count}"
    printf 'nix_csf_set_entries{set="cluster_deny_ipv4"} %s\n' "${cluster_deny_v4_count}"
    printf 'nix_csf_set_entries{set="cluster_deny_ipv6"} %s\n' "${cluster_deny_v6_count}"
    printf 'nix_csf_set_entries{set="cluster_ignore_ipv4"} %s\n' "${cluster_ignore_v4_count}"
    printf 'nix_csf_set_entries{set="cluster_ignore_ipv6"} %s\n' "${cluster_ignore_v6_count}"
    printf 'nix_csf_set_entries{set="dynamic_ban_ipv4"} %s\n' "${dynamic_ban_v4_count}"
    printf 'nix_csf_set_entries{set="dynamic_ban_ipv6"} %s\n' "${dynamic_ban_v6_count}"
    echo "# HELP nix_csf_source_count Number of configured source identifiers."
    echo "# TYPE nix_csf_source_count gauge"
    printf 'nix_csf_source_count{source="country_codes"} %s\n' "${#country_codes[@]}"
    printf 'nix_csf_source_count{source="country_port_deny_codes"} %s\n' "${#country_port_deny_codes[@]}"
    printf 'nix_csf_source_count{source="blocklist_urls"} %s\n' "${#blocklist_urls[@]}"
    printf 'nix_csf_source_count{source="local_allow_files"} %s\n' "${local_allow_source_count}"
    printf 'nix_csf_source_count{source="local_deny_files"} %s\n' "${local_deny_source_count}"
    printf 'nix_csf_source_count{source="local_ignore_files"} %s\n' "${local_ignore_source_count}"
    printf 'nix_csf_source_count{source="cluster_policy_urls"} %s\n' "${cluster_policy_source_count}"
    printf 'nix_csf_source_count{source="dynamic_offender_urls"} %s\n' "${dynamic_offenders_source_count}"
    echo "# HELP nix_csf_auth_token_candidates Number of configured auth token candidates per remote source."
    echo "# TYPE nix_csf_auth_token_candidates gauge"
    printf 'nix_csf_auth_token_candidates{source="cluster_policy"} %s\n' "${cluster_policy_auth_token_candidate_count}"
    printf 'nix_csf_auth_token_candidates{source="dynamic_offenders"} %s\n' "${dynamic_offenders_auth_token_candidate_count}"
    echo "# HELP nix_csf_auth_token_selected_slot Selected auth token candidate slot for successful fetches (0 when none selected)."
    echo "# TYPE nix_csf_auth_token_selected_slot gauge"
    printf 'nix_csf_auth_token_selected_slot{source="cluster_policy"} %s\n' "${cluster_policy_auth_token_selected_slot}"
    printf 'nix_csf_auth_token_selected_slot{source="dynamic_offenders"} %s\n' "${dynamic_offenders_auth_token_selected_slot}"
    echo "# HELP nix_csf_cluster_policy_schema_version Active cluster policy schema version."
    echo "# TYPE nix_csf_cluster_policy_schema_version gauge"
    printf 'nix_csf_cluster_policy_schema_version %s\n' "${cluster_policy_schema_version}"
    echo "# HELP nix_csf_cluster_policy_cache_age_seconds Age of cached cluster policy in seconds."
    echo "# TYPE nix_csf_cluster_policy_cache_age_seconds gauge"
    printf 'nix_csf_cluster_policy_cache_age_seconds %s\n' "${cluster_policy_cache_age_seconds}"
    echo "# HELP nix_csf_cluster_policy_ttl_seconds Cluster policy TTL in seconds (0 when unset)."
    echo "# TYPE nix_csf_cluster_policy_ttl_seconds gauge"
    printf 'nix_csf_cluster_policy_ttl_seconds %s\n' "${cluster_policy_ttl_seconds}"
    echo "# HELP nix_csf_cluster_policy_cache_expired Cached cluster policy expiration status (1=expired)."
    echo "# TYPE nix_csf_cluster_policy_cache_expired gauge"
    printf 'nix_csf_cluster_policy_cache_expired %s\n' "$(bool_to_num "${cluster_policy_cache_expired}")"
    echo "# HELP nix_csf_dynamic_snapshot_schema_version Active dynamic snapshot schema version."
    echo "# TYPE nix_csf_dynamic_snapshot_schema_version gauge"
    printf 'nix_csf_dynamic_snapshot_schema_version %s\n' "${dynamic_offenders_schema_version}"
    echo "# HELP nix_csf_dynamic_snapshot_cache_age_seconds Age of cached dynamic snapshot in seconds."
    echo "# TYPE nix_csf_dynamic_snapshot_cache_age_seconds gauge"
    printf 'nix_csf_dynamic_snapshot_cache_age_seconds %s\n' "${dynamic_offenders_cache_age_seconds}"
    echo "# HELP nix_csf_dynamic_snapshot_ttl_seconds Dynamic snapshot TTL in seconds (0 when unset)."
    echo "# TYPE nix_csf_dynamic_snapshot_ttl_seconds gauge"
    printf 'nix_csf_dynamic_snapshot_ttl_seconds %s\n' "${dynamic_offenders_ttl_seconds}"
    echo "# HELP nix_csf_dynamic_snapshot_cache_expired Cached dynamic snapshot expiration status (1=expired)."
    echo "# TYPE nix_csf_dynamic_snapshot_cache_expired gauge"
    printf 'nix_csf_dynamic_snapshot_cache_expired %s\n' "$(bool_to_num "${dynamic_offenders_cache_expired}")"
    echo "# HELP nix_csf_rate_limit_burst_packets Burst thresholds for rate-limited controls."
    echo "# TYPE nix_csf_rate_limit_burst_packets gauge"
    printf 'nix_csf_rate_limit_burst_packets{limit="syn_flood",preset="%s"} %s\n' "${syn_flood_preset}" "${syn_flood_burst}"
    printf 'nix_csf_rate_limit_burst_packets{limit="conn_flood",preset="%s"} %s\n' "${conn_flood_preset}" "${conn_flood_burst}"
  } > "${tmp_metrics}"

  install -m 0644 "${tmp_metrics}" "${metrics_output_file}"
  log_event "stdout" "info" "metrics_written" "output=${metrics_output_file}"
}

default_policy="$(jq -r '.defaultPolicy' "${CONFIG_FILE}")"
forward_policy="$(jq -r '.forwardPolicy' "${CONFIG_FILE}")"
coexistence_profile="$(jq -r '.coexistence.profile // "exclusive-firewall"' "${CONFIG_FILE}")"
allow_icmp="$(jq -r '.allowICMP' "${CONFIG_FILE}")"
icmp_profile="$(jq -r '.icmp.profile // "legacy"' "${CONFIG_FILE}")"
mapfile -t icmp_extra_ipv4_types < <(jq -r '.icmp.extraIPv4Types[]?' "${CONFIG_FILE}")
mapfile -t icmp_extra_ipv6_types < <(jq -r '.icmp.extraIPv6Types[]?' "${CONFIG_FILE}")
icmp_rate_limit_enabled="$(jq -r '.icmp.rateLimit.enable // false' "${CONFIG_FILE}")"
icmp_rate_limit_rate="$(jq -r '.icmp.rateLimit.rate // "30/second"' "${CONFIG_FILE}")"
icmp_rate_limit_burst="$(jq -r '.icmp.rateLimit.burst // 120' "${CONFIG_FILE}")"
log_drops="$(jq -r '.logDrops' "${CONFIG_FILE}")"
module_version="$(jq -r '.moduleVersion // "0.0.0-dev"' "${CONFIG_FILE}")"
syn_rate_limit="$(jq -r '.synRateLimit // ""' "${CONFIG_FILE}")"
legacy_syn_rate_limit_enabled="false"
if [[ -n "${syn_rate_limit}" ]]; then
  legacy_syn_rate_limit_enabled="true"
fi
syn_flood_enabled="$(jq -r '.rateLimits.synFlood.enable // false' "${CONFIG_FILE}")"
syn_flood_preset="$(jq -r '.rateLimits.synFlood.preset // "balanced"' "${CONFIG_FILE}")"
syn_flood_rate="$(jq -r '.rateLimits.synFlood.rate // ""' "${CONFIG_FILE}")"
syn_flood_burst="$(jq -r '.rateLimits.synFlood.burst // 0' "${CONFIG_FILE}")"
conn_flood_enabled="$(jq -r '.rateLimits.connFlood.enable // false' "${CONFIG_FILE}")"
conn_flood_preset="$(jq -r '.rateLimits.connFlood.preset // "balanced"' "${CONFIG_FILE}")"
conn_flood_rate="$(jq -r '.rateLimits.connFlood.rate // ""' "${CONFIG_FILE}")"
conn_flood_burst="$(jq -r '.rateLimits.connFlood.burst // 0' "${CONFIG_FILE}")"
structured_logging="$(jq -r '.observability.structuredLogging // false' "${CONFIG_FILE}")"
metrics_enabled="$(jq -r '.observability.metrics.enable // false' "${CONFIG_FILE}")"
metrics_output_file="$(jq -r '.observability.metrics.outputFile // "/var/lib/nix-csf/metrics.prom"' "${CONFIG_FILE}")"
dynamic_offenders_enabled="$(jq -r '.dynamicOffenders.enable // false' "${CONFIG_FILE}")"
dynamic_offenders_default_entry_ttl_seconds="$(jq -r '.dynamicOffenders.defaultEntryTTLSeconds // 900' "${CONFIG_FILE}")"
dynamic_offenders_max_entries="$(jq -r '.dynamicOffenders.maxEntries // 20000' "${CONFIG_FILE}")"
coexistence_docker_enabled="false"
icmp_rate_limit_effective="false"
icmp_rate_limit_clause=""
icmp_emit_open_accept="false"
icmp_emit_type_accept="false"
icmp_emit_drop_all="false"
declare -a icmp_profile_v4_types=()
declare -a icmp_profile_v6_types=()

if [[ "${coexistence_profile}" != "exclusive-firewall" && "${coexistence_profile}" != "docker-coexist" ]]; then
  fail "coexistence.profile must be one of: exclusive-firewall, docker-coexist"
fi

if [[ "${coexistence_profile}" == "docker-coexist" ]]; then
  coexistence_docker_enabled="true"
fi

if [[ "${metrics_enabled}" == "true" && "${metrics_output_file}" != /* ]]; then
  fail "observability.metrics.outputFile must be an absolute path"
fi

if [[ ! "${dynamic_offenders_default_entry_ttl_seconds}" =~ ^[1-9][0-9]*$ ]]; then
  fail "dynamicOffenders.defaultEntryTTLSeconds must be a positive integer"
fi

if [[ ! "${dynamic_offenders_max_entries}" =~ ^[1-9][0-9]*$ ]]; then
  fail "dynamicOffenders.maxEntries must be a positive integer"
fi

if [[ "${coexistence_profile}" == "docker-coexist" && "${forward_policy}" != "accept" ]]; then
  fail "coexistence.profile=docker-coexist requires forwardPolicy=accept"
fi

if [[ "${icmp_profile}" != "legacy" \
  && "${icmp_profile}" != "off" \
  && "${icmp_profile}" != "safe" \
  && "${icmp_profile}" != "diagnostic" \
  && "${icmp_profile}" != "open" ]]; then
  fail "icmp.profile must be one of: legacy, off, safe, diagnostic, open"
fi

if [[ "${icmp_rate_limit_enabled}" == "true" ]]; then
  if [[ -z "${icmp_rate_limit_rate}" ]]; then
    fail "icmp.rateLimit.rate must be non-empty when icmp.rateLimit.enable=true"
  fi
  if [[ ! "${icmp_rate_limit_burst}" =~ ^[1-9][0-9]*$ ]]; then
    fail "icmp.rateLimit.burst must be a positive integer when icmp.rateLimit.enable=true"
  fi
fi

if [[ "${icmp_profile}" == "open" ]]; then
  icmp_emit_open_accept="true"
elif [[ "${icmp_profile}" == "off" ]]; then
  icmp_emit_drop_all="true"
elif [[ "${icmp_profile}" == "safe" || "${icmp_profile}" == "diagnostic" ]]; then
  icmp_emit_type_accept="true"
  icmp_profile_v4_types=(
    "destination-unreachable"
    "time-exceeded"
    "parameter-problem"
  )
  icmp_profile_v6_types=(
    "destination-unreachable"
    "packet-too-big"
    "time-exceeded"
    "parameter-problem"
    "nd-router-solicit"
    "nd-router-advert"
    "nd-neighbor-solicit"
    "nd-neighbor-advert"
  )
  if [[ "${icmp_profile}" == "diagnostic" ]]; then
    append_unique_value icmp_profile_v4_types "echo-request"
    append_unique_value icmp_profile_v4_types "echo-reply"
    append_unique_value icmp_profile_v6_types "echo-request"
    append_unique_value icmp_profile_v6_types "echo-reply"
  fi

  for candidate in "${icmp_extra_ipv4_types[@]}"; do
    normalized="$(printf '%s' "${candidate}" | tr '[:upper:]' '[:lower:]')"
    validate_icmp_type_name "extraIPv4Types" "${normalized}"
    append_unique_value icmp_profile_v4_types "${normalized}"
  done

  for candidate in "${icmp_extra_ipv6_types[@]}"; do
    normalized="$(printf '%s' "${candidate}" | tr '[:upper:]' '[:lower:]')"
    validate_icmp_type_name "extraIPv6Types" "${normalized}"
    append_unique_value icmp_profile_v6_types "${normalized}"
  done
fi

if [[ "${icmp_rate_limit_enabled}" == "true" ]] && [[ "${icmp_profile}" != "legacy" && "${icmp_profile}" != "off" ]]; then
  icmp_rate_limit_effective="true"
  icmp_rate_limit_clause=" limit rate ${icmp_rate_limit_rate} burst ${icmp_rate_limit_burst} packets"
fi

log_event "stdout" "info" "run_start" \
  "version=${module_version}" \
  "metrics_enabled=${metrics_enabled}" \
  "coexistence_profile=${coexistence_profile}" \
  "icmp_profile=${icmp_profile}" \
  "icmp_rate_limit=${icmp_rate_limit_effective}"

if [[ "${syn_flood_enabled}" == "true" ]]; then
  if [[ -z "${syn_flood_rate}" || ! "${syn_flood_burst}" =~ ^[1-9][0-9]*$ ]]; then
    fail "rateLimits.synFlood requires a non-empty rate and positive burst"
  fi
fi

if [[ "${conn_flood_enabled}" == "true" ]]; then
  if [[ -z "${conn_flood_rate}" || ! "${conn_flood_burst}" =~ ^[1-9][0-9]*$ ]]; then
    fail "rateLimits.connFlood requires a non-empty rate and positive burst"
  fi
fi

jq -r '.allowIPv4[]?' "${CONFIG_FILE}" > "${TMP_DIR}/allow-v4.raw"
jq -r '.allowIPv6[]?' "${CONFIG_FILE}" > "${TMP_DIR}/allow-v6.raw"
jq -r '.denyIPv4[]?' "${CONFIG_FILE}" > "${TMP_DIR}/deny-v4.raw"
jq -r '.denyIPv6[]?' "${CONFIG_FILE}" > "${TMP_DIR}/deny-v6.raw"

local_files_enabled="$(jq -r '.localFiles.enable // false' "${CONFIG_FILE}")"
local_files_fail_on_missing="$(jq -r '.localFiles.failOnMissing // false' "${CONFIG_FILE}")"
mapfile -t local_allow_files < <(jq -r '.localFiles.allow[]?' "${CONFIG_FILE}")
mapfile -t local_deny_files < <(jq -r '.localFiles.deny[]?' "${CONFIG_FILE}")
mapfile -t local_ignore_files < <(jq -r '.localFiles.ignore[]?' "${CONFIG_FILE}")
local_allow_source_count="0"
local_deny_source_count="0"
local_ignore_source_count="0"

if [[ "${local_files_enabled}" == "true" ]]; then
  local_allow_source_count="${#local_allow_files[@]}"
  local_deny_source_count="${#local_deny_files[@]}"
  local_ignore_source_count="${#local_ignore_files[@]}"
fi

: > "${TMP_DIR}/local-allow.raw"
: > "${TMP_DIR}/local-deny.raw"
: > "${TMP_DIR}/local-ignore.raw"

if [[ "${local_files_enabled}" == "true" ]]; then
  for path in "${local_allow_files[@]}"; do
    append_local_policy_file "allow" "${path}" "${TMP_DIR}/local-allow.raw" "${local_files_fail_on_missing}"
  done

  for path in "${local_deny_files[@]}"; do
    append_local_policy_file "deny" "${path}" "${TMP_DIR}/local-deny.raw" "${local_files_fail_on_missing}"
  done

  for path in "${local_ignore_files[@]}"; do
    append_local_policy_file "ignore" "${path}" "${TMP_DIR}/local-ignore.raw" "${local_files_fail_on_missing}"
  done
fi

normalize_cidrs "${TMP_DIR}/allow-v4.raw" "${TMP_DIR}/allow-v4.norm" "${TMP_DIR}/allow-v4.ignore"
normalize_cidrs "${TMP_DIR}/allow-v6.raw" "${TMP_DIR}/allow-v6.ignore" "${TMP_DIR}/allow-v6.norm"
normalize_cidrs "${TMP_DIR}/deny-v4.raw" "${TMP_DIR}/deny-v4.norm" "${TMP_DIR}/deny-v4.ignore"
normalize_cidrs "${TMP_DIR}/deny-v6.raw" "${TMP_DIR}/deny-v6.ignore" "${TMP_DIR}/deny-v6.norm"

sort_unique "${TMP_DIR}/allow-v4.norm" "${TMP_DIR}/allow-v4.txt"
sort_unique "${TMP_DIR}/allow-v6.norm" "${TMP_DIR}/allow-v6.txt"
sort_unique "${TMP_DIR}/deny-v4.norm" "${TMP_DIR}/deny-v4.txt"
sort_unique "${TMP_DIR}/deny-v6.norm" "${TMP_DIR}/deny-v6.txt"

normalize_cidrs "${TMP_DIR}/local-allow.raw" "${TMP_DIR}/local-allow-v4.norm" "${TMP_DIR}/local-allow-v6.norm"
normalize_cidrs "${TMP_DIR}/local-deny.raw" "${TMP_DIR}/local-deny-v4.norm" "${TMP_DIR}/local-deny-v6.norm"
normalize_cidrs "${TMP_DIR}/local-ignore.raw" "${TMP_DIR}/local-ignore-v4.norm" "${TMP_DIR}/local-ignore-v6.norm"

sort_unique "${TMP_DIR}/local-allow-v4.norm" "${TMP_DIR}/local-allow-v4.txt"
sort_unique "${TMP_DIR}/local-allow-v6.norm" "${TMP_DIR}/local-allow-v6.txt"
sort_unique "${TMP_DIR}/local-deny-v4.norm" "${TMP_DIR}/local-deny-v4.txt"
sort_unique "${TMP_DIR}/local-deny-v6.norm" "${TMP_DIR}/local-deny-v6.txt"
sort_unique "${TMP_DIR}/local-ignore-v4.norm" "${TMP_DIR}/local-ignore-v4.txt"
sort_unique "${TMP_DIR}/local-ignore-v6.norm" "${TMP_DIR}/local-ignore-v6.txt"

merge_sorted_overlay "${TMP_DIR}/allow-v4.txt" "${TMP_DIR}/local-allow-v4.txt"
merge_sorted_overlay "${TMP_DIR}/allow-v6.txt" "${TMP_DIR}/local-allow-v6.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v4.txt" "${TMP_DIR}/local-deny-v4.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v6.txt" "${TMP_DIR}/local-deny-v6.txt"

country_enabled="$(jq -r '.country.enable' "${CONFIG_FILE}")"
country_mode="$(jq -r '.country.mode // "deny"' "${CONFIG_FILE}")"
country_fail_open="$(jq -r '.country.failOpen' "${CONFIG_FILE}")"
country_ipv4_template="$(jq -r '.country.ipv4URLTemplate // ""' "${CONFIG_FILE}")"
country_ipv6_template="$(jq -r '.country.ipv6URLTemplate // ""' "${CONFIG_FILE}")"
mapfile -t country_codes < <(jq -r '.country.countries[]?' "${CONFIG_FILE}")
country_port_deny_enabled="$(jq -r '.country.portDeny.enable // false' "${CONFIG_FILE}")"
mapfile -t country_port_deny_codes < <(jq -r '.country.portDeny.countries[]?' "${CONFIG_FILE}")
mapfile -t country_port_deny_tcp_ports < <(jq -r '.country.portDeny.tcpPorts[]?' "${CONFIG_FILE}")
mapfile -t country_port_deny_udp_ports < <(jq -r '.country.portDeny.udpPorts[]?' "${CONFIG_FILE}")

if [[ "${country_mode}" != "deny" && "${country_mode}" != "allow" ]]; then
  fail "country.mode must be one of: deny, allow"
fi

: > "${TMP_DIR}/country-v4.raw"
: > "${TMP_DIR}/country-v6.raw"
: > "${TMP_DIR}/country-port-deny-v4.raw"
: > "${TMP_DIR}/country-port-deny-v6.raw"

if [[ "${country_enabled}" == "true" ]]; then
  jq -r '.country.extraIPv4[]?' "${CONFIG_FILE}" >> "${TMP_DIR}/country-v4.raw"
  jq -r '.country.extraIPv6[]?' "${CONFIG_FILE}" >> "${TMP_DIR}/country-v6.raw"

  for cc in "${country_codes[@]}"; do
    cc_lc="$(printf '%s' "${cc}" | tr '[:upper:]' '[:lower:]')"
    fetch_country_data_for_code "${cc_lc}" "${TMP_DIR}/country-v4.raw" "${TMP_DIR}/country-v6.raw"
  done
fi

if [[ "${country_port_deny_enabled}" == "true" ]]; then
  jq -r '.country.portDeny.extraIPv4[]?' "${CONFIG_FILE}" >> "${TMP_DIR}/country-port-deny-v4.raw"
  jq -r '.country.portDeny.extraIPv6[]?' "${CONFIG_FILE}" >> "${TMP_DIR}/country-port-deny-v6.raw"

  for cc in "${country_port_deny_codes[@]}"; do
    cc_lc="$(printf '%s' "${cc}" | tr '[:upper:]' '[:lower:]')"
    fetch_country_data_for_code "${cc_lc}" "${TMP_DIR}/country-port-deny-v4.raw" "${TMP_DIR}/country-port-deny-v6.raw"
  done
fi

normalize_cidrs "${TMP_DIR}/country-v4.raw" "${TMP_DIR}/country-v4.norm" "${TMP_DIR}/country-v4.ignore"
normalize_cidrs "${TMP_DIR}/country-v6.raw" "${TMP_DIR}/country-v6.ignore" "${TMP_DIR}/country-v6.norm"
sort_unique "${TMP_DIR}/country-v4.norm" "${TMP_DIR}/country-v4.txt"
sort_unique "${TMP_DIR}/country-v6.norm" "${TMP_DIR}/country-v6.txt"
normalize_cidrs "${TMP_DIR}/country-port-deny-v4.raw" "${TMP_DIR}/country-port-deny-v4.norm" "${TMP_DIR}/country-port-deny-v4.ignore"
normalize_cidrs "${TMP_DIR}/country-port-deny-v6.raw" "${TMP_DIR}/country-port-deny-v6.ignore" "${TMP_DIR}/country-port-deny-v6.norm"
sort_unique "${TMP_DIR}/country-port-deny-v4.norm" "${TMP_DIR}/country-port-deny-v4.txt"
sort_unique "${TMP_DIR}/country-port-deny-v6.norm" "${TMP_DIR}/country-port-deny-v6.txt"

country_allow_v4_enforced="false"
country_allow_v6_enforced="false"

if [[ "${country_enabled}" == "true" && "${country_mode}" == "allow" ]]; then
  has_country_v4="false"
  has_country_v6="false"

  if [[ -s "${TMP_DIR}/country-v4.txt" ]]; then
    has_country_v4="true"
    country_allow_v4_enforced="true"
  fi

  if [[ -s "${TMP_DIR}/country-v6.txt" ]]; then
    has_country_v6="true"
    country_allow_v6_enforced="true"
  fi

  if [[ "${has_country_v4}" == "false" && "${has_country_v6}" == "false" ]]; then
    if [[ "${country_fail_open}" == "true" ]]; then
      warn "country mode is allow, but no country data is available; skipping allow enforcement due to failOpen"
    else
      fail "country mode is allow, but no country data is available"
    fi
  fi
fi

country_port_deny_v4_enforced="false"
country_port_deny_v6_enforced="false"

if [[ "${country_port_deny_enabled}" == "true" ]]; then
  has_port_deny_v4="false"
  has_port_deny_v6="false"

  if [[ -s "${TMP_DIR}/country-port-deny-v4.txt" ]]; then
    has_port_deny_v4="true"
    country_port_deny_v4_enforced="true"
  fi

  if [[ -s "${TMP_DIR}/country-port-deny-v6.txt" ]]; then
    has_port_deny_v6="true"
    country_port_deny_v6_enforced="true"
  fi

  if [[ "${has_port_deny_v4}" == "false" && "${has_port_deny_v6}" == "false" ]]; then
    if [[ "${country_fail_open}" == "true" ]]; then
      warn "country.portDeny is enabled, but no country data is available; skipping port deny enforcement due to failOpen"
    else
      fail "country.portDeny is enabled, but no country data is available"
    fi
  fi
fi

blocklists_enabled="$(jq -r '.blocklists.enable' "${CONFIG_FILE}")"
blocklists_fail_open="$(jq -r '.blocklists.failOpen' "${CONFIG_FILE}")"
mapfile -t blocklist_urls < <(jq -r '.blocklists.urls[]?' "${CONFIG_FILE}")

: > "${TMP_DIR}/feeds.raw"
if [[ "${blocklists_enabled}" == "true" ]]; then
  for url in "${blocklist_urls[@]}"; do
    hash="$(printf '%s' "${url}" | sha256sum | awk '{print $1}')"
    cache_file="${CACHE_DIR}/feed-${hash}.txt"

    if [[ "${MODE}" == "refresh" ]]; then
      if ! fetch_to_cache "${url}" "${cache_file}"; then
        if [[ -s "${cache_file}" ]]; then
          warn "failed to refresh ${url}; using cached data"
        elif [[ "${blocklists_fail_open}" == "true" ]]; then
          warn "failed to fetch ${url}; continuing due to failOpen"
        else
          fail "failed to fetch ${url} and no cache exists"
        fi
      fi
    elif [[ "${blocklists_fail_open}" != "true" && ! -s "${cache_file}" ]]; then
      fail "blocklists.failOpen=false and no cached data is available for ${url}"
    fi

    append_if_exists "${cache_file}" "${TMP_DIR}/feeds.raw"
  done
fi

normalize_cidrs "${TMP_DIR}/feeds.raw" "${TMP_DIR}/feeds-v4.norm" "${TMP_DIR}/feeds-v6.norm"
sort_unique "${TMP_DIR}/feeds-v4.norm" "${TMP_DIR}/feeds-v4.txt"
sort_unique "${TMP_DIR}/feeds-v6.norm" "${TMP_DIR}/feeds-v6.txt"

cluster_policy_enabled="$(jq -r '.clusterPolicy.enable // false' "${CONFIG_FILE}")"
cluster_policy_url="$(jq -r '.clusterPolicy.url // ""' "${CONFIG_FILE}")"
cluster_policy_fail_open="$(jq -r 'if .clusterPolicy.failOpen == null then true else .clusterPolicy.failOpen end' "${CONFIG_FILE}")"
cluster_policy_auth_token_file_legacy="$(jq -r '.clusterPolicy.authTokenFile // ""' "${CONFIG_FILE}")"
mapfile -t cluster_policy_auth_token_files < <(jq -r '.clusterPolicy.authTokenFiles[]?' "${CONFIG_FILE}")
cluster_policy_node_id="$(jq -r '.clusterPolicy.nodeId // ""' "${CONFIG_FILE}")"
cluster_policy_source_count="0"
cluster_policy_schema_version="1"
cluster_policy_revision="none"
cluster_policy_ttl_seconds="0"
cluster_policy_cache_age_seconds="0"
cluster_policy_cache_expired="false"

if [[ -n "${cluster_policy_auth_token_file_legacy}" && "${#cluster_policy_auth_token_files[@]}" -gt 0 ]]; then
  fail "clusterPolicy.authTokenFile cannot be combined with clusterPolicy.authTokenFiles"
fi

if [[ -n "${cluster_policy_auth_token_file_legacy}" ]]; then
  cluster_policy_auth_token_files=( "${cluster_policy_auth_token_file_legacy}" )
fi

: > "${TMP_DIR}/cluster-allow-v4.raw"
: > "${TMP_DIR}/cluster-allow-v6.raw"
: > "${TMP_DIR}/cluster-deny-v4.raw"
: > "${TMP_DIR}/cluster-deny-v6.raw"
: > "${TMP_DIR}/cluster-ignore-v4.raw"
: > "${TMP_DIR}/cluster-ignore-v6.raw"

if [[ "${cluster_policy_enabled}" == "true" ]]; then
  cluster_policy_source_count="1"
  cluster_policy_cache="${CACHE_DIR}/cluster-policy.json"
  if [[ "${#cluster_policy_auth_token_files[@]}" -gt 0 ]]; then
    load_auth_tokens_from_files "cluster policy" cluster_policy_auth_token_files cluster_policy_auth_tokens
  else
    cluster_policy_auth_tokens=()
  fi
  cluster_policy_auth_token_candidate_count="${#cluster_policy_auth_tokens[@]}"

  if [[ "${MODE}" == "refresh" ]]; then
    cluster_fetch_rc=0
    if fetch_cluster_policy_to_cache "${cluster_policy_url}" "${cluster_policy_cache}"; then
      cluster_fetch_rc=0
    else
      cluster_fetch_rc=$?
      if [[ "${cluster_fetch_rc}" -eq 2 ]]; then
        if [[ -s "${cluster_policy_cache}" ]]; then
          warn "invalid JSON from cluster policy ${cluster_policy_url}; using cached data"
        elif [[ "${cluster_policy_fail_open}" == "true" ]]; then
          warn "invalid JSON from cluster policy ${cluster_policy_url}; continuing due to failOpen"
        else
          fail "invalid JSON from cluster policy ${cluster_policy_url} and no cache exists"
        fi
      elif [[ "${cluster_fetch_rc}" -eq 3 ]]; then
        if [[ -s "${cluster_policy_cache}" ]]; then
          warn "cluster policy ${cluster_policy_url} failed schema validation; using cached data"
        elif [[ "${cluster_policy_fail_open}" == "true" ]]; then
          warn "cluster policy ${cluster_policy_url} failed schema validation; continuing due to failOpen"
        else
          fail "cluster policy ${cluster_policy_url} failed schema validation and no cache exists"
        fi
      elif [[ -s "${cluster_policy_cache}" ]]; then
        warn "failed to refresh cluster policy ${cluster_policy_url}; using cached data"
      elif [[ "${cluster_policy_fail_open}" == "true" ]]; then
        warn "failed to fetch cluster policy ${cluster_policy_url}; continuing due to failOpen"
      else
        fail "failed to fetch cluster policy ${cluster_policy_url} and no cache exists"
      fi
    fi
  elif [[ "${cluster_policy_fail_open}" != "true" && ! -s "${cluster_policy_cache}" ]]; then
    fail "clusterPolicy.failOpen=false and no cached policy is available for ${cluster_policy_url}"
  fi

  if [[ -s "${cluster_policy_cache}" ]]; then
    if ! validate_cluster_policy_schema "${cluster_policy_cache}"; then
      if [[ "${cluster_policy_fail_open}" == "true" ]]; then
        warn "cached cluster policy failed schema validation; skipping merge due to failOpen"
      else
        fail "cached cluster policy failed schema validation"
      fi
    else
      cluster_policy_schema_version="$(jq -r 'if .schemaVersion == null then "1" else (.schemaVersion | tostring) end' "${cluster_policy_cache}")"
      cluster_policy_revision="$(jq -r 'if .revision == null then "none" else (.revision | tostring) end' "${cluster_policy_cache}")"
      cluster_policy_ttl_seconds="$(jq -r '(.ttlSeconds // 0) | tostring' "${cluster_policy_cache}")"
      cluster_policy_cache_age_seconds="$(( $(date +%s) - $(stat -c %Y "${cluster_policy_cache}") ))"

      if [[ "${cluster_policy_ttl_seconds}" =~ ^[0-9]+$ ]] \
        && [[ "${cluster_policy_ttl_seconds}" -gt 0 ]] \
        && [[ "${cluster_policy_cache_age_seconds}" -gt "${cluster_policy_ttl_seconds}" ]]; then
        cluster_policy_cache_expired="true"
        if [[ "${cluster_policy_fail_open}" == "true" ]]; then
          warn "cached cluster policy expired (ttlSeconds=${cluster_policy_ttl_seconds}, age=${cluster_policy_cache_age_seconds}); skipping merge due to failOpen"
        else
          fail "cached cluster policy expired (ttlSeconds=${cluster_policy_ttl_seconds}, age=${cluster_policy_cache_age_seconds})"
        fi
      else
        jq -r '.allowIPv4[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-allow-v4.raw"
        jq -r '.allowIPv6[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-allow-v6.raw"
        jq -r '.denyIPv4[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-deny-v4.raw"
        jq -r '.denyIPv6[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-deny-v6.raw"
        jq -r '.ignoreIPv4[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-ignore-v4.raw"
        jq -r '.ignoreIPv6[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-ignore-v6.raw"
      fi
    fi
  fi
fi

normalize_cidrs "${TMP_DIR}/cluster-allow-v4.raw" "${TMP_DIR}/cluster-allow-v4.norm" "${TMP_DIR}/cluster-allow-v4.ignore"
normalize_cidrs "${TMP_DIR}/cluster-allow-v6.raw" "${TMP_DIR}/cluster-allow-v6.ignore" "${TMP_DIR}/cluster-allow-v6.norm"
normalize_cidrs "${TMP_DIR}/cluster-deny-v4.raw" "${TMP_DIR}/cluster-deny-v4.norm" "${TMP_DIR}/cluster-deny-v4.ignore"
normalize_cidrs "${TMP_DIR}/cluster-deny-v6.raw" "${TMP_DIR}/cluster-deny-v6.ignore" "${TMP_DIR}/cluster-deny-v6.norm"
normalize_cidrs "${TMP_DIR}/cluster-ignore-v4.raw" "${TMP_DIR}/cluster-ignore-v4.norm" "${TMP_DIR}/cluster-ignore-v4.ignore"
normalize_cidrs "${TMP_DIR}/cluster-ignore-v6.raw" "${TMP_DIR}/cluster-ignore-v6.ignore" "${TMP_DIR}/cluster-ignore-v6.norm"

sort_unique "${TMP_DIR}/cluster-allow-v4.norm" "${TMP_DIR}/cluster-allow-v4.txt"
sort_unique "${TMP_DIR}/cluster-allow-v6.norm" "${TMP_DIR}/cluster-allow-v6.txt"
sort_unique "${TMP_DIR}/cluster-deny-v4.norm" "${TMP_DIR}/cluster-deny-v4.txt"
sort_unique "${TMP_DIR}/cluster-deny-v6.norm" "${TMP_DIR}/cluster-deny-v6.txt"
sort_unique "${TMP_DIR}/cluster-ignore-v4.norm" "${TMP_DIR}/cluster-ignore-v4.txt"
sort_unique "${TMP_DIR}/cluster-ignore-v6.norm" "${TMP_DIR}/cluster-ignore-v6.txt"

merge_sorted_overlay "${TMP_DIR}/allow-v4.txt" "${TMP_DIR}/cluster-allow-v4.txt"
merge_sorted_overlay "${TMP_DIR}/allow-v6.txt" "${TMP_DIR}/cluster-allow-v6.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v4.txt" "${TMP_DIR}/cluster-deny-v4.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v6.txt" "${TMP_DIR}/cluster-deny-v6.txt"

: > "${TMP_DIR}/effective-ignore-v4.txt"
: > "${TMP_DIR}/effective-ignore-v6.txt"
merge_sorted_overlay "${TMP_DIR}/effective-ignore-v4.txt" "${TMP_DIR}/cluster-ignore-v4.txt"
merge_sorted_overlay "${TMP_DIR}/effective-ignore-v6.txt" "${TMP_DIR}/cluster-ignore-v6.txt"
merge_sorted_overlay "${TMP_DIR}/effective-ignore-v4.txt" "${TMP_DIR}/local-ignore-v4.txt"
merge_sorted_overlay "${TMP_DIR}/effective-ignore-v6.txt" "${TMP_DIR}/local-ignore-v6.txt"

if [[ -s "${TMP_DIR}/effective-ignore-v4.txt" ]]; then
  merge_sorted_overlay "${TMP_DIR}/allow-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
  subtract_sorted_overlay "${TMP_DIR}/deny-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
  subtract_sorted_overlay "${TMP_DIR}/country-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
  subtract_sorted_overlay "${TMP_DIR}/country-port-deny-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
  subtract_sorted_overlay "${TMP_DIR}/feeds-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
  subtract_sorted_overlay "${TMP_DIR}/cluster-deny-v4.txt" "${TMP_DIR}/effective-ignore-v4.txt"
fi

if [[ -s "${TMP_DIR}/effective-ignore-v6.txt" ]]; then
  merge_sorted_overlay "${TMP_DIR}/allow-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
  subtract_sorted_overlay "${TMP_DIR}/deny-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
  subtract_sorted_overlay "${TMP_DIR}/country-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
  subtract_sorted_overlay "${TMP_DIR}/country-port-deny-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
  subtract_sorted_overlay "${TMP_DIR}/feeds-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
  subtract_sorted_overlay "${TMP_DIR}/cluster-deny-v6.txt" "${TMP_DIR}/effective-ignore-v6.txt"
fi

dynamic_offenders_url="$(jq -r '.dynamicOffenders.url // ""' "${CONFIG_FILE}")"
dynamic_offenders_fail_open="$(jq -r 'if .dynamicOffenders.failOpen == null then true else .dynamicOffenders.failOpen end' "${CONFIG_FILE}")"
dynamic_offenders_auth_token_file_legacy="$(jq -r '.dynamicOffenders.authTokenFile // ""' "${CONFIG_FILE}")"
mapfile -t dynamic_offenders_auth_token_files < <(jq -r '.dynamicOffenders.authTokenFiles[]?' "${CONFIG_FILE}")
dynamic_offenders_node_id="$(jq -r '.dynamicOffenders.nodeId // ""' "${CONFIG_FILE}")"
dynamic_offenders_source_count="0"
dynamic_offenders_schema_version="1"
dynamic_offenders_revision="none"
dynamic_offenders_ttl_seconds="0"
dynamic_offenders_cache_age_seconds="0"
dynamic_offenders_cache_expired="false"

if [[ -n "${dynamic_offenders_auth_token_file_legacy}" && "${#dynamic_offenders_auth_token_files[@]}" -gt 0 ]]; then
  fail "dynamicOffenders.authTokenFile cannot be combined with dynamicOffenders.authTokenFiles"
fi

if [[ -n "${dynamic_offenders_auth_token_file_legacy}" ]]; then
  dynamic_offenders_auth_token_files=( "${dynamic_offenders_auth_token_file_legacy}" )
fi

: > "${TMP_DIR}/dynamic-ban-v4.txt"
: > "${TMP_DIR}/dynamic-ban-v6.txt"

if [[ "${dynamic_offenders_enabled}" == "true" ]]; then
  dynamic_offenders_source_count="1"
  dynamic_offenders_cache="${CACHE_DIR}/dynamic-offenders.json"
  if [[ "${#dynamic_offenders_auth_token_files[@]}" -gt 0 ]]; then
    load_auth_tokens_from_files "dynamic offenders" dynamic_offenders_auth_token_files dynamic_offenders_auth_tokens
  else
    dynamic_offenders_auth_tokens=()
  fi
  dynamic_offenders_auth_token_candidate_count="${#dynamic_offenders_auth_tokens[@]}"

  if [[ "${MODE}" == "refresh" ]]; then
    dynamic_fetch_rc=0
    if fetch_dynamic_offenders_to_cache "${dynamic_offenders_url}" "${dynamic_offenders_cache}"; then
      dynamic_fetch_rc=0
    else
      dynamic_fetch_rc=$?
      if [[ "${dynamic_fetch_rc}" -eq 2 ]]; then
        if [[ -s "${dynamic_offenders_cache}" ]]; then
          warn "invalid JSON from dynamic offenders ${dynamic_offenders_url}; using cached data"
        elif [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
          warn "invalid JSON from dynamic offenders ${dynamic_offenders_url}; continuing due to failOpen"
        else
          fail "invalid JSON from dynamic offenders ${dynamic_offenders_url} and no cache exists"
        fi
      elif [[ "${dynamic_fetch_rc}" -eq 3 ]]; then
        if [[ -s "${dynamic_offenders_cache}" ]]; then
          warn "dynamic offenders ${dynamic_offenders_url} failed schema validation; using cached data"
        elif [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
          warn "dynamic offenders ${dynamic_offenders_url} failed schema validation; continuing due to failOpen"
        else
          fail "dynamic offenders ${dynamic_offenders_url} failed schema validation and no cache exists"
        fi
      elif [[ -s "${dynamic_offenders_cache}" ]]; then
        warn "failed to refresh dynamic offenders ${dynamic_offenders_url}; using cached data"
      elif [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
        warn "failed to fetch dynamic offenders ${dynamic_offenders_url}; continuing due to failOpen"
      else
        fail "failed to fetch dynamic offenders ${dynamic_offenders_url} and no cache exists"
      fi
    fi
  elif [[ "${dynamic_offenders_fail_open}" != "true" && ! -s "${dynamic_offenders_cache}" ]]; then
    fail "dynamicOffenders.failOpen=false and no cached data is available for ${dynamic_offenders_url}"
  fi

  if [[ -s "${dynamic_offenders_cache}" ]]; then
    if ! validate_dynamic_offenders_schema "${dynamic_offenders_cache}"; then
      if [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
        warn "cached dynamic offenders snapshot failed schema validation; skipping merge due to failOpen"
      else
        fail "cached dynamic offenders snapshot failed schema validation"
      fi
    else
      dynamic_offenders_schema_version="$(jq -r 'if .schemaVersion == null then "1" else (.schemaVersion | tostring) end' "${dynamic_offenders_cache}")"
      dynamic_offenders_revision="$(jq -r 'if .revision == null then "none" else (.revision | tostring) end' "${dynamic_offenders_cache}")"
      dynamic_offenders_ttl_seconds="$(jq -r '(.ttlSeconds // 0) | tostring' "${dynamic_offenders_cache}")"
      dynamic_offenders_cache_age_seconds="$(( $(date +%s) - $(stat -c %Y "${dynamic_offenders_cache}") ))"

      if [[ "${dynamic_offenders_ttl_seconds}" =~ ^[0-9]+$ ]] \
        && [[ "${dynamic_offenders_ttl_seconds}" -gt 0 ]] \
        && [[ "${dynamic_offenders_cache_age_seconds}" -gt "${dynamic_offenders_ttl_seconds}" ]]; then
        dynamic_offenders_cache_expired="true"
        if [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
          warn "cached dynamic offenders snapshot expired (ttlSeconds=${dynamic_offenders_ttl_seconds}, age=${dynamic_offenders_cache_age_seconds}); skipping merge due to failOpen"
        else
          fail "cached dynamic offenders snapshot expired (ttlSeconds=${dynamic_offenders_ttl_seconds}, age=${dynamic_offenders_cache_age_seconds})"
        fi
      else
        dynamic_total_entries="$(jq -r '((.banIPv4 // []) | length) + ((.banIPv6 // []) | length)' "${dynamic_offenders_cache}")"
        if [[ "${dynamic_total_entries}" =~ ^[0-9]+$ ]] \
          && [[ "${dynamic_total_entries}" -gt "${dynamic_offenders_max_entries}" ]]; then
          if [[ "${dynamic_offenders_fail_open}" == "true" ]]; then
            warn "dynamic offenders snapshot exceeds maxEntries (${dynamic_total_entries} > ${dynamic_offenders_max_entries}); skipping merge due to failOpen"
          else
            fail "dynamic offenders snapshot exceeds maxEntries (${dynamic_total_entries} > ${dynamic_offenders_max_entries})"
          fi
        else
          now_epoch="$(date +%s)"

          jq -r \
            --argjson now_epoch "${now_epoch}" \
            --argjson default_ttl "${dynamic_offenders_default_entry_ttl_seconds}" '
              (.banIPv4 // [])[]
              | if type == "string" then
                  "\(.)|\($default_ttl)"
                else
                  "\(.cidr)|\(
                    if .expiresAt != null then ((.expiresAt | floor) - $now_epoch)
                    elif .ttlSeconds != null then (.ttlSeconds | floor)
                    else $default_ttl
                    end
                  )"
                end
            ' "${dynamic_offenders_cache}" > "${TMP_DIR}/dynamic-ban-v4.raw"

          jq -r \
            --argjson now_epoch "${now_epoch}" \
            --argjson default_ttl "${dynamic_offenders_default_entry_ttl_seconds}" '
              (.banIPv6 // [])[]
              | if type == "string" then
                  "\(.)|\($default_ttl)"
                else
                  "\(.cidr)|\(
                    if .expiresAt != null then ((.expiresAt | floor) - $now_epoch)
                    elif .ttlSeconds != null then (.ttlSeconds | floor)
                    else $default_ttl
                    end
                  )"
                end
            ' "${dynamic_offenders_cache}" > "${TMP_DIR}/dynamic-ban-v6.raw"

          sanitize_dynamic_entry_pairs "${TMP_DIR}/dynamic-ban-v4.raw" "${TMP_DIR}/dynamic-ban-v4.sanitized"
          sanitize_dynamic_entry_pairs "${TMP_DIR}/dynamic-ban-v6.raw" "${TMP_DIR}/dynamic-ban-v6.sanitized"
          build_dynamic_timeout_set_v4 "${TMP_DIR}/dynamic-ban-v4.sanitized" "${TMP_DIR}/dynamic-ban-v4.txt"
          build_dynamic_timeout_set_v6 "${TMP_DIR}/dynamic-ban-v6.sanitized" "${TMP_DIR}/dynamic-ban-v6.txt"
        fi
      fi
    fi
  fi
fi

mapfile -t trusted_interfaces < <(jq -r '.trustedInterfaces[]?' "${CONFIG_FILE}")
mapfile -t open_tcp_ports < <(jq -r '.openTCPPorts[]?' "${CONFIG_FILE}")
mapfile -t open_udp_ports < <(jq -r '.openUDPPorts[]?' "${CONFIG_FILE}")

allow_v4_count="$(count_file_lines "${TMP_DIR}/allow-v4.txt")"
allow_v6_count="$(count_file_lines "${TMP_DIR}/allow-v6.txt")"
deny_v4_count="$(count_file_lines "${TMP_DIR}/deny-v4.txt")"
deny_v6_count="$(count_file_lines "${TMP_DIR}/deny-v6.txt")"
country_v4_count="$(count_file_lines "${TMP_DIR}/country-v4.txt")"
country_v6_count="$(count_file_lines "${TMP_DIR}/country-v6.txt")"
country_port_deny_v4_count="$(count_file_lines "${TMP_DIR}/country-port-deny-v4.txt")"
country_port_deny_v6_count="$(count_file_lines "${TMP_DIR}/country-port-deny-v6.txt")"
feed_v4_count="$(count_file_lines "${TMP_DIR}/feeds-v4.txt")"
feed_v6_count="$(count_file_lines "${TMP_DIR}/feeds-v6.txt")"
local_allow_v4_count="$(count_file_lines "${TMP_DIR}/local-allow-v4.txt")"
local_allow_v6_count="$(count_file_lines "${TMP_DIR}/local-allow-v6.txt")"
local_deny_v4_count="$(count_file_lines "${TMP_DIR}/local-deny-v4.txt")"
local_deny_v6_count="$(count_file_lines "${TMP_DIR}/local-deny-v6.txt")"
local_ignore_v4_count="$(count_file_lines "${TMP_DIR}/local-ignore-v4.txt")"
local_ignore_v6_count="$(count_file_lines "${TMP_DIR}/local-ignore-v6.txt")"
effective_ignore_v4_count="$(count_file_lines "${TMP_DIR}/effective-ignore-v4.txt")"
effective_ignore_v6_count="$(count_file_lines "${TMP_DIR}/effective-ignore-v6.txt")"
cluster_allow_v4_count="$(count_file_lines "${TMP_DIR}/cluster-allow-v4.txt")"
cluster_allow_v6_count="$(count_file_lines "${TMP_DIR}/cluster-allow-v6.txt")"
cluster_deny_v4_count="$(count_file_lines "${TMP_DIR}/cluster-deny-v4.txt")"
cluster_deny_v6_count="$(count_file_lines "${TMP_DIR}/cluster-deny-v6.txt")"
cluster_ignore_v4_count="$(count_file_lines "${TMP_DIR}/cluster-ignore-v4.txt")"
cluster_ignore_v6_count="$(count_file_lines "${TMP_DIR}/cluster-ignore-v6.txt")"
dynamic_ban_v4_count="$(count_file_lines "${TMP_DIR}/dynamic-ban-v4.txt")"
dynamic_ban_v6_count="$(count_file_lines "${TMP_DIR}/dynamic-ban-v6.txt")"

log_event "stdout" "info" "set_counts" \
  "allow_v4=${allow_v4_count}" \
  "allow_v6=${allow_v6_count}" \
  "deny_v4=${deny_v4_count}" \
  "deny_v6=${deny_v6_count}" \
  "country_v4=${country_v4_count}" \
  "country_v6=${country_v6_count}" \
  "country_port_deny_v4=${country_port_deny_v4_count}" \
  "country_port_deny_v6=${country_port_deny_v6_count}" \
  "feed_v4=${feed_v4_count}" \
  "feed_v6=${feed_v6_count}" \
  "local_allow_v4=${local_allow_v4_count}" \
  "local_allow_v6=${local_allow_v6_count}" \
  "local_deny_v4=${local_deny_v4_count}" \
  "local_deny_v6=${local_deny_v6_count}" \
  "local_ignore_v4=${local_ignore_v4_count}" \
  "local_ignore_v6=${local_ignore_v6_count}" \
  "effective_ignore_v4=${effective_ignore_v4_count}" \
  "effective_ignore_v6=${effective_ignore_v6_count}" \
  "cluster_allow_v4=${cluster_allow_v4_count}" \
  "cluster_allow_v6=${cluster_allow_v6_count}" \
  "cluster_deny_v4=${cluster_deny_v4_count}" \
  "cluster_deny_v6=${cluster_deny_v6_count}" \
  "cluster_ignore_v4=${cluster_ignore_v4_count}" \
  "cluster_ignore_v6=${cluster_ignore_v6_count}" \
  "dynamic_ban_v4=${dynamic_ban_v4_count}" \
  "dynamic_ban_v6=${dynamic_ban_v6_count}"

if [[ "${cluster_policy_enabled}" == "true" ]]; then
  log_event "stdout" "info" "cluster_policy_meta" \
    "schema_version=${cluster_policy_schema_version}" \
    "revision=${cluster_policy_revision}" \
    "ttl_seconds=${cluster_policy_ttl_seconds}" \
    "cache_age_seconds=${cluster_policy_cache_age_seconds}" \
    "cache_expired=${cluster_policy_cache_expired}" \
    "auth_candidates=${cluster_policy_auth_token_candidate_count}" \
    "auth_selected_slot=${cluster_policy_auth_token_selected_slot}"
fi

if [[ "${dynamic_offenders_enabled}" == "true" ]]; then
  log_event "stdout" "info" "dynamic_offenders_meta" \
    "schema_version=${dynamic_offenders_schema_version}" \
    "revision=${dynamic_offenders_revision}" \
    "ttl_seconds=${dynamic_offenders_ttl_seconds}" \
    "cache_age_seconds=${dynamic_offenders_cache_age_seconds}" \
    "cache_expired=${dynamic_offenders_cache_expired}" \
    "auth_candidates=${dynamic_offenders_auth_token_candidate_count}" \
    "auth_selected_slot=${dynamic_offenders_auth_token_selected_slot}" \
    "ban_v4=${dynamic_ban_v4_count}" \
    "ban_v6=${dynamic_ban_v6_count}"
fi

render_port_set() {
  # shellcheck disable=SC2178
  local -n ports_ref="$1"
  local IFS=", "
  printf '%s' "${ports_ref[*]}"
}

render_token_set() {
  # shellcheck disable=SC2178
  local -n tokens_ref="$1"
  local IFS=", "
  printf '%s' "${tokens_ref[*]}"
}

tmp_rules="${TMP_DIR}/ruleset.nft"

{
  echo "table inet nix_csf {"
  emit_set "allow_ipv4" "ipv4_addr" "${TMP_DIR}/allow-v4.txt"
  emit_set "allow_ipv6" "ipv6_addr" "${TMP_DIR}/allow-v6.txt"
  emit_set "deny_ipv4" "ipv4_addr" "${TMP_DIR}/deny-v4.txt"
  emit_set "deny_ipv6" "ipv6_addr" "${TMP_DIR}/deny-v6.txt"
  emit_set "country_ipv4" "ipv4_addr" "${TMP_DIR}/country-v4.txt"
  emit_set "country_ipv6" "ipv6_addr" "${TMP_DIR}/country-v6.txt"
  emit_set "country_port_deny_ipv4" "ipv4_addr" "${TMP_DIR}/country-port-deny-v4.txt"
  emit_set "country_port_deny_ipv6" "ipv6_addr" "${TMP_DIR}/country-port-deny-v6.txt"
  emit_set "feed_ipv4" "ipv4_addr" "${TMP_DIR}/feeds-v4.txt"
  emit_set "feed_ipv6" "ipv6_addr" "${TMP_DIR}/feeds-v6.txt"
  emit_set "dynamic_ban_ipv4" "ipv4_addr" "${TMP_DIR}/dynamic-ban-v4.txt" "interval,timeout"
  emit_set "dynamic_ban_ipv6" "ipv6_addr" "${TMP_DIR}/dynamic-ban-v6.txt" "interval,timeout"

  echo "  chain input {"
  echo "    type filter hook input priority filter; policy ${default_policy};"
  echo "    ct state invalid drop"
  echo "    ct state established,related accept"
  echo "    iifname \"lo\" accept"

  for iface in "${trusted_interfaces[@]}"; do
    if [[ -n "${iface}" ]]; then
      printf '    iifname "%s" accept\n' "${iface}"
    fi
  done

  if [[ -n "${syn_rate_limit}" ]]; then
    printf '    tcp flags syn ct state new limit rate over %s drop\n' "${syn_rate_limit}"
  fi

  if [[ "${syn_flood_enabled}" == "true" ]]; then
    printf '    tcp flags syn ct state new meter syn_flood_v4 { ip saddr limit rate over %s burst %s packets } drop\n' "${syn_flood_rate}" "${syn_flood_burst}"
    printf '    tcp flags syn ct state new meter syn_flood_v6 { ip6 saddr limit rate over %s burst %s packets } drop\n' "${syn_flood_rate}" "${syn_flood_burst}"
  fi

  if [[ "${conn_flood_enabled}" == "true" ]]; then
    printf '    ct state new meter conn_flood_v4 { ip saddr limit rate over %s burst %s packets } drop\n' "${conn_flood_rate}" "${conn_flood_burst}"
    printf '    ct state new meter conn_flood_v6 { ip6 saddr limit rate over %s burst %s packets } drop\n' "${conn_flood_rate}" "${conn_flood_burst}"
  fi

  echo "    ip saddr @deny_ipv4 drop"
  echo "    ip6 saddr @deny_ipv6 drop"

  echo "    ip saddr @allow_ipv4 accept"
  echo "    ip6 saddr @allow_ipv6 accept"

  if [[ "${country_enabled}" == "true" && "${country_mode}" == "deny" ]]; then
    echo "    ip saddr @country_ipv4 drop"
    echo "    ip6 saddr @country_ipv6 drop"
  fi

  if [[ "${country_enabled}" == "true" && "${country_mode}" == "allow" ]]; then
    if [[ "${country_allow_v4_enforced}" == "true" ]]; then
      echo "    ip saddr != @country_ipv4 drop"
    fi
    if [[ "${country_allow_v6_enforced}" == "true" ]]; then
      echo "    ip6 saddr != @country_ipv6 drop"
    fi
  fi

  if [[ "${country_port_deny_enabled}" == "true" ]]; then
    if [[ "${#country_port_deny_tcp_ports[@]}" -gt 0 ]]; then
      if [[ "${country_port_deny_v4_enforced}" == "true" ]]; then
        printf '    ip saddr @country_port_deny_ipv4 tcp dport { %s } drop\n' "$(render_port_set country_port_deny_tcp_ports)"
      fi
      if [[ "${country_port_deny_v6_enforced}" == "true" ]]; then
        printf '    ip6 saddr @country_port_deny_ipv6 tcp dport { %s } drop\n' "$(render_port_set country_port_deny_tcp_ports)"
      fi
    fi

    if [[ "${#country_port_deny_udp_ports[@]}" -gt 0 ]]; then
      if [[ "${country_port_deny_v4_enforced}" == "true" ]]; then
        printf '    ip saddr @country_port_deny_ipv4 udp dport { %s } drop\n' "$(render_port_set country_port_deny_udp_ports)"
      fi
      if [[ "${country_port_deny_v6_enforced}" == "true" ]]; then
        printf '    ip6 saddr @country_port_deny_ipv6 udp dport { %s } drop\n' "$(render_port_set country_port_deny_udp_ports)"
      fi
    fi
  fi

  if [[ "${blocklists_enabled}" == "true" ]]; then
    echo "    ip saddr @feed_ipv4 drop"
    echo "    ip6 saddr @feed_ipv6 drop"
  fi

  if [[ "${dynamic_offenders_enabled}" == "true" ]]; then
    echo "    ip saddr @dynamic_ban_ipv4 drop"
    echo "    ip6 saddr @dynamic_ban_ipv6 drop"
  fi

  if [[ "${#open_tcp_ports[@]}" -gt 0 ]]; then
    printf '    tcp dport { %s } accept\n' "$(render_port_set open_tcp_ports)"
  fi

  if [[ "${#open_udp_ports[@]}" -gt 0 ]]; then
    printf '    udp dport { %s } accept\n' "$(render_port_set open_udp_ports)"
  fi

  if [[ "${icmp_profile}" == "legacy" ]]; then
    if [[ "${allow_icmp}" == "true" ]]; then
      echo "    ip protocol icmp accept"
      echo "    ip6 nexthdr ipv6-icmp accept"
    fi
  elif [[ "${icmp_emit_open_accept}" == "true" ]]; then
    printf '    ip protocol icmp%s accept\n' "${icmp_rate_limit_clause}"
    printf '    ip6 nexthdr ipv6-icmp%s accept\n' "${icmp_rate_limit_clause}"
  elif [[ "${icmp_emit_type_accept}" == "true" ]]; then
    if [[ "${#icmp_profile_v4_types[@]}" -gt 0 ]]; then
      printf '    icmp type { %s }%s accept\n' "$(render_token_set icmp_profile_v4_types)" "${icmp_rate_limit_clause}"
    fi
    if [[ "${#icmp_profile_v6_types[@]}" -gt 0 ]]; then
      printf '    icmpv6 type { %s }%s accept\n' "$(render_token_set icmp_profile_v6_types)" "${icmp_rate_limit_clause}"
    fi
    # Enforce safe/diagnostic profile semantics even when policy is accept.
    echo "    ip protocol icmp drop"
    echo "    ip6 nexthdr ipv6-icmp drop"
  elif [[ "${icmp_emit_drop_all}" == "true" ]]; then
    echo "    ip protocol icmp drop"
    echo "    ip6 nexthdr ipv6-icmp drop"
  fi

  if [[ "${default_policy}" == "drop" ]]; then
    if [[ "${log_drops}" == "true" ]]; then
      echo "    log prefix \"nix-csf drop: \" level warn"
    fi
    echo "    reject with icmpx type admin-prohibited"
  fi

  echo "  }"
  echo "  chain forward {"
  echo "    type filter hook forward priority filter; policy ${forward_policy};"

  if [[ "${coexistence_profile}" == "docker-coexist" ]]; then
    # In coexistence mode keep default forward acceptance for Docker/dynamic daemons,
    # but still enforce nix-csf deny-style overlays.
    echo "    ct state invalid drop"
    echo "    ip saddr @deny_ipv4 drop"
    echo "    ip6 saddr @deny_ipv6 drop"

    if [[ "${country_enabled}" == "true" && "${country_mode}" == "deny" ]]; then
      echo "    ip saddr @country_ipv4 drop"
      echo "    ip6 saddr @country_ipv6 drop"
    fi

    if [[ "${country_port_deny_enabled}" == "true" ]]; then
      if [[ "${#country_port_deny_tcp_ports[@]}" -gt 0 ]]; then
        if [[ "${country_port_deny_v4_enforced}" == "true" ]]; then
          printf '    ip saddr @country_port_deny_ipv4 tcp dport { %s } drop\n' "$(render_port_set country_port_deny_tcp_ports)"
        fi
        if [[ "${country_port_deny_v6_enforced}" == "true" ]]; then
          printf '    ip6 saddr @country_port_deny_ipv6 tcp dport { %s } drop\n' "$(render_port_set country_port_deny_tcp_ports)"
        fi
      fi

      if [[ "${#country_port_deny_udp_ports[@]}" -gt 0 ]]; then
        if [[ "${country_port_deny_v4_enforced}" == "true" ]]; then
          printf '    ip saddr @country_port_deny_ipv4 udp dport { %s } drop\n' "$(render_port_set country_port_deny_udp_ports)"
        fi
        if [[ "${country_port_deny_v6_enforced}" == "true" ]]; then
          printf '    ip6 saddr @country_port_deny_ipv6 udp dport { %s } drop\n' "$(render_port_set country_port_deny_udp_ports)"
        fi
      fi
    fi

    if [[ "${blocklists_enabled}" == "true" ]]; then
      echo "    ip saddr @feed_ipv4 drop"
      echo "    ip6 saddr @feed_ipv6 drop"
    fi

    if [[ "${dynamic_offenders_enabled}" == "true" ]]; then
      echo "    ip saddr @dynamic_ban_ipv4 drop"
      echo "    ip6 saddr @dynamic_ban_ipv6 drop"
    fi
  fi

  echo "  }"
  echo "  chain output {"
  echo "    type filter hook output priority filter; policy accept;"
  echo "  }"
  echo "}"
} > "${tmp_rules}"

nft -c -f "${tmp_rules}"
nft delete table inet nix_csf >/dev/null 2>&1 || true
nft -f "${tmp_rules}"
install -m 0640 "${tmp_rules}" "${RULESET_FILE}"

write_metrics

run_finished_epoch="$(date +%s)"
log_event "stdout" "info" "run_complete" "duration_seconds=$(( run_finished_epoch - run_started_epoch ))"
say "rules applied (${MODE}, version ${module_version})"
