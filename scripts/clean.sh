#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GENERATED_ROOT="${PROJECT_ROOT}/data/generated"
REPORTS_ROOT="${PROJECT_ROOT}/data/reports"
DRY_RUN=0
REMOVED_COUNT=0

usage() {
  cat <<'EOF'
Usage: scripts/clean.sh [--dry-run] [--help]

Deletes runtime-generated data under:
  - data/generated (keeps manifest.json)
  - data/.reports_staging

Does not touch:
  - data/reference
  - data/reports/ (published current-code reports)
EOF
}

log() {
  echo "[clean-data] $*"
}

remove_path() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    return
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "would remove: ${path}"
  else
    log "remove: ${path}"
    rm -rf -- "${path}"
  fi
  ((REMOVED_COUNT += 1))
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        echo "[clean-data] error: unknown argument: $1" >&2
        exit 2
        ;;
    esac
  done
}

clean_generated() {
  local path

  if [[ ! -d "${GENERATED_ROOT}" ]]; then
    return
  fi

  while IFS= read -r -d '' path; do
    remove_path "${path}"
  done < <(find "${GENERATED_ROOT}" -type d \( -name input -o -name output_samples \) -print0 | sort -z)

  while IFS= read -r -d '' path; do
    remove_path "${path}"
  done < <(
    find "${GENERATED_ROOT}" \
      \( -type d \( -name input -o -name output_samples \) -prune \) -o \
      \( -type f ! -name manifest.json -print0 \)
  )
}

clean_reports() {
  local path
  for path in \
    "${PROJECT_ROOT}/data/.reports_staging"; do
    remove_path "${path}"
  done
}

main() {
  parse_args "$@"

  clean_generated
  clean_reports

  if [[ "${REMOVED_COUNT}" -eq 0 ]]; then
    log "nothing to clean"
    exit 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry run complete, matched ${REMOVED_COUNT} path(s)"
  else
    log "clean complete, removed ${REMOVED_COUNT} path(s)"
  fi
}

main "$@"
