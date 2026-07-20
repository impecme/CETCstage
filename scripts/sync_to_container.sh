#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONTAINER="${CETC_CONTAINER:-gpu_04}"
DESTINATION=""
DESTINATION_READY=0
DESTINATION_EXPLICIT=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/sync_to_container.sh [options]

Stage the final repository on the host and copy it to a unique container
incoming directory. The script never overwrites /CETC.

Options:
  --container NAME       Docker container name (default: gpu_04)
  --destination PATH     Exact incoming directory in the container. Use with
                         --destination-ready after creating it interactively.
  --destination-ready    Confirm --destination was created in the container
                         through the permitted interactive shell.
  --dry-run              Build and verify the local filtered stage only
  -h, --help             Show this help

Run this script on the server host, not inside the ZQ500 container.
USAGE
}

die() {
  echo "[container-sync] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      [[ $# -ge 2 ]] || die "--container requires a value"
      CONTAINER="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || die "--destination requires a value"
      DESTINATION="$2"
      DESTINATION_EXPLICIT=1
      shift 2
      ;;
    --destination-ready)
      DESTINATION_READY=1
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
if [[ -z "${DESTINATION}" ]]; then
  DESTINATION="/CETC.incoming.$(date +%Y%m%d%H%M%S).$$.${RANDOM}"
