#!/usr/bin/env bash
set -euo pipefail

container="${1:-gpu_04}"
target="${2:-/CETC}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage="${target}.incoming.$(date +%Y%m%d%H%M%S)"
tmp="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p "${tmp}/project"
rsync -a \
  --exclude '/zq500_sdk_full/' \
  --exclude '/.zq500_sdk_full.delete_me/' \
  --exclude '/build/' \
  --exclude '/build-*/' \
  --exclude '/__cmake_systeminformation/' \
  --exclude '/*.log' \
  "${root}/" "${tmp}/project/"

wheel_count="$(find "${root}/third_party/python_wheels" -maxdepth 1 -type f -name '*.whl' 2>/dev/null | wc -l || true)"
echo "Python wheel cache count: ${wheel_count}"
if [[ "${wheel_count}" -eq 0 ]]; then
  echo "warning: third_party/python_wheels has no wheels; container may need network for Python visualization dependencies" >&2
fi

sudo -n docker cp "${tmp}/project/." "${container}:${stage}"

echo "进入容器后执行："
printf '%q %q\n' "${stage}/replace_container_project.sh" "${target}"
