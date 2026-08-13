#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_PARENT="$(cd "${PROJECT_ROOT}/.." && pwd)"

CONTAINER="${CETC_CONTAINER:-gpu_04}"
CONTAINER_ROOT="${CETC_CONTAINER_ROOT:-/CETC}"
OUTPUT=""
ARTIFACT_PATHS=()
EXTRA_REPORT_PATHS=()
INCLUDE_GENERATED=0
USE_DEFAULT_REPORTS=1
ALLOW_MISSING=0
SYNC_REPORTS=0
DRY_RUN=0
REPORT_HASH_STAGE=""

usage() {
  cat <<'USAGE'
Usage: scripts/pull_results.sh [options]

Copy reports from the ZQ500 container. Use --sync-reports to merge any
available report files directly into this host repository.

Options:
  --container NAME       Docker container name (default: gpu_04)
  --container-root PATH  Project path in the container (default: /CETC)
  --output PATH          Host output directory
                         (default: ../CETC_garbage/container_pull_<timestamp>)
  --artifact PATH        Also retrieve an absolute container file or directory;
                         may be repeated
  --log PATH             Alias for --artifact PATH
  --report-path PATH     Also retrieve a report directory relative to the project;
                         may be repeated
  --no-default-reports   Do not request data/reports
  --include-generated    Also retrieve data/generated/demo
  --sync-reports         Incrementally copy container data/reports directly into
                         this repository's data/reports; preserves host files not
                         present in the container and does not require full
                         validation.
  --allow-missing        Return success when requested paths are missing; missing
                         paths are still recorded in TRANSFER_STATUS.txt
  --dry-run              Print the transfer plan without using Docker
  -h, --help             Show this help

Run this script on the server host, not inside the ZQ500 container.
USAGE
}

die() {
  echo "[container-pull] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      [[ $# -ge 2 ]] || die "--container requires a value"
      CONTAINER="$2"
      shift 2
      ;;
    --container-root)
      [[ $# -ge 2 ]] || die "--container-root requires a value"
      CONTAINER_ROOT="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a value"
      OUTPUT="$2"
      shift 2
      ;;
    --artifact|--log)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      ARTIFACT_PATHS+=("$2")
      shift 2
      ;;
    --report-path)
      [[ $# -ge 2 ]] || die "--report-path requires a value"
      EXTRA_REPORT_PATHS+=("$2")
      shift 2
      ;;
    --no-default-reports)
      USE_DEFAULT_REPORTS=0
      shift
      ;;
    --include-generated)
      INCLUDE_GENERATED=1
      shift
      ;;
    --allow-missing)
      ALLOW_MISSING=1
      shift
      ;;
    --sync-reports)
      SYNC_REPORTS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${CONTAINER}" ]] || die "container name must not be empty"
