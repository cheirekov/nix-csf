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

say() {
  echo "nix-csf: $*"
}

warn() {
  echo "nix-csf: WARNING: $*" >&2
}

fail() {
  echo "nix-csf: ERROR: $*" >&2
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

default_policy="$(jq -r '.defaultPolicy' "${CONFIG_FILE}")"
forward_policy="$(jq -r '.forwardPolicy' "${CONFIG_FILE}")"
allow_icmp="$(jq -r '.allowICMP' "${CONFIG_FILE}")"
log_drops="$(jq -r '.logDrops' "${CONFIG_FILE}")"
syn_rate_limit="$(jq -r '.synRateLimit // ""' "${CONFIG_FILE}")"

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

mapfile -t trusted_interfaces < <(jq -r '.trustedInterfaces[]?' "${CONFIG_FILE}")
mapfile -t open_tcp_ports < <(jq -r '.openTCPPorts[]?' "${CONFIG_FILE}")
mapfile -t open_udp_ports < <(jq -r '.openUDPPorts[]?' "${CONFIG_FILE}")

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

say "rules applied (${MODE})"
