#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csfctl [global options] <command> [args]

Global options:
  --endpoint URL            Control-plane base URL (default: http://127.0.0.1:18081)
  --auth-token-file PATH    Bearer token file for authenticated endpoints
  --output MODE             json|pretty (default: json)
  -h, --help                Show this help

Commands:
  health
      GET /healthz

  policy add <allow|deny|ignore> <CIDR>
      POST /v1/policy/<list>

  policy remove <allow|deny|ignore> <CIDR>
      DELETE /v1/policy/<list>

  ban-temp <CIDR> [--ttl SECONDS] [--reason TEXT]
      POST /v1/offenders/ban-temp

  unban <CIDR>
      POST /v1/offenders/unban

  promotions [--limit N]
      GET /v1/escalation/promotions
EOF
}

fail() {
  echo "nix-csfctl: ERROR: $*" >&2
  exit 1
}

validate_list_name() {
  case "$1" in
    allow|deny|ignore) ;;
    *) fail "invalid list '$1' (expected: allow|deny|ignore)" ;;
  esac
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" == "0" ]]; then
    fail "${name} must be a positive integer"
  fi
}

endpoint="${NIX_CSFCTL_ENDPOINT:-http://127.0.0.1:18081}"
auth_token_file="${NIX_CSFCTL_AUTH_TOKEN_FILE:-}"
output_mode="json"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
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
    --output)
      [[ "$#" -ge 2 ]] || fail "--output requires a value"
      output_mode="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

if [[ "${output_mode}" != "json" && "${output_mode}" != "pretty" ]]; then
  fail "--output must be 'json' or 'pretty'"
fi

[[ "$#" -gt 0 ]] || {
  usage
  exit 1
}

curl_auth_args=()
if [[ -n "${auth_token_file}" ]]; then
  [[ "${auth_token_file}" == /* ]] || fail "--auth-token-file must be an absolute path"
  [[ -f "${auth_token_file}" ]] || fail "token file not found: ${auth_token_file}"
  token="$(<"${auth_token_file}")"
  token="${token//$'\r'/}"
  token="${token//$'\n'/}"
  [[ -n "${token}" ]] || fail "token file is empty: ${auth_token_file}"
  if [[ "${token}" =~ [[:space:]] ]]; then
    fail "token file contains whitespace: ${auth_token_file}"
  fi
  curl_auth_args=(-H "Authorization: Bearer ${token}")
fi

render_output() {
  local payload="$1"
  if [[ "${output_mode}" == "pretty" ]]; then
    printf '%s\n' "${payload}" | jq .
  else
    printf '%s\n' "${payload}"
  fi
}

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local extra_header_name="${4:-}"
  local extra_header_value="${5:-}"
  local payload=""

  local response_file
  response_file="$(mktemp)"
  local code
  local url="${endpoint%/}${path}"

  local -a curl_args=(
    --silent
    --show-error
    --location
    --request "${method}"
    --output "${response_file}"
    --write-out "%{http_code}"
  )

  if [[ -n "${extra_header_name}" ]]; then
    curl_args+=( -H "${extra_header_name}: ${extra_header_value}" )
  fi

  if [[ -n "${body}" ]]; then
    curl_args+=( -H "Content-Type: application/json" --data "${body}" )
  fi

  if [[ "${#curl_auth_args[@]}" -gt 0 ]]; then
    curl_args+=( "${curl_auth_args[@]}" )
  fi

  if ! code="$(curl "${curl_args[@]}" "${url}")"; then
    rm -f "${response_file}"
    fail "request failed (${method} ${path})"
  fi

  payload="$(<"${response_file}")"
  rm -f "${response_file}"

  if [[ "${code}" =~ ^2[0-9][0-9]$ ]]; then
    render_output "${payload}"
    return 0
  fi

  echo "nix-csfctl: HTTP ${code} from ${method} ${path}" >&2
  if [[ -n "${payload}" ]]; then
    if [[ "${output_mode}" == "pretty" ]]; then
      printf '%s\n' "${payload}" | jq . >&2 || printf '%s\n' "${payload}" >&2
    else
      printf '%s\n' "${payload}" >&2
    fi
  fi
  exit 1
}

command="$1"
shift

case "${command}" in
  health)
    request "GET" "/healthz"
    ;;

  policy)
    [[ "$#" -eq 3 ]] || fail "usage: nix-csfctl policy <add|remove> <allow|deny|ignore> <CIDR>"
    action="$1"
    list_name="$2"
    cidr="$3"
    validate_list_name "${list_name}"
    payload="$(jq -cn --arg cidr "${cidr}" '{cidr: $cidr}')"
    case "${action}" in
      add)
        request "POST" "/v1/policy/${list_name}" "${payload}"
        ;;
      remove)
        request "DELETE" "/v1/policy/${list_name}" "${payload}"
        ;;
      *)
        fail "invalid policy action '${action}' (expected: add|remove)"
        ;;
    esac
    ;;

  ban-temp)
    [[ "$#" -ge 1 ]] || fail "usage: nix-csfctl ban-temp <CIDR> [--ttl SECONDS] [--reason TEXT]"
    cidr="$1"
    shift
    ttl=""
    reason=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --ttl)
          [[ "$#" -ge 2 ]] || fail "--ttl requires a value"
          ttl="$2"
          shift 2
          ;;
        --reason)
          [[ "$#" -ge 2 ]] || fail "--reason requires a value"
          reason="$2"
          shift 2
          ;;
        *)
          fail "unknown ban-temp option: $1"
          ;;
      esac
    done

    if [[ -n "${ttl}" ]]; then
      validate_positive_int "${ttl}" "ttl"
    fi

    if [[ -n "${ttl}" && -n "${reason}" ]]; then
      payload="$(jq -cn --arg cidr "${cidr}" --argjson ttl "${ttl}" --arg reason "${reason}" '{cidr: $cidr, ttlSeconds: $ttl, reason: $reason}')"
    elif [[ -n "${ttl}" ]]; then
      payload="$(jq -cn --arg cidr "${cidr}" --argjson ttl "${ttl}" '{cidr: $cidr, ttlSeconds: $ttl}')"
    elif [[ -n "${reason}" ]]; then
      payload="$(jq -cn --arg cidr "${cidr}" --arg reason "${reason}" '{cidr: $cidr, reason: $reason}')"
    else
      payload="$(jq -cn --arg cidr "${cidr}" '{cidr: $cidr}')"
    fi

    request "POST" "/v1/offenders/ban-temp" "${payload}"
    ;;

  unban)
    [[ "$#" -ge 1 ]] || fail "usage: nix-csfctl unban <CIDR>"
    cidr="$1"
    payload="$(jq -cn --arg cidr "${cidr}" '{cidr: $cidr}')"
    request "POST" "/v1/offenders/unban" "${payload}"
    ;;

  promotions)
    limit="200"
    if [[ "$#" -gt 0 ]]; then
      if [[ "$1" == "--limit" ]]; then
        [[ "$#" -ge 2 ]] || fail "--limit requires a value"
        limit="$2"
        shift 2
      else
        fail "unknown promotions option: $1"
      fi
    fi
    [[ "$#" -eq 0 ]] || fail "unexpected extra arguments for promotions"
    validate_positive_int "${limit}" "limit"
    request "GET" "/v1/escalation/promotions" "" "X-Nix-Csf-Limit" "${limit}"
    ;;

  *)
    fail "unknown command: ${command}"
    ;;
esac
