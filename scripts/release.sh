#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"

usage() {
  cat <<'USAGE'
Usage:
  release.sh --version <semver> [--dry-run] [--no-validate] [--push] [--allow-dirty]

Options:
  --version <semver>  Target SemVer version (for example: 0.2.0, 1.0.0-rc.1).
  --dry-run           Execute checks and validation, but do not commit or tag.
  --no-validate       Skip ./scripts/validate.sh.
  --push              Push commit and tag to origin after creating them.
  --allow-dirty       Allow a dirty working tree (not recommended).
  -h, --help          Show this help message.
USAGE
}

fail() {
  echo "nix-csf-release: ERROR: $*" >&2
  exit 1
}

say() {
  echo "nix-csf-release: $*"
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

target_version=""
dry_run="false"
run_validate="true"
do_push="false"
allow_dirty="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      target_version="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --no-validate)
      run_validate="false"
      shift
      ;;
    --push)
      do_push="true"
      shift
      ;;
    --allow-dirty)
      allow_dirty="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${target_version}" ]]; then
  usage >&2
  fail "--version is required"
fi

if ! is_semver "${target_version}"; then
  fail "--version must be valid SemVer (for example 0.2.0 or 1.0.0-rc.1)"
fi

if [[ ! -f "${VERSION_FILE}" ]]; then
  fail "missing VERSION file at ${VERSION_FILE}"
fi

if ! git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "${ROOT_DIR} is not a git repository"
fi

if [[ "${allow_dirty}" != "true" ]]; then
  if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain)" ]]; then
    fail "working tree is dirty; commit or stash changes first (or use --allow-dirty)"
  fi
fi

current_branch="$(git -C "${ROOT_DIR}" symbolic-ref --quiet --short HEAD || true)"
if [[ -z "${current_branch}" ]]; then
  fail "detached HEAD is not supported for release tagging"
fi

if git -C "${ROOT_DIR}" rev-parse --verify --quiet "refs/tags/v${target_version}" >/dev/null; then
  fail "tag v${target_version} already exists"
fi

current_version="$(tr -d '\r\n' < "${VERSION_FILE}")"
if [[ "${target_version}" == "${current_version}" ]]; then
  fail "target version equals current VERSION (${current_version})"
fi

version_written="false"
version_committed="false"
cleanup() {
  if [[ "${version_written}" == "true" && "${version_committed}" == "false" ]]; then
    printf '%s\n' "${current_version}" > "${VERSION_FILE}"
  fi
}
trap cleanup EXIT

say "preparing release v${target_version} from branch ${current_branch}"
printf '%s\n' "${target_version}" > "${VERSION_FILE}"
version_written="true"

if [[ "${run_validate}" == "true" ]]; then
  say "running validation suite"
  "${ROOT_DIR}/scripts/validate.sh"
fi

if [[ "${dry_run}" == "true" ]]; then
  say "dry-run complete (no commit/tag created)"
  exit 0
fi

git -C "${ROOT_DIR}" add VERSION
git -C "${ROOT_DIR}" commit -m "release: v${target_version}"
version_committed="true"

git -C "${ROOT_DIR}" tag -a "v${target_version}" -m "release v${target_version}"

if [[ "${do_push}" == "true" ]]; then
  say "pushing commit and tag to origin"
  git -C "${ROOT_DIR}" push origin HEAD
  git -C "${ROOT_DIR}" push origin "v${target_version}"
fi

trap - EXIT
say "release created: v${target_version}"
if [[ "${do_push}" != "true" ]]; then
  say "next step: push with 'git -C ${ROOT_DIR} push origin HEAD && git -C ${ROOT_DIR} push origin v${target_version}'"
fi
