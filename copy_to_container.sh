#!/usr/bin/env bash
set -euo pipefail

container="${1:-gpu_04}"
target="${2:-/CETC}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage="${target}.incoming.$(date +%Y%m%d%H%M%S)"

sudo docker cp "${root}/." "${container}:${stage}"

echo "进入容器后执行："
printf '%q %q\n' "${stage}/replace_container_project.sh" "${target}"
