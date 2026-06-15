#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-/CETC}"
runner="/tmp/replace_container_project_$$.sh"

cat >"${runner}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /
rm -rf '${target}'
mv '${source_dir}' '${target}'
echo "已替换 ${target}"
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage1.sh' || true
grep -n "for flags" '${target}/scripts/platform/run_zhongkexin_stage1.sh' || true
rm -f '${runner}'
EOF

chmod +x "${runner}"
exec "${runner}"
