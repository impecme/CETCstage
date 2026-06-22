#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${V5_2_BUILD_DIR:-${PROJECT_ROOT}/build-zx}"
REPORT_DIR="${V5_2_REPORT_DIR:-${PROJECT_ROOT}/data/reports/zhongkexin/v5_2_gate_latest}"
REGISTRY="${REPORT_DIR}/all81.tsv"

cd "${PROJECT_ROOT}"
if [[ -f /zq500/sdk/env.sh ]]; then
    set +u
    # shellcheck source=/dev/null
    source /zq500/sdk/env.sh
    set -u
fi

mkdir -p "${REPORT_DIR}"
scripts/test/run_all_tests.sh --list >"${REGISTRY}"

python3 scripts/test/validate_operator_sets.py \
    --registry "${REGISTRY}" \
    --sets scripts/test/operator_sets.json \
    --summary-json "${REPORT_DIR}/operator_sets.json"

python3 scripts/test/audit_operator_interfaces.py \
    --registry "${REGISTRY}" \
    --sets scripts/test/operator_sets.json \
    --output-dir "${REPORT_DIR}/interface_audit" \
    --contract-markdown "${REPORT_DIR}/operator_contract_inventory.md"

python3 scripts/test/validate_operator_type_contracts.py \
    --registry "${REGISTRY}" \
    --contracts scripts/test/operator_type_contracts.json \
    --output-dir "${REPORT_DIR}/type_contracts" \
    --contract-markdown "${REPORT_DIR}/operator_type_contracts.md"

python3 scripts/platform/generate_zx_compat_matrix.py \
    --driver "复赛说明文件/CUDA 11.7 driver api.xlsx" \
    --runtime "复赛说明文件/CUDA 11.7 runtime API.xlsx" \
    --libraries "复赛说明文件/科学计算库实现列表.xlsx" \
    --output "${REPORT_DIR}/compatibility" \
    --summary-markdown "${REPORT_DIR}/platform_compatibility.md"

scripts/test/run_all_tests.sh \
    --platform ZHONGKEXIN \
    --module all \
    --operator all \
    --case-set accuracy \
    --warmup 0 \
    --repeat 1 \
    --build-dir "${BUILD_DIR}" \
    --emit-report

cmake --build "${BUILD_DIR}" --target \
    cusignal_type_contract_tests \
    zx_compat_compile_probes \
    zx_compat_runtime_probes \
    zx_forbidden_api_scan --parallel

ctest --test-dir "${BUILD_DIR}" \
    -R '^(cusignal_type_contract|zx_compat_runtime_safe|zx_forbidden_api_scan_test)$' \
    --output-on-failure

printf '{"status":"passed","tests":["cusignal_type_contract","zx_compat_runtime_safe","zx_forbidden_api_scan_test"]}\n' \
    >"${REPORT_DIR}/execution_stamp.json"

python3 scripts/platform/summarize_v5_2_gate.py \
    --registry "${REGISTRY}" \
    --operator-sets "${REPORT_DIR}/operator_sets.json" \
    --interface-audit "${REPORT_DIR}/interface_audit/latest_interface_audit.json" \
    --type-contracts "${REPORT_DIR}/type_contracts/latest_type_contracts.json" \
    --compatibility "${REPORT_DIR}/compatibility/summary.json" \
    --api-usage "${BUILD_DIR}/reports/zx_compatibility/api_usage.json" \
    --execution-stamp "${REPORT_DIR}/execution_stamp.json" \
    --unit-report-root data/reports/unit \
    --output-dir "${REPORT_DIR}"

echo "[v5.2-gate] PASS report=${REPORT_DIR}/summary.json"
