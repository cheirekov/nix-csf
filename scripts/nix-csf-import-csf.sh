#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nix-csf-import-csf \
    [--allow-file <path>] \
    [--deny-file <path>] \
    [--ignore-file <path>] \
    --output-dir <path> \
    [--prefix <name>] \
    [--report-file <path>] \
    [--strict]

Imports legacy CSF list files into nix-csf local list files:
  - <prefix>-allow.local
  - <prefix>-deny.local
  - <prefix>-ignore.local

Also writes an unsupported-entry report for lines that cannot be migrated
as plain CIDR/IP entries (for example CSF advanced port rules).
EOF
}

allow_file=""
deny_file=""
ignore_file=""
output_dir=""
prefix="csf-import"
report_file=""
strict="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-file)
      allow_file="${2:-}"
      shift 2
      ;;
    --deny-file)
      deny_file="${2:-}"
      shift 2
      ;;
    --ignore-file)
      ignore_file="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --prefix)
      prefix="${2:-}"
      shift 2
      ;;
    --report-file)
      report_file="${2:-}"
      shift 2
      ;;
    --strict)
      strict="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "nix-csf-import-csf: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${output_dir}" ]]; then
  echo "nix-csf-import-csf: --output-dir is required" >&2
  exit 1
fi

if [[ -z "${allow_file}" && -z "${deny_file}" && -z "${ignore_file}" ]]; then
  echo "nix-csf-import-csf: at least one of --allow-file/--deny-file/--ignore-file is required" >&2
  exit 1
fi

if [[ ! "${prefix}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "nix-csf-import-csf: --prefix contains unsupported characters: ${prefix}" >&2
  exit 1
fi

mkdir -p "${output_dir}"

if [[ -z "${report_file}" ]]; then
  report_file="${output_dir}/${prefix}-unsupported.log"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

allow_out="${output_dir}/${prefix}-allow.local"
deny_out="${output_dir}/${prefix}-deny.local"
ignore_out="${output_dir}/${prefix}-ignore.local"
summary_out="${output_dir}/${prefix}-summary.log"
snippet_out="${output_dir}/${prefix}-nixos-localFiles-snippet.nix"

printf 'role\tsource\tline\treason\tentry\n' > "${report_file}"

write_empty_sorted_file() {
  local path="$1"
  : > "${path}"
}

parse_csf_file() {
  local role="$1"
  local input_file="$2"
  local output_file="$3"
  local report_path="$4"
  local stats_file="$5"

  if [[ -z "${input_file}" ]]; then
    write_empty_sorted_file "${output_file}"
    printf '0 0\n' > "${stats_file}"
    return 0
  fi

  if [[ ! -r "${input_file}" ]]; then
    echo "nix-csf-import-csf: ${role} file is missing or unreadable: ${input_file}" >&2
    exit 1
  fi

  awk \
    -v role="${role}" \
    -v source="${input_file}" \
    -v report="${report_path}" \
    -v stats="${stats_file}" '
    function trim(str) {
      sub(/^[ \t]+/, "", str);
      sub(/[ \t]+$/, "", str);
      return str;
    }
    function emit_unsupported(reason, raw_line) {
      unsupported++;
      printf "%s\t%s\t%d\t%s\t%s\n", role, source, NR, reason, raw_line >> report;
    }
    {
      raw = $0;
      gsub(/\r/, "", raw);
      work = raw;
      sub(/#.*/, "", work);
      sub(/;.*/, "", work);
      work = trim(work);
      if (work == "") {
        next;
      }

      token = work;
      if (work ~ /^add[ \t]+/) {
        parts_count = split(work, parts, /[ \t]+/);
        if (parts_count >= 3) {
          token = parts[3];
        } else {
          emit_unsupported("unrecognized_add_rule", raw);
          next;
        }
      } else if (work ~ /^ipset[ \t]+add[ \t]+/) {
        parts_count = split(work, parts, /[ \t]+/);
        if (parts_count >= 4) {
          token = parts[4];
        } else {
          emit_unsupported("unrecognized_ipset_rule", raw);
          next;
        }
      } else if (work ~ /^[Ii]nclude[ \t]+/) {
        emit_unsupported("include_directive", raw);
        next;
      } else if (work ~ /^(tcp|udp)\|/) {
        emit_unsupported("advanced_port_rule", raw);
        next;
      } else if (work ~ /\|/) {
        emit_unsupported("advanced_rule", raw);
        next;
      }

      token = trim(token);
      is_ipv4 = (token ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/);
      is_ipv6 = (token ~ /^[0-9A-Fa-f:]+(\/[0-9]{1,3})?$/ && index(token, ":") > 0);
      if (is_ipv4 || is_ipv6) {
        parsed++;
        print token;
      } else {
        emit_unsupported("unrecognized_token", raw);
      }
    }
    END {
      printf "%d %d\n", parsed + 0, unsupported + 0 > stats;
    }
  ' "${input_file}" | sort -u > "${output_file}"
}

allow_stats="${tmp_dir}/allow.stats"
deny_stats="${tmp_dir}/deny.stats"
ignore_stats="${tmp_dir}/ignore.stats"

parse_csf_file "allow" "${allow_file}" "${allow_out}" "${report_file}" "${allow_stats}"
parse_csf_file "deny" "${deny_file}" "${deny_out}" "${report_file}" "${deny_stats}"
parse_csf_file "ignore" "${ignore_file}" "${ignore_out}" "${report_file}" "${ignore_stats}"

read -r allow_parsed allow_unsupported < "${allow_stats}"
read -r deny_parsed deny_unsupported < "${deny_stats}"
read -r ignore_parsed ignore_unsupported < "${ignore_stats}"

total_unsupported=$((allow_unsupported + deny_unsupported + ignore_unsupported))

cat > "${summary_out}" <<EOF
nix-csf-import-csf summary

allow:
  source: ${allow_file:-<none>}
  parsed_cidr_or_ip: ${allow_parsed}
  unsupported_entries: ${allow_unsupported}
  output: ${allow_out}

deny:
  source: ${deny_file:-<none>}
  parsed_cidr_or_ip: ${deny_parsed}
  unsupported_entries: ${deny_unsupported}
  output: ${deny_out}

ignore:
  source: ${ignore_file:-<none>}
  parsed_cidr_or_ip: ${ignore_parsed}
  unsupported_entries: ${ignore_unsupported}
  output: ${ignore_out}

unsupported_report: ${report_file}
strict_mode: ${strict}
EOF

cat > "${snippet_out}" <<EOF
services.nixCsf.localFiles = {
  enable = true;
  failOnMissing = true;
  allow = [ "${allow_out}" ];
  deny = [ "${deny_out}" ];
  ignore = [ "${ignore_out}" ];
};
EOF

echo "[nix-csf] import complete"
echo "[nix-csf] summary: ${summary_out}"
echo "[nix-csf] unsupported report: ${report_file}"
echo "[nix-csf] nix snippet: ${snippet_out}"

if [[ "${strict}" == "true" && "${total_unsupported}" -gt 0 ]]; then
  echo "[nix-csf] strict mode: unsupported entries detected (${total_unsupported})" >&2
  exit 2
fi
