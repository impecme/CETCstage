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
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage2.sh' || true
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage3.sh' || true
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage4.sh' || true
echo "Python requirements:"
sed -n '1,20p' '${target}/scripts/platform/zhongkexin_python_requirements.txt' || true
wheel_count=\$(find '${target}/third_party/python_wheels' -maxdepth 1 -type f -name '*.whl' 2>/dev/null | wc -l || true)
echo "Python wheel cache count: \${wheel_count}"
rm -f '${runner}'
EOF

chmod +x "${runner}"
exec "${runner}"