fi
[[ "${DESTINATION}" = /* && "${DESTINATION}" != / ]] || \
  die "destination must be an absolute path other than /"
[[ ! "${DESTINATION}" =~ (^|/)\.\.?(/|$) ]] || \
  die "destination must not contain dot segments"
[[ "${DESTINATION}" =~ ^/[A-Za-z0-9][A-Za-z0-9_.-]*(/[A-Za-z0-9][A-Za-z0-9_.-]*)*$ ]] || \
  die "destination contains unsupported characters"
if [[ "${DESTINATION_READY}" -eq 1 && "${DESTINATION}" != /CETC.incoming.* ]]; then
  die "--destination-ready accepts only a unique /CETC.incoming.* path"
fi
if [[ "${DESTINATION_READY}" -eq 1 && "${DESTINATION_EXPLICIT}" -eq 0 ]]; then
  die "--destination-ready requires an explicit --destination"
fi

command -v rsync >/dev/null 2>&1 || die "rsync is required on the host"
DELIVERY_MANIFEST="${PROJECT_ROOT}/DELIVERY_FILES.txt"
[[ -f "${DELIVERY_MANIFEST}" ]] || die "missing delivery manifest: ${DELIVERY_MANIFEST}"
LC_ALL=C sort -c -u "${DELIVERY_MANIFEST}" >/dev/null || \
  die "DELIVERY_FILES.txt must be sorted and contain no duplicate paths"

manifest_count=0
while IFS= read -r relative_path; do
  [[ -n "${relative_path}" ]] || die "delivery manifest contains an empty path"
  [[ "${relative_path}" != /* ]] || die "delivery path must be relative: ${relative_path}"
  [[ ! "${relative_path}" =~ (^|/)\.\.?(/|$) ]] || \
    die "delivery path contains a dot segment: ${relative_path}"
  [[ -f "${PROJECT_ROOT}/${relative_path}" && ! -L "${PROJECT_ROOT}/${relative_path}" ]] || \
    die "delivery path is missing or not a regular file: ${relative_path}"
  manifest_count=$((manifest_count + 1))
done <"${DELIVERY_MANIFEST}"
[[ "${manifest_count}" -gt 0 ]] || die "delivery manifest is empty"

STAGE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/cetc-container-sync.XXXXXX")"
STAGE="${STAGE_PARENT}/project"
cleanup() {
  rm -rf -- "${STAGE_PARENT}"
}
trap cleanup EXIT

mkdir -p "${STAGE}"
rsync -a --files-from="${DELIVERY_MANIFEST}" "${PROJECT_ROOT}/" "${STAGE}/"

required_files=(
  README.md
  DELIVERY_FILES.txt
  CMakeLists.txt
  scripts/build.sh
  scripts/validate.sh
  scripts/demo.sh
  scripts/test_operators.sh
  scripts/finalize_reports.py
  scripts/sync_to_container.sh
  scripts/pull_results.sh
  scripts/clean.sh
  data/reports/README.md
  third_party/fftw/dist/fftw-3.3.10.tar.gz
)
for relative_path in "${required_files[@]}"; do
  [[ -f "${STAGE}/${relative_path}" ]] || die "staged delivery is missing ${relative_path}"
done

STAGED_MANIFEST="${STAGE_PARENT}/staged_files.txt"
find "${STAGE}" -type f -printf '%P\n' | LC_ALL=C sort >"${STAGED_MANIFEST}"
if ! cmp -s "${DELIVERY_MANIFEST}" "${STAGED_MANIFEST}"; then
  diff -u "${DELIVERY_MANIFEST}" "${STAGED_MANIFEST}" >&2 || true
  die "staged path set differs from DELIVERY_FILES.txt"
fi

forbidden_paths=(
  .git
  .codex
  .agents
  .vscode
  .zq500_sdk_full.delete_me
  zq500_sdk_full
  ppt_work
  复赛说明文件
  build
  build-zx
  data/.reports_staging
  data/generated/demo
  third_party/fftw/src
  third_party/fftw/build
  third_party/fftw/install
)
for relative_path in "${forbidden_paths[@]}"; do
  [[ ! -e "${STAGE}/${relative_path}" ]] || die "forbidden path entered stage: ${relative_path}"
done

file_count="$(find "${STAGE}" -type f | wc -l)"
[[ "${file_count}" -eq "${manifest_count}" ]] || die "staged file count differs from manifest"
byte_count="$(find "${STAGE}" -type f -printf '%s\n' | awk '{total += $1} END {print total + 0}')"
echo "[container-sync] verified ${file_count} files (${byte_count} bytes)"
echo "[container-sync] destination ${CONTAINER}:${DESTINATION}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[container-sync] dry-run PASS"
  exit 0
fi

command -v docker >/dev/null 2>&1 || die "docker is required on the server host"
command -v tar >/dev/null 2>&1 || die "tar is required on the server host"
[[ -S /var/run/docker.sock ]] || die "Docker socket is unavailable; run this script on the server host"

docker_command=(docker)
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required for Docker access"
  docker_command=(sudo docker)
fi

if [[ "${DESTINATION_READY}" -eq 0 ]]; then
  cat <<EOF
[container-sync] The account cannot create directories with non-interactive docker exec.
[container-sync] Create this exact unique directory through the permitted shell:
  sudo docker exec -it ${CONTAINER} bash
  mkdir ${DESTINATION}
  exit
[container-sync] Then copy the verified stage with:
  scripts/sync_to_container.sh --container ${CONTAINER} --destination ${DESTINATION} --destination-ready
EOF
  exit 3
fi
echo "[container-sync] copying into user-prepared destination ${CONTAINER}:${DESTINATION}"
"${docker_command[@]}" cp "${STAGE}/." "${CONTAINER}:${DESTINATION}/"

READBACK="${STAGE_PARENT}/readback"
mkdir -p "${READBACK}"
"${docker_command[@]}" cp "${CONTAINER}:${DESTINATION}/." - \
  | tar --extract --file=- --directory="${READBACK}" \
      --no-same-owner --no-same-permissions

HOST_HASHES="${STAGE_PARENT}/host.sha256"
READBACK_HASHES="${STAGE_PARENT}/readback.sha256"
(
  cd "${STAGE}"
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
) >"${HOST_HASHES}"
(
  cd "${READBACK}"
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
) >"${READBACK_HASHES}"
if ! cmp -s "${HOST_HASHES}" "${READBACK_HASHES}"; then
  diff -u "${HOST_HASHES}" "${READBACK_HASHES}" >&2 || true
  die "container readback differs from the staged delivery"
fi

echo "[container-sync] copy and full SHA256 readback complete"
echo "Run on the host:"
printf '  sudo docker exec -it %q bash\n' "${CONTAINER}"
echo "Then run inside the container:"
printf '  cd %q\n' "${DESTINATION}"
echo '  source /zq500/sdk/env.sh ""'
echo '  scripts/validate.sh --build-dir build-zx'
echo "After leaving the container, retrieve reports from the host with:"
printf '  scripts/pull_results.sh --container %q --container-root %q --promote-reports\n' \
  "${CONTAINER}" "${DESTINATION}"
