#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csfctl [global options] <command> [args]

Global options:
  --endpoint URL            Control-plane base URL (default: http://127.0.0.1:18081)
  --auth-token-file PATH    Bearer token file for authenticated endpoints
  --node-id ID              Send X-Nix-Csf-Node header on all requests
  --output MODE             json|pretty (default: json)
  -h, --help                Show this help

Commands:
  health
      GET /healthz

  policy add <allow|deny|ignore> <CIDR> [--scope cluster|local] [--node-id ID] [--source NAME]
      POST /v1/policy/<list>

  policy remove <allow|deny|ignore> <CIDR> [--scope cluster|local|any]
      DELETE /v1/policy/<list>

  ban-temp <CIDR> [--ttl SECONDS] [--reason TEXT] [--scope cluster|local] [--node-id ID] [--source NAME]
      POST /v1/offenders/ban-temp

  unban <CIDR> [--scope cluster|local|any] [--node-id ID]
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

validate_scope_value() {
  local value="$1"
  local name="$2"
  case "${value}" in
    cluster|local) ;;
    *) fail "${name} must be one of: cluster|local" ;;
  esac
}

validate_scope_filter() {
  local value="$1"
  local name="$2"
  case "${value}" in
    cluster|local|any) ;;
    *) fail "${name} must be one of: cluster|local|any" ;;
  esac
}

validate_node_id() {
  local value="$1"
  local name="$2"
  [[ -n "${value}" ]] || fail "${name} must not be empty"
  if [[ "${value}" =~ [[:space:]] ]]; then
    fail "${name} must not contain whitespace"
  fi
}

validate_source_name() {
  local value="$1"
  local name="$2"
  [[ -n "${value}" ]] || fail "${name} must not be empty"
  if [[ "${value}" =~ [[:space:]] ]]; then
    fail "${name} must not contain whitespace"
  fi
}

endpoint="${NIX_CSFCTL_ENDPOINT:-http://127.0.0.1:18081}"
auth_token_file="${NIX_CSFCTL_AUTH_TOKEN_FILE:-}"
global_node_id="${NIX_CSFCTL_NODE_ID:-}"
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
    --node-id)
      [[ "$#" -ge 2 ]] || fail "--node-id requires a value"
      global_node_id="$2"
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

