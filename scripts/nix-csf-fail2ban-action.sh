#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csf-fail2ban-action <ban|unban|start|stop|check> [options]

Options:
  --ip ADDRESS              offender IP or CIDR
  --jail NAME               fail2ban jail name (used in reason/logging)
  --endpoint URL            control-plane endpoint (default: http://127.0.0.1:18081)
  --auth-token-file PATH    bearer token file for authenticated control-plane APIs
  --ban-ttl-seconds N       TTL used for ban action (default: 900)
  --reason-prefix TEXT      reason prefix (default: fail2ban)
  --refresh-after-ban       start nix-csf-refresh.service after successful ban mutation
  --refresh-after-unban     start nix-csf-refresh.service after successful unban mutation
  --log-prefix TEXT         log prefix (default: nix-csf-fail2ban-action)
  -h, --help                show this help

Compat positional mode:
  nix-csf-fail2ban-action ban <ip> <jail>
  nix-csf-fail2ban-action unban <ip> <jail>
EOF
}

fail() {
  echo "nix-csf-fail2ban-action: ERROR: $*" >&2
  exit 1
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" == "0" ]]; then
    fail "${name} must be a positive integer"
  fi
}

normalize_cidr() {
  local value="$1"
  if [[ "${value}" == */* ]]; then
    printf '%s\n' "${value}"
    return
  fi
  if [[ "${value}" == *:* ]]; then
    printf '%s/128\n' "${value}"
  else
    printf '%s/32\n' "${value}"
  fi
}

action=""
ip=""
jail=""
endpoint="http://127.0.0.1:18081"
auth_token_file=""
ban_ttl_seconds="900"
reason_prefix="fail2ban"
refresh_after_ban="false"
refresh_after_unban="false"
log_prefix="nix-csf-fail2ban-action"

if [[ "$#" -gt 0 ]]; then
  action="$1"
  shift
fi

case "${action}" in
  ban|unban|start|stop|check) ;;
  ""|-h|--help)
    usage
    exit 0
    ;;
  *)
    fail "unknown action '${action}'"
    ;;
esac

# Fail2ban often passes positional IP + jail. Accept both positional and flag-based forms.
if [[ "$#" -gt 0 && "${1:-}" != -* && -z "${ip}" ]]; then
  ip="$1"
  shift
fi
if [[ "$#" -gt 0 && "${1:-}" != -* && -z "${jail}" ]]; then
  jail="$1"
  shift
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --ip)
      [[ "$#" -ge 2 ]] || fail "--ip requires a value"
      ip="$2"
      shift 2
      ;;
    --jail)
      [[ "$#" -ge 2 ]] || fail "--jail requires a value"
      jail="$2"
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
    --ban-ttl-seconds)
      [[ "$#" -ge 2 ]] || fail "--ban-ttl-seconds requires a value"
      ban_ttl_seconds="$2"
      shift 2
      ;;
    --reason-prefix)
      [[ "$#" -ge 2 ]] || fail "--reason-prefix requires a value"
      reason_prefix="$2"
      shift 2
      ;;
    --refresh-after-ban)
      refresh_after_ban="true"
      shift
      ;;
    --refresh-after-unban)
      refresh_after_unban="true"
      shift
      ;;
    --log-prefix)
      [[ "$#" -ge 2 ]] || fail "--log-prefix requires a value"
      log_prefix="$2"
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

case "${action}" in
  start|stop|check)
    echo "${log_prefix}: action=${action} status=noop"
    exit 0
    ;;
  ban|unban)
    [[ -n "${ip}" ]] || fail "--ip (or positional ip) is required for action ${action}"
    ;;
esac

validate_positive_int "${ban_ttl_seconds}" "ban-ttl-seconds"

if [[ -n "${auth_token_file}" ]]; then
  [[ "${auth_token_file}" == /* ]] || fail "--auth-token-file must be an absolute path"
  [[ -f "${auth_token_file}" ]] || fail "token file not found: ${auth_token_file}"
fi

cidr="$(normalize_cidr "${ip}")"
jail_component="${jail:-unknown}"
reason="${reason_prefix}:${jail_component}"

cmd=(nix-csfctl --endpoint "${endpoint}" --output json)
if [[ -n "${auth_token_file}" ]]; then
  cmd+=(--auth-token-file "${auth_token_file}")
fi

if [[ "${action}" == "ban" ]]; then
  cmd+=(ban-temp "${cidr}" --ttl "${ban_ttl_seconds}" --reason "${reason}")
else
  cmd+=(unban "${cidr}")
fi

response="$("${cmd[@]}")" || fail "control-plane request failed for action ${action} cidr=${cidr}"
changed="$(printf '%s\n' "${response}" | jq -r '.changed // false' 2>/dev/null || echo "false")"
escalated="$(printf '%s\n' "${response}" | jq -r '.escalation.escalated // false' 2>/dev/null || echo "false")"

echo "${log_prefix}: action=${action} jail=${jail_component} cidr=${cidr} changed=${changed} escalated=${escalated}"

if [[ "${action}" == "ban" && "${refresh_after_ban}" == "true" && "${changed}" == "true" ]]; then
  if systemctl start nix-csf-refresh.service; then
    echo "${log_prefix}: refresh_trigger=ban status=success"
  else
    echo "${log_prefix}: WARNING refresh_trigger=ban status=failed" >&2
  fi
fi

if [[ "${action}" == "unban" && "${refresh_after_unban}" == "true" && "${changed}" == "true" ]]; then
  if systemctl start nix-csf-refresh.service; then
    echo "${log_prefix}: refresh_trigger=unban status=success"
  else
    echo "${log_prefix}: WARNING refresh_trigger=unban status=failed" >&2
  fi
fi
