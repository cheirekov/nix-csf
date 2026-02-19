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
      gsub(/^[ \t]+|[ \t]+$/, "", $0);
      if ($0 != "") print $0;
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

append_if_exists() {
  local source_file="$1"
  local target_file="$2"
  if [[ -s "${source_file}" ]]; then
    cat "${source_file}" >> "${target_file}"
  fi
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

fetch_cluster_policy_to_cache() {
  local url="$1"
  local cache_file="$2"
  local tmp_file="${TMP_DIR}/cluster-policy-download.json"
  local -a curl_args=(--fail --location --silent --show-error --max-time 40)

  if [[ -n "${cluster_policy_node_id}" ]]; then
    curl_args+=(-H "X-Nix-Csf-Node: ${cluster_policy_node_id}")
  fi

  if [[ -n "${cluster_policy_auth_token_file}" ]]; then
    if [[ ! -f "${cluster_policy_auth_token_file}" ]]; then
      fail "cluster policy authTokenFile does not exist: ${cluster_policy_auth_token_file}"
    fi

    local auth_token
    auth_token="$(tr -d '\r\n' < "${cluster_policy_auth_token_file}")"
    if [[ -z "${auth_token}" ]]; then
      fail "cluster policy authTokenFile is empty: ${cluster_policy_auth_token_file}"
    fi

    curl_args+=(-H "Authorization: Bearer ${auth_token}")
  fi

  if curl "${curl_args[@]}" "${url}" -o "${tmp_file}"; then
    if ! jq -e . "${tmp_file}" >/dev/null 2>&1; then
      return 2
    fi
    install -m 0640 "${tmp_file}" "${cache_file}"
    return 0
  fi

  return 1
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

  echo "  set ${name} {"
  echo "    type ${nft_type}"
  echo "    flags interval"
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
    printf 'nix_csf_feature_enabled{feature="cluster_policy"} %s\n' "$(bool_to_num "${cluster_policy_enabled}")"
    printf 'nix_csf_feature_enabled{feature="log_drops"} %s\n' "$(bool_to_num "${log_drops}")"
    printf 'nix_csf_feature_enabled{feature="legacy_syn_rate_limit"} %s\n' "$(bool_to_num "${legacy_syn_rate_limit_enabled}")"
    printf 'nix_csf_feature_enabled{feature="syn_flood"} %s\n' "$(bool_to_num "${syn_flood_enabled}")"
    printf 'nix_csf_feature_enabled{feature="conn_flood"} %s\n' "$(bool_to_num "${conn_flood_enabled}")"
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
    printf 'nix_csf_set_entries{set="cluster_allow_ipv4"} %s\n' "${cluster_allow_v4_count}"
    printf 'nix_csf_set_entries{set="cluster_allow_ipv6"} %s\n' "${cluster_allow_v6_count}"
    printf 'nix_csf_set_entries{set="cluster_deny_ipv4"} %s\n' "${cluster_deny_v4_count}"
    printf 'nix_csf_set_entries{set="cluster_deny_ipv6"} %s\n' "${cluster_deny_v6_count}"
    echo "# HELP nix_csf_source_count Number of configured source identifiers."
    echo "# TYPE nix_csf_source_count gauge"
    printf 'nix_csf_source_count{source="country_codes"} %s\n' "${#country_codes[@]}"
    printf 'nix_csf_source_count{source="country_port_deny_codes"} %s\n' "${#country_port_deny_codes[@]}"
    printf 'nix_csf_source_count{source="blocklist_urls"} %s\n' "${#blocklist_urls[@]}"
    printf 'nix_csf_source_count{source="cluster_policy_urls"} %s\n' "${cluster_policy_source_count}"
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
allow_icmp="$(jq -r '.allowICMP' "${CONFIG_FILE}")"
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

if [[ "${metrics_enabled}" == "true" && "${metrics_output_file}" != /* ]]; then
  fail "observability.metrics.outputFile must be an absolute path"
fi

log_event "stdout" "info" "run_start" "version=${module_version}" "metrics_enabled=${metrics_enabled}"

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

normalize_cidrs "${TMP_DIR}/allow-v4.raw" "${TMP_DIR}/allow-v4.norm" "${TMP_DIR}/allow-v4.ignore"
normalize_cidrs "${TMP_DIR}/allow-v6.raw" "${TMP_DIR}/allow-v6.ignore" "${TMP_DIR}/allow-v6.norm"
normalize_cidrs "${TMP_DIR}/deny-v4.raw" "${TMP_DIR}/deny-v4.norm" "${TMP_DIR}/deny-v4.ignore"
normalize_cidrs "${TMP_DIR}/deny-v6.raw" "${TMP_DIR}/deny-v6.ignore" "${TMP_DIR}/deny-v6.norm"

sort_unique "${TMP_DIR}/allow-v4.norm" "${TMP_DIR}/allow-v4.txt"
sort_unique "${TMP_DIR}/allow-v6.norm" "${TMP_DIR}/allow-v6.txt"
sort_unique "${TMP_DIR}/deny-v4.norm" "${TMP_DIR}/deny-v4.txt"
sort_unique "${TMP_DIR}/deny-v6.norm" "${TMP_DIR}/deny-v6.txt"

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
    fi

    append_if_exists "${cache_file}" "${TMP_DIR}/feeds.raw"
  done
fi

normalize_cidrs "${TMP_DIR}/feeds.raw" "${TMP_DIR}/feeds-v4.norm" "${TMP_DIR}/feeds-v6.norm"
sort_unique "${TMP_DIR}/feeds-v4.norm" "${TMP_DIR}/feeds-v4.txt"
sort_unique "${TMP_DIR}/feeds-v6.norm" "${TMP_DIR}/feeds-v6.txt"

cluster_policy_enabled="$(jq -r '.clusterPolicy.enable // false' "${CONFIG_FILE}")"
cluster_policy_url="$(jq -r '.clusterPolicy.url // ""' "${CONFIG_FILE}")"
cluster_policy_fail_open="$(jq -r '.clusterPolicy.failOpen // true' "${CONFIG_FILE}")"
cluster_policy_auth_token_file="$(jq -r '.clusterPolicy.authTokenFile // ""' "${CONFIG_FILE}")"
cluster_policy_node_id="$(jq -r '.clusterPolicy.nodeId // ""' "${CONFIG_FILE}")"
cluster_policy_source_count="0"

: > "${TMP_DIR}/cluster-allow-v4.raw"
: > "${TMP_DIR}/cluster-allow-v6.raw"
: > "${TMP_DIR}/cluster-deny-v4.raw"
: > "${TMP_DIR}/cluster-deny-v6.raw"

if [[ "${cluster_policy_enabled}" == "true" ]]; then
  cluster_policy_source_count="1"
  cluster_policy_cache="${CACHE_DIR}/cluster-policy.json"

  if [[ "${MODE}" == "refresh" ]]; then
    cluster_fetch_rc=0
    if ! fetch_cluster_policy_to_cache "${cluster_policy_url}" "${cluster_policy_cache}"; then
      cluster_fetch_rc=$?
      if [[ "${cluster_fetch_rc}" -eq 2 ]]; then
        if [[ -s "${cluster_policy_cache}" ]]; then
          warn "invalid JSON from cluster policy ${cluster_policy_url}; using cached data"
        elif [[ "${cluster_policy_fail_open}" == "true" ]]; then
          warn "invalid JSON from cluster policy ${cluster_policy_url}; continuing due to failOpen"
        else
          fail "invalid JSON from cluster policy ${cluster_policy_url} and no cache exists"
        fi
      elif [[ -s "${cluster_policy_cache}" ]]; then
        warn "failed to refresh cluster policy ${cluster_policy_url}; using cached data"
      elif [[ "${cluster_policy_fail_open}" == "true" ]]; then
        warn "failed to fetch cluster policy ${cluster_policy_url}; continuing due to failOpen"
      else
        fail "failed to fetch cluster policy ${cluster_policy_url} and no cache exists"
      fi
    fi
  fi

  if [[ -s "${cluster_policy_cache}" ]]; then
    if ! jq -e . "${cluster_policy_cache}" >/dev/null 2>&1; then
      if [[ "${cluster_policy_fail_open}" == "true" ]]; then
        warn "cached cluster policy is invalid JSON; skipping merge due to failOpen"
      else
        fail "cached cluster policy is invalid JSON"
      fi
    else
      jq -r '.allowIPv4[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-allow-v4.raw"
      jq -r '.allowIPv6[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-allow-v6.raw"
      jq -r '.denyIPv4[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-deny-v4.raw"
      jq -r '.denyIPv6[]?' "${cluster_policy_cache}" >> "${TMP_DIR}/cluster-deny-v6.raw"
    fi
  fi
fi

normalize_cidrs "${TMP_DIR}/cluster-allow-v4.raw" "${TMP_DIR}/cluster-allow-v4.norm" "${TMP_DIR}/cluster-allow-v4.ignore"
normalize_cidrs "${TMP_DIR}/cluster-allow-v6.raw" "${TMP_DIR}/cluster-allow-v6.ignore" "${TMP_DIR}/cluster-allow-v6.norm"
normalize_cidrs "${TMP_DIR}/cluster-deny-v4.raw" "${TMP_DIR}/cluster-deny-v4.norm" "${TMP_DIR}/cluster-deny-v4.ignore"
normalize_cidrs "${TMP_DIR}/cluster-deny-v6.raw" "${TMP_DIR}/cluster-deny-v6.ignore" "${TMP_DIR}/cluster-deny-v6.norm"

sort_unique "${TMP_DIR}/cluster-allow-v4.norm" "${TMP_DIR}/cluster-allow-v4.txt"
sort_unique "${TMP_DIR}/cluster-allow-v6.norm" "${TMP_DIR}/cluster-allow-v6.txt"
sort_unique "${TMP_DIR}/cluster-deny-v4.norm" "${TMP_DIR}/cluster-deny-v4.txt"
sort_unique "${TMP_DIR}/cluster-deny-v6.norm" "${TMP_DIR}/cluster-deny-v6.txt"

merge_sorted_overlay "${TMP_DIR}/allow-v4.txt" "${TMP_DIR}/cluster-allow-v4.txt"
merge_sorted_overlay "${TMP_DIR}/allow-v6.txt" "${TMP_DIR}/cluster-allow-v6.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v4.txt" "${TMP_DIR}/cluster-deny-v4.txt"
merge_sorted_overlay "${TMP_DIR}/deny-v6.txt" "${TMP_DIR}/cluster-deny-v6.txt"

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
cluster_allow_v4_count="$(count_file_lines "${TMP_DIR}/cluster-allow-v4.txt")"
cluster_allow_v6_count="$(count_file_lines "${TMP_DIR}/cluster-allow-v6.txt")"
cluster_deny_v4_count="$(count_file_lines "${TMP_DIR}/cluster-deny-v4.txt")"
cluster_deny_v6_count="$(count_file_lines "${TMP_DIR}/cluster-deny-v6.txt")"

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
  "cluster_allow_v4=${cluster_allow_v4_count}" \
  "cluster_allow_v6=${cluster_allow_v6_count}" \
  "cluster_deny_v4=${cluster_deny_v4_count}" \
  "cluster_deny_v6=${cluster_deny_v6_count}"

render_port_set() {
  local -n ref="$1"
  local IFS=", "
  printf '%s' "${ref[*]}"
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

  echo "    ip saddr @allow_ipv4 accept"
  echo "    ip6 saddr @allow_ipv6 accept"

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

  if [[ "${#open_tcp_ports[@]}" -gt 0 ]]; then
    printf '    tcp dport { %s } accept\n' "$(render_port_set open_tcp_ports)"
  fi

  if [[ "${#open_udp_ports[@]}" -gt 0 ]]; then
    printf '    udp dport { %s } accept\n' "$(render_port_set open_udp_ports)"
  fi

  if [[ "${allow_icmp}" == "true" ]]; then
    echo "    ip protocol icmp accept"
    echo "    ip6 nexthdr ipv6-icmp accept"
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