if [[ -n "${global_node_id}" ]]; then
  validate_node_id "${global_node_id}" "--node-id"
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

  if [[ -n "${global_node_id}" ]]; then
    curl_args+=( -H "X-Nix-Csf-Node: ${global_node_id}" )
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
    [[ "$#" -ge 3 ]] || fail "usage: nix-csfctl policy <add|remove> <allow|deny|ignore> <CIDR> [options]"
    action="$1"
    list_name="$2"
    cidr="$3"
    shift 3
    scope=""
    node_id=""
    source=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --scope)
          [[ "$#" -ge 2 ]] || fail "--scope requires a value"
          scope="$2"
          shift 2
          ;;
        --node-id)
          [[ "$#" -ge 2 ]] || fail "--node-id requires a value"
          node_id="$2"
          shift 2
          ;;
        --source)
          [[ "$#" -ge 2 ]] || fail "--source requires a value"
          source="$2"
          shift 2
          ;;
        *)
          fail "unknown policy option: $1"
          ;;
      esac
    done
    validate_list_name "${list_name}"
    if [[ -n "${node_id}" ]]; then
      validate_node_id "${node_id}" "policy --node-id"
    fi
    if [[ -n "${source}" ]]; then
      validate_source_name "${source}" "policy --source"
    fi
    case "${action}" in
      add)
        if [[ -n "${scope}" ]]; then
          validate_scope_value "${scope}" "policy --scope"
        fi
        payload="$(jq -cn \
          --arg cidr "${cidr}" \
          --arg scope "${scope}" \
          --arg nodeId "${node_id}" \
          --arg source "${source}" \
          '{cidr: $cidr}
          + (if $scope != "" then {scope: $scope} else {} end)
          + (if $nodeId != "" then {nodeId: $nodeId} else {} end)
          + (if $source != "" then {source: $source} else {} end)')"
        request "POST" "/v1/policy/${list_name}" "${payload}"
        ;;
      remove)
        if [[ -n "${scope}" ]]; then
          validate_scope_filter "${scope}" "policy --scope"
        fi
        payload="$(jq -cn \
          --arg cidr "${cidr}" \
          --arg scope "${scope}" \
          '{cidr: $cidr}
          + (if $scope != "" then {scope: $scope} else {} end)')"
        request "DELETE" "/v1/policy/${list_name}" "${payload}"
        ;;
      *)
        fail "invalid policy action '${action}' (expected: add|remove)"
        ;;
    esac
    ;;

  ban-temp)
    [[ "$#" -ge 1 ]] || fail "usage: nix-csfctl ban-temp <CIDR> [--ttl SECONDS] [--reason TEXT] [--scope cluster|local] [--node-id ID] [--source NAME]"
    cidr="$1"
    shift
    ttl=""
    reason=""
    scope=""
    node_id=""
    source=""
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
        --scope)
          [[ "$#" -ge 2 ]] || fail "--scope requires a value"
          scope="$2"
          shift 2
          ;;
        --node-id)
          [[ "$#" -ge 2 ]] || fail "--node-id requires a value"
          node_id="$2"
          shift 2
          ;;
        --source)
          [[ "$#" -ge 2 ]] || fail "--source requires a value"
          source="$2"
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
    if [[ -n "${scope}" ]]; then
      validate_scope_value "${scope}" "ban-temp --scope"
    fi
    if [[ -n "${node_id}" ]]; then
      validate_node_id "${node_id}" "ban-temp --node-id"
    fi
    if [[ -n "${source}" ]]; then
      validate_source_name "${source}" "ban-temp --source"
    fi

    ttl_or_null="null"
    if [[ -n "${ttl}" ]]; then
      ttl_or_null="${ttl}"
    fi
    reason_or_null="null"
    if [[ -n "${reason}" ]]; then
      reason_or_null="$(jq -Rn --arg value "${reason}" '$value')"
    fi
    payload="$(jq -cn \
      --arg cidr "${cidr}" \
      --arg scope "${scope}" \
      --arg nodeId "${node_id}" \
      --arg source "${source}" \
      --argjson ttlSeconds "${ttl_or_null}" \
      --argjson reason "${reason_or_null}" \
      '{cidr: $cidr}
      + (if $ttlSeconds != null then {ttlSeconds: $ttlSeconds} else {} end)
      + (if $reason != null then {reason: $reason} else {} end)
      + (if $scope != "" then {scope: $scope} else {} end)
      + (if $nodeId != "" then {nodeId: $nodeId} else {} end)
      + (if $source != "" then {source: $source} else {} end)')"

    request "POST" "/v1/offenders/ban-temp" "${payload}"
    ;;

  unban)
    [[ "$#" -ge 1 ]] || fail "usage: nix-csfctl unban <CIDR> [--scope cluster|local|any] [--node-id ID]"
    cidr="$1"
    shift
    scope=""
    node_id=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --scope)
          [[ "$#" -ge 2 ]] || fail "--scope requires a value"
          scope="$2"
          shift 2
          ;;
        --node-id)
          [[ "$#" -ge 2 ]] || fail "--node-id requires a value"
          node_id="$2"
          shift 2
          ;;
        *)
          fail "unknown unban option: $1"
          ;;
      esac
    done
    if [[ -n "${scope}" ]]; then
      validate_scope_filter "${scope}" "unban --scope"
    fi
    if [[ -n "${node_id}" ]]; then
      validate_node_id "${node_id}" "unban --node-id"
    fi
    payload="$(jq -cn \
      --arg cidr "${cidr}" \
      --arg scope "${scope}" \
      --arg nodeId "${node_id}" \
      '{cidr: $cidr}
      + (if $scope != "" then {scope: $scope} else {} end)
      + (if $nodeId != "" then {nodeId: $nodeId} else {} end)')"
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
