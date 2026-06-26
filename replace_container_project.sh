#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-/CETC}"
runner="/tmp/replace_container_project_$$.sh"
preserve_dir="/tmp/cetc_replace_preserve_$$"

cat >"${runner}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /
mkdir -p '${preserve_dir}'
if [[ -d '${target}/build-zx' ]]; then
    mv '${target}/build-zx' '${preserve_dir}/build-zx'
fi
if [[ -d '${target}/data/reports' ]]; then
    mkdir -p '${preserve_dir}/data'
    mv '${target}/data/reports' '${preserve_dir}/data/reports'
fi
if [[ -d '${target}/data/generated' ]]; then
    mkdir -p '${preserve_dir}/data'
    mv '${target}/data/generated' '${preserve_dir}/data/generated'
fi
rm -rf '${target}'
mv '${source_dir}' '${target}'
if [[ -d '${preserve_dir}/build-zx' ]]; then
    mv '${preserve_dir}/build-zx' '${target}/build-zx'
    echo "已保留 ${target}/build-zx"
fi
if [[ -d '${preserve_dir}/data/reports' ]]; then
    mkdir -p '${target}/data'
    mv '${preserve_dir}/data/reports' '${target}/data/reports'
    echo "已保留 ${target}/data/reports"
fi
if [[ -d '${preserve_dir}/data/generated' ]]; then
    mkdir -p '${target}/data'
    mv '${preserve_dir}/data/generated' '${target}/data/generated'
    echo "已保留 ${target}/data/generated"
fi
rm -rf '${preserve_dir}'
echo "已替换 ${target}"
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage1.sh' || true
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage2.sh' || true
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage3.sh' || true
grep -n "script version" '${target}/scripts/platform/run_zhongkexin_stage4.sh' || true
echo "Python requirements:"
sed -n '1,20p' '${target}/scripts/platform/zhongkexin_python_requirements.txt' || true
wheel_count=\$(find '${target}/third_party/python_wheels' -maxdepth 1 -type f -name '*.whl' 2>/dev/null | wc -l || true)
echo "Python wheel cache count: \${wheel_count}"
echo "新容器 shell 运行项目前请执行:"
echo "  cd ${target}"
echo "  source /zq500/sdk/env.sh"
rm -f '${runner}'
EOF

chmod +x "${runner}"
exec "${runner}"