[[ "${CONTAINER}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "invalid container name"
[[ "${CONTAINER_ROOT}" = /* && "${CONTAINER_ROOT}" != / ]] || \
  die "container root must be an absolute path other than /"
CONTAINER_ROOT="${CONTAINER_ROOT%/}"
[[ ! "${CONTAINER_ROOT}" =~ (^|/)\.\.?(/|$) ]] || \
  die "container root must not contain dot segments"

normalized_artifacts=()
for artifact_path in "${ARTIFACT_PATHS[@]}"; do
  artifact_path="${artifact_path%/}"
  [[ "${artifact_path}" = /* && "${artifact_path}" != / ]] || \
    die "artifact path must be an absolute path other than /"
  [[ ! "${artifact_path}" =~ (^|/)\.\.?(/|$) ]] || \
    die "artifact path must not contain dot segments"
  [[ "${artifact_path}" != *$'\n'* ]] || die "artifact path must not contain newlines"
  normalized_artifacts+=("${artifact_path}")
done
ARTIFACT_PATHS=("${normalized_artifacts[@]}")

OUTPUT="${OUTPUT:-${HOST_PARENT}/CETC_garbage/container_pull_$(date +%Y%m%d_%H%M%S)}"
OUTPUT="$(realpath -m "${OUTPUT}")"
PROJECT_ROOT_REAL="$(realpath -m "${PROJECT_ROOT}")"
case "${OUTPUT}" in
  "${PROJECT_ROOT_REAL}"|"${PROJECT_ROOT_REAL}"/*)
    die "output must be outside the repository"
    ;;
esac
[[ ! -e "${OUTPUT}" ]] || die "output already exists: ${OUTPUT}"

relative_paths=()
if [[ "${USE_DEFAULT_REPORTS}" -eq 1 ]]; then
  relative_paths+=(
    data/reports
  )
fi
if [[ "${INCLUDE_GENERATED}" -eq 1 ]]; then
  relative_paths+=(data/generated/demo)
fi
relative_paths+=("${EXTRA_REPORT_PATHS[@]}")

normalized_relative_paths=()
for relative_path in "${relative_paths[@]}"; do
  relative_path="${relative_path%/}"
  [[ -n "${relative_path}" && "${relative_path}" != /* ]] || \
    die "report path must be non-empty and relative: ${relative_path}"
  [[ ! "${relative_path}" =~ (^|/)\.\.?(/|$) ]] || \
    die "report path must not contain dot segments: ${relative_path}"
  [[ "${relative_path}" =~ ^[A-Za-z0-9._/-]+$ ]] || \
    die "report path contains unsupported characters: ${relative_path}"
  normalized_relative_paths+=("${relative_path}")
done
relative_paths=("${normalized_relative_paths[@]}")

[[ "${#relative_paths[@]}" -gt 0 || "${#ARTIFACT_PATHS[@]}" -gt 0 ]] || \
  die "no report or artifact paths were requested"

if [[ "${SYNC_REPORTS}" -eq 1 ]]; then
  found_reports=0
  for relative_path in "${relative_paths[@]}"; do
    if [[ "${relative_path}" == "data/reports" ]]; then
      found_reports=1
      break
    fi
  done
  [[ "${found_reports}" -eq 1 ]] || \
    die "--sync-reports requires data/reports; omit --no-default-reports or add --report-path data/reports"
  [[ "${#ARTIFACT_PATHS[@]}" -eq 0 ]] || \
    die "--sync-reports only synchronizes data/reports; retrieve artifacts separately"
fi

echo "[container-pull] source ${CONTAINER}:${CONTAINER_ROOT}"
if [[ "${SYNC_REPORTS}" -eq 1 ]]; then
  echo "[container-pull] synchronize into ${PROJECT_ROOT}/data/reports"
else
  echo "[container-pull] output ${OUTPUT}"
fi
for relative_path in "${relative_paths[@]}"; do
  echo "[container-pull] include ${CONTAINER_ROOT}/${relative_path}"
done
for artifact_path in "${ARTIFACT_PATHS[@]}"; do
  echo "[container-pull] include ${artifact_path}"
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[container-pull] dry-run PASS"
  exit 0
fi

command -v docker >/dev/null 2>&1 || die "docker is required on the server host"
command -v tar >/dev/null 2>&1 || die "tar is required on the server host"
if [[ "${SYNC_REPORTS}" -eq 1 ]]; then
  command -v rsync >/dev/null 2>&1 || die "rsync is required for --sync-reports"
fi
[[ -S /var/run/docker.sock ]] || die "Docker socket is unavailable; run this script on the server host"

docker_command=(docker)
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required for Docker access"
  docker_command=(sudo docker)
fi

if [[ "${SYNC_REPORTS}" -eq 1 ]]; then
  STAGE="$(mktemp -d "${HOST_PARENT}/.container-pull.XXXXXX")"
else
  OUTPUT_PARENT="$(dirname "${OUTPUT}")"
  mkdir -p "${OUTPUT_PARENT}"
  STAGE="$(mktemp -d "${OUTPUT_PARENT}/.container-pull.XXXXXX")"
fi
cleanup() {
  if [[ -n "${STAGE:-}" && -d "${STAGE}" ]]; then
    rm -rf -- "${STAGE}"
  fi
  if [[ -n "${REPORT_HASH_STAGE:-}" && -f "${REPORT_HASH_STAGE}" ]]; then
    rm -f -- "${REPORT_HASH_STAGE}"
  fi
}
trap cleanup EXIT

missing_paths=()
copied_paths=()

for relative_path in "${relative_paths[@]}"; do
  host_path="${STAGE}/${relative_path}"
  mkdir -p "${host_path}"
  if "${docker_command[@]}" cp \
      "${CONTAINER}:${CONTAINER_ROOT}/${relative_path}/." - \
      | tar --extract --file=- --directory="${host_path}" \
          --no-same-owner --no-same-permissions; then
    copied_paths+=("${CONTAINER_ROOT}/${relative_path}")
  else
    rm -rf -- "${host_path}"
    missing_paths+=("${CONTAINER_ROOT}/${relative_path}")
    echo "[container-pull] warning: unavailable ${CONTAINER_ROOT}/${relative_path}" >&2
  fi
done

for artifact_path in "${ARTIFACT_PATHS[@]}"; do
  artifact_parent="${STAGE}/artifacts/$(dirname "${artifact_path#/}")"
  artifact_host_path="${STAGE}/artifacts/${artifact_path#/}"
  mkdir -p "${artifact_parent}"
  if "${docker_command[@]}" cp "${CONTAINER}:${artifact_path}" - \
      | tar --extract --file=- --directory="${artifact_parent}" \
          --no-same-owner --no-same-permissions; then
    copied_paths+=("${artifact_path}")
  else
    rm -rf -- "${artifact_host_path}"
    missing_paths+=("${artifact_path}")
    echo "[container-pull] warning: unavailable ${artifact_path}" >&2
  fi
done

container_file_count="$(find "${STAGE}" -type f | wc -l)"
container_byte_count="$(find "${STAGE}" -type f -printf '%s\n' | awk '{total += $1} END {print total + 0}')"

{
  if [[ "${#missing_paths[@]}" -eq 0 ]]; then
    echo 'status=complete'
  else
    echo 'status=partial'
  fi
  printf 'container=%s\n' "${CONTAINER}"
  printf 'container_root=%s\n' "${CONTAINER_ROOT}"
  printf 'copied_path_count=%s\n' "${#copied_paths[@]}"
  printf 'missing_path_count=%s\n' "${#missing_paths[@]}"
  for copied_path in "${copied_paths[@]}"; do
    printf 'copied=%s\n' "${copied_path}"
  done
  for missing_path in "${missing_paths[@]}"; do
    printf 'missing=%s\n' "${missing_path}"
  done
} >"${STAGE}/TRANSFER_STATUS.txt"

(
  cd "${STAGE}"
  find . -type f ! -name FILES.sha256 -print0 \
    | sort -z \
    | xargs -0 -r sha256sum
) >"${STAGE}/FILES.sha256"

(
  cd "${STAGE}"
  sha256sum --quiet -c FILES.sha256
)

if [[ "${SYNC_REPORTS}" -eq 1 ]]; then
  [[ "${#missing_paths[@]}" -eq 0 ]] || \
    die "cannot synchronize reports from a partial transfer"
  PULLED_REPORTS="${STAGE}/data/reports"
  [[ -d "${PULLED_REPORTS}" && ! -L "${PULLED_REPORTS}" ]] || \
    die "pulled report directory is missing or unsafe: ${PULLED_REPORTS}"
  if find "${PULLED_REPORTS}" -type l -print -quit | grep -q .; then
    die "pulled report directory contains a symbolic link"
  fi

  REPORTS_ROOT="${PROJECT_ROOT}/data/reports"
  [[ -d "${REPORTS_ROOT}" && ! -L "${REPORTS_ROOT}" ]] || \
    die "host report directory is missing or unsafe: ${REPORTS_ROOT}"
  # Task1/Task2 reports are replacement-style formal outputs.  Remove only
  # those two explicitly scoped task directories before copying the new
  # summary.csv/operators tree, so legacy scales/final Host+H2D artifacts
  # cannot survive an otherwise incremental report pull.
  for task_report in task1_radar task2_features; do
    pulled_task="${PULLED_REPORTS}/demo/${task_report}"
    host_task="${REPORTS_ROOT}/demo/${task_report}"
    if [[ -d "${pulled_task}" ]]; then
      [[ ! -L "${pulled_task}" && ! -L "${host_task}" ]] || \
        die "task report path is a symbolic link: ${task_report}"
      rm -rf "${host_task}"
    fi
  done
  rsync -a "${PULLED_REPORTS}/" "${REPORTS_ROOT}/"

  REPORT_HASH_STAGE="$(mktemp "${HOST_PARENT}/.reports-hash.XXXXXX")"
  (
    cd "${REPORTS_ROOT}"
    find . -type f ! -name FILES.sha256 -printf '%P\0' \
      | LC_ALL=C sort -z \
      | xargs -0 -r sha256sum
  ) >"${REPORT_HASH_STAGE}"
  mv "${REPORT_HASH_STAGE}" "${REPORTS_ROOT}/FILES.sha256"
  REPORT_HASH_STAGE=""

  echo "[container-pull] synchronized ${container_file_count} container files into ${REPORTS_ROOT}"
  echo "[container-pull] refreshed ${REPORTS_ROOT}/FILES.sha256"
  exit 0
fi

mv "${STAGE}" "${OUTPUT}"
STAGE=""

echo "[container-pull] copied ${container_file_count} container files (${container_byte_count} bytes)"
echo "[container-pull] SHA256 manifest: ${OUTPUT}/FILES.sha256"
if [[ "${#missing_paths[@]}" -gt 0 && "${ALLOW_MISSING}" -eq 0 ]]; then
  echo "[container-pull] partial result preserved at ${OUTPUT}" >&2
  exit 1
fi
