# no shebang - this file is loaded by netdata charts.d.plugin
# shellcheck shell=bash

nix_csf_update_every=
nix_csf_priority=162000
nix_csf_metrics_file="/var/lib/nix-csf/metrics.prom"

nix_csf_apply_success=0
nix_csf_refresh_success=0
nix_csf_cluster_cache_expired=0
nix_csf_dynamic_cache_expired=0
nix_csf_deny_ipv4=0
nix_csf_dynamic_ban_ipv4=0
nix_csf_effective_ignore_ipv4=0
nix_csf_cluster_auth_slot=0
nix_csf_dynamic_auth_slot=0

nix_csf_collect() {
  local metrics_file
  metrics_file="${nix_csf_metrics_file}"

  if [[ ! -r "${metrics_file}" ]]; then
    error "nix_csf: metrics file is missing or unreadable: ${metrics_file}"
    return 1
  fi

  while IFS='=' read -r key value; do
    case "${key}" in
      apply_success) nix_csf_apply_success="${value}" ;;
      refresh_success) nix_csf_refresh_success="${value}" ;;
      cluster_cache_expired) nix_csf_cluster_cache_expired="${value}" ;;
      dynamic_cache_expired) nix_csf_dynamic_cache_expired="${value}" ;;
      deny_ipv4) nix_csf_deny_ipv4="${value}" ;;
      dynamic_ban_ipv4) nix_csf_dynamic_ban_ipv4="${value}" ;;
      effective_ignore_ipv4) nix_csf_effective_ignore_ipv4="${value}" ;;
      cluster_auth_slot) nix_csf_cluster_auth_slot="${value}" ;;
      dynamic_auth_slot) nix_csf_dynamic_auth_slot="${value}" ;;
    esac
  done < <(
    awk '
      BEGIN {
        print "apply_success=0";
        print "refresh_success=0";
        print "cluster_cache_expired=0";
        print "dynamic_cache_expired=0";
        print "deny_ipv4=0";
        print "dynamic_ban_ipv4=0";
        print "effective_ignore_ipv4=0";
        print "cluster_auth_slot=0";
        print "dynamic_auth_slot=0";
      }
      /^nix_csf_last_run_success\{mode="apply"\}[[:space:]]+/ { print "apply_success=" $2; next }
      /^nix_csf_last_run_success\{mode="refresh"\}[[:space:]]+/ { print "refresh_success=" $2; next }
      /^nix_csf_cluster_policy_cache_expired[[:space:]]+/ { print "cluster_cache_expired=" $2; next }
      /^nix_csf_dynamic_snapshot_cache_expired[[:space:]]+/ { print "dynamic_cache_expired=" $2; next }
      /^nix_csf_set_entries\{set="deny_ipv4"\}[[:space:]]+/ { print "deny_ipv4=" $2; next }
      /^nix_csf_set_entries\{set="dynamic_ban_ipv4"\}[[:space:]]+/ { print "dynamic_ban_ipv4=" $2; next }
      /^nix_csf_set_entries\{set="effective_ignore_ipv4"\}[[:space:]]+/ { print "effective_ignore_ipv4=" $2; next }
      /^nix_csf_auth_token_selected_slot\{source="cluster_policy"\}[[:space:]]+/ { print "cluster_auth_slot=" $2; next }
      /^nix_csf_auth_token_selected_slot\{source="dynamic_offenders"\}[[:space:]]+/ { print "dynamic_auth_slot=" $2; next }
    ' "${metrics_file}"
  )

  return 0
}

nix_csf_check() {
  nix_csf_collect || return 1
  return 0
}

nix_csf_create() {
  cat <<EOFCHARTS
CHART nix_csf.run_status '' "nix-csf run status" "state" nix_csf status line ${nix_csf_priority} ${nix_csf_update_every} '' '' 'nix_csf'
DIMENSION apply_success "apply success" absolute 1 1
DIMENSION refresh_success "refresh success" absolute 1 1
CHART nix_csf.cache_expiry '' "nix-csf cache expiry" "expired" nix_csf cache line $((nix_csf_priority + 1)) ${nix_csf_update_every} '' '' 'nix_csf'
DIMENSION cluster_cache_expired "cluster policy" absolute 1 1
DIMENSION dynamic_cache_expired "dynamic snapshot" absolute 1 1
CHART nix_csf.cardinality '' "nix-csf ipv4 cardinality" "entries" nix_csf sets area $((nix_csf_priority + 2)) ${nix_csf_update_every} '' '' 'nix_csf'
DIMENSION deny_ipv4 "deny ipv4" absolute 1 1
DIMENSION dynamic_ban_ipv4 "dynamic bans" absolute 1 1
DIMENSION effective_ignore_ipv4 "effective ignore" absolute 1 1
CHART nix_csf.auth_slot '' "nix-csf auth slot" "slot" nix_csf auth line $((nix_csf_priority + 3)) ${nix_csf_update_every} '' '' 'nix_csf'
DIMENSION cluster_auth_slot "cluster policy" absolute 1 1
DIMENSION dynamic_auth_slot "dynamic offenders" absolute 1 1
EOFCHARTS

  return 0
}

nix_csf_update() {
  nix_csf_collect || return 1

  cat <<EOFVALUES
BEGIN nix_csf.run_status $1
SET apply_success = ${nix_csf_apply_success}
SET refresh_success = ${nix_csf_refresh_success}
END
BEGIN nix_csf.cache_expiry $1
SET cluster_cache_expired = ${nix_csf_cluster_cache_expired}
SET dynamic_cache_expired = ${nix_csf_dynamic_cache_expired}
END
BEGIN nix_csf.cardinality $1
SET deny_ipv4 = ${nix_csf_deny_ipv4}
SET dynamic_ban_ipv4 = ${nix_csf_dynamic_ban_ipv4}
SET effective_ignore_ipv4 = ${nix_csf_effective_ignore_ipv4}
END
BEGIN nix_csf.auth_slot $1
SET cluster_auth_slot = ${nix_csf_cluster_auth_slot}
SET dynamic_auth_slot = ${nix_csf_dynamic_auth_slot}
END
EOFVALUES

  return 0
}
