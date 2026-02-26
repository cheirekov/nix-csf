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

  policy compile --input PATH [options]
      Compile policy-as-code JSON into canonical snapshots.
      Options:
        --cluster-output PATH      Write compiled cluster snapshot JSON
        --dynamic-output PATH      Write compiled dynamic snapshot JSON
        --policy-revision TEXT     Cluster snapshot revision (default: compiled-policy-r1)
        --dynamic-revision TEXT    Dynamic snapshot revision (default: compiled-dyn-r1)
        --cluster-ttl SECONDS      Cluster snapshot ttlSeconds (default: 300)
        --dynamic-ttl SECONDS      Dynamic snapshot ttlSeconds (default: 120)
        --default-ban-ttl SECONDS  ttlSeconds for string ban entries (default: 900)
        --last-mutation-id N       lastMutationId value (default: 0)

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

validate_nonneg_int() {
  local value="$1"
  local name="$2"
  if ! [[ "${value}" =~ ^[0-9]+$ ]]; then
    fail "${name} must be a non-negative integer"
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

write_json_file_atomic() {
  local output_path="$1"
  local jq_selector="$2"
  local payload="$3"

  local output_dir
  output_dir="$(dirname "${output_path}")"
  mkdir -p "${output_dir}"

  local tmp_file
  tmp_file="$(mktemp "${output_dir}/.nix-csfctl.XXXXXX")"
  printf '%s\n' "${payload}" | jq -S "${jq_selector}" > "${tmp_file}"
  mv "${tmp_file}" "${output_path}"
}

compile_policy_payload() {
  local input_file="$1"
  local policy_revision="$2"
  local dynamic_revision="$3"
  local cluster_ttl="$4"
  local dynamic_ttl="$5"
  local default_ban_ttl="$6"
  local last_mutation_id="$7"

  jq -ce \
    --arg policyRevision "${policy_revision}" \
    --arg dynamicRevision "${dynamic_revision}" \
    --argjson clusterTtl "${cluster_ttl}" \
    --argjson dynamicTtl "${dynamic_ttl}" \
    --argjson defaultBanTtl "${default_ban_ttl}" \
    --argjson lastMutationId "${last_mutation_id}" '
      def is_nonneg_int:
        (type == "number")
        and (floor == .)
        and (. >= 0);

      def normalize_trimmed_string($path):
        if type != "string" then
          error($path + " must be a string")
        else
          gsub("^[[:space:]]+|[[:space:]]+$"; "")
        end;

      def is_v4_cidr:
        test("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$");

      def is_v6_cidr:
        (test("^[0-9A-Fa-f:]+(/[0-9]{1,3})?$") and contains(":"));

      def normalize_cidr($path):
        (normalize_trimmed_string($path)) as $cidr
        | if $cidr == "" then
            error($path + " must not be empty")
          elif ($cidr | is_v4_cidr) then
            $cidr
          elif ($cidr | is_v6_cidr) then
            ($cidr | ascii_downcase)
          else
            error($path + " invalid CIDR: " + $cidr)
          end;

      def as_string_array($value; $path):
        if $value == null then
          []
        elif ($value | type) != "array" then
          error($path + " must be an array")
        else
          [
            range(0; ($value | length)) as $index
            | ($value[$index] | normalize_cidr($path + "[" + ($index | tostring) + "]"))
          ]
        end;

      def normalize_dynamic_entry($entry; $path):
        if ($entry | type) == "string" then
          {
            cidr: ($entry | normalize_cidr($path)),
            ttlSeconds: $defaultBanTtl
          }
        elif ($entry | type) == "object" then
          ($entry.cidr | normalize_cidr($path + ".cidr")) as $cidr
          | if ($entry.ttlSeconds? != null) and (($entry.ttlSeconds | is_nonneg_int) | not) then
              error($path + ".ttlSeconds must be a non-negative integer")
            elif ($entry.expiresAt? != null) and (($entry.expiresAt | is_nonneg_int) | not) then
              error($path + ".expiresAt must be a non-negative integer")
            elif ($entry.reason? != null) and (($entry.reason | type) != "string") then
              error($path + ".reason must be a string")
            else
              {
                cidr: $cidr
              }
              + (if $entry.ttlSeconds? != null then { ttlSeconds: $entry.ttlSeconds } else {} end)
              + (if $entry.expiresAt? != null then { expiresAt: $entry.expiresAt } else {} end)
              + (if $entry.reason? != null then { reason: $entry.reason } else {} end)
            end
        else
          error($path + " entries must be strings or objects")
        end;

      def dedupe_dynamic:
        sort_by(.cidr, (.expiresAt // 0), (.ttlSeconds // 0), (.reason // ""))
        | group_by(.cidr)
        | map(last)
        | sort_by(.cidr);

      if type != "object" then
        error("input document must be a JSON object")
      else
        .
      end
      | . as $root
      | ($root.clusterPolicy // {}) as $cluster
      | ($root.dynamicOffenders // {}) as $dynamic
      | if ($cluster | type) != "object" then
          error("clusterPolicy must be an object")
        elif ($dynamic | type) != "object" then
          error("dynamicOffenders must be an object")
        else
          .
        end
      | (
          as_string_array(($cluster.allow // $root.allow // []); "clusterPolicy.allow")
          + as_string_array(($cluster.allowIPv4 // []); "clusterPolicy.allowIPv4")
          + as_string_array(($cluster.allowIPv6 // []); "clusterPolicy.allowIPv6")
        ) as $allow_entries
      | (
          as_string_array(($cluster.deny // $root.deny // []); "clusterPolicy.deny")
          + as_string_array(($cluster.denyIPv4 // []); "clusterPolicy.denyIPv4")
          + as_string_array(($cluster.denyIPv6 // []); "clusterPolicy.denyIPv6")
        ) as $deny_entries
      | (
          as_string_array(($cluster.ignore // $root.ignore // []); "clusterPolicy.ignore")
          + as_string_array(($cluster.ignoreIPv4 // []); "clusterPolicy.ignoreIPv4")
          + as_string_array(($cluster.ignoreIPv6 // []); "clusterPolicy.ignoreIPv6")
        ) as $ignore_entries
      | (
          ($dynamic.ban // $root.ban // []) as $ban_raw
          | if ($ban_raw | type) != "array" then
              error("dynamicOffenders.ban must be an array")
            else
              [
                range(0; ($ban_raw | length)) as $index
                | normalize_dynamic_entry(
                    $ban_raw[$index];
                    "dynamicOffenders.ban[" + ($index | tostring) + "]"
                  )
              ]
            end
        ) as $ban_entries
      | {
          clusterPolicy: {
            schemaVersion: 2,
            revision: $policyRevision,
            ttlSeconds: $clusterTtl,
            lastMutationId: $lastMutationId,
            allowIPv4: ($allow_entries | map(select(is_v4_cidr)) | unique | sort),
            allowIPv6: ($allow_entries | map(select(is_v6_cidr)) | unique | sort),
            denyIPv4: ($deny_entries | map(select(is_v4_cidr)) | unique | sort),
            denyIPv6: ($deny_entries | map(select(is_v6_cidr)) | unique | sort),
            ignoreIPv4: ($ignore_entries | map(select(is_v4_cidr)) | unique | sort),
            ignoreIPv6: ($ignore_entries | map(select(is_v6_cidr)) | unique | sort)
          },
          dynamicOffenders: {
            schemaVersion: 1,
            revision: $dynamicRevision,
            ttlSeconds: $dynamicTtl,
            lastMutationId: $lastMutationId,
            banIPv4: ($ban_entries | map(select(.cidr | is_v4_cidr)) | dedupe_dynamic),
            banIPv6: ($ban_entries | map(select(.cidr | is_v6_cidr)) | dedupe_dynamic)
          }
        }
  ' "${input_file}"
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
    [[ "$#" -ge 1 ]] || fail "usage: nix-csfctl policy <add|remove|compile> ..."
    action="$1"
    shift
    case "${action}" in
      add|remove)
        [[ "$#" -ge 2 ]] || fail "usage: nix-csfctl policy <add|remove> <allow|deny|ignore> <CIDR> [options]"
        list_name="$1"
        cidr="$2"
        shift 2
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
        if [[ "${action}" == "add" ]]; then
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
        else
          if [[ -n "${scope}" ]]; then
            validate_scope_filter "${scope}" "policy --scope"
          fi
          payload="$(jq -cn \
            --arg cidr "${cidr}" \
            --arg scope "${scope}" \
            '{cidr: $cidr}
            + (if $scope != "" then {scope: $scope} else {} end)')"
          request "DELETE" "/v1/policy/${list_name}" "${payload}"
        fi
        ;;
      compile)
        input_file=""
        cluster_output=""
        dynamic_output=""
        policy_revision="compiled-policy-r1"
        dynamic_revision="compiled-dyn-r1"
        cluster_ttl="300"
        dynamic_ttl="120"
        default_ban_ttl="900"
        last_mutation_id="0"

        while [[ "$#" -gt 0 ]]; do
          case "$1" in
            --input)
              [[ "$#" -ge 2 ]] || fail "--input requires a value"
              input_file="$2"
              shift 2
              ;;
            --cluster-output)
              [[ "$#" -ge 2 ]] || fail "--cluster-output requires a value"
              cluster_output="$2"
              shift 2
              ;;
            --dynamic-output)
              [[ "$#" -ge 2 ]] || fail "--dynamic-output requires a value"
              dynamic_output="$2"
              shift 2
              ;;
            --policy-revision)
              [[ "$#" -ge 2 ]] || fail "--policy-revision requires a value"
              policy_revision="$2"
              shift 2
              ;;
            --dynamic-revision)
              [[ "$#" -ge 2 ]] || fail "--dynamic-revision requires a value"
              dynamic_revision="$2"
              shift 2
              ;;
            --cluster-ttl)
              [[ "$#" -ge 2 ]] || fail "--cluster-ttl requires a value"
              cluster_ttl="$2"
              shift 2
              ;;
            --dynamic-ttl)
              [[ "$#" -ge 2 ]] || fail "--dynamic-ttl requires a value"
              dynamic_ttl="$2"
              shift 2
              ;;
            --default-ban-ttl)
              [[ "$#" -ge 2 ]] || fail "--default-ban-ttl requires a value"
              default_ban_ttl="$2"
              shift 2
              ;;
            --last-mutation-id)
              [[ "$#" -ge 2 ]] || fail "--last-mutation-id requires a value"
              last_mutation_id="$2"
              shift 2
              ;;
            *)
              fail "unknown policy compile option: $1"
              ;;
          esac
        done

        [[ -n "${input_file}" ]] || fail "policy compile requires --input PATH"
        [[ -f "${input_file}" ]] || fail "policy compile input file not found: ${input_file}"
        [[ -n "${policy_revision}" ]] || fail "--policy-revision must not be empty"
        [[ -n "${dynamic_revision}" ]] || fail "--dynamic-revision must not be empty"
        validate_nonneg_int "${cluster_ttl}" "--cluster-ttl"
        validate_nonneg_int "${dynamic_ttl}" "--dynamic-ttl"
        validate_positive_int "${default_ban_ttl}" "--default-ban-ttl"
        validate_nonneg_int "${last_mutation_id}" "--last-mutation-id"

        if ! compiled_payload="$(
          compile_policy_payload \
            "${input_file}" \
            "${policy_revision}" \
            "${dynamic_revision}" \
            "${cluster_ttl}" \
            "${dynamic_ttl}" \
            "${default_ban_ttl}" \
            "${last_mutation_id}"
        )"; then
          fail "policy compile failed schema or CIDR validation for ${input_file}"
        fi

        if [[ -n "${cluster_output}" ]]; then
          write_json_file_atomic "${cluster_output}" '.clusterPolicy' "${compiled_payload}"
        fi
        if [[ -n "${dynamic_output}" ]]; then
          write_json_file_atomic "${dynamic_output}" '.dynamicOffenders' "${compiled_payload}"
        fi

        render_output "${compiled_payload}"
        ;;
      *)
        fail "invalid policy action '${action}' (expected: add|remove|compile)"
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
