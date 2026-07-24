#!/usr/bin/env bash

set -euo pipefail

# Build exactly the binaries required by scripts/ppt_performance.sh --live-demo.
# This command performs no measurements and is intended for pre-stage setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="build-zx"

usage() {
  cat <<'USAGE'
Usage: scripts/build_live_demo.sh [--build-dir DIR]

Prebuild the core53 unit-test binaries plus task1_radar_demo and
task2_features_demo for the cold-start live demonstration. No test or task is
executed by this script.
USAGE
}

die() {
  echo "[build-live-demo] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
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

mapfile -t UNIT_TARGETS < <(
  python3 - "${PROJECT_ROOT}/tests/contracts/operator_sets.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
sets = payload.get("sets")
if not isinstance(sets, dict):
    raise SystemExit("operator_sets.json missing sets")

all81_item = sets.get("all81")
all81 = all81_item.get("operators") if isinstance(all81_item, dict) else None
if not isinstance(all81, list) or len(all81) != 81:
    raise SystemExit("operator_sets.json has invalid all81")

def resolve(name, resolving=None):
    resolving = set() if resolving is None else resolving
    if name in resolving:
        raise SystemExit(f"operator-set cycle: {name}")
    item = sets.get(name)
    if not isinstance(item, dict):
        raise SystemExit(f"unknown operator set: {name}")
    resolving.add(name)
    if "operators" in item:
        values = item["operators"]
        if not isinstance(values, list):
            raise SystemExit(f"invalid operators in {name}")
        result = list(values)
    else:
        included = set()
        for include in item.get("include_sets", []):
            included.update(resolve(include, resolving))
        excluded = set()
        for exclude in item.get("exclude_sets", []):
            excluded.update(resolve(exclude, resolving))
        result = [key for key in all81 if key in included and key not in excluded]
    resolving.remove(name)
    return result

core53 = resolve("core53")
if len(core53) != 53:
    raise SystemExit(f"core53 target count mismatch: {len(core53)}")
for key in core53:
    module, operator = key.split("/", 1)
    print(f"{module}_test_{operator}")
PY
)

[[ ${#UNIT_TARGETS[@]} -eq 53 ]] || die "expected 53 core53 test targets"

BUILD_ARGS=(
  --build-dir "${BUILD_DIR}"
  --target task1_radar_demo
  --target task2_features_demo
)
for target in "${UNIT_TARGETS[@]}"; do
  BUILD_ARGS+=(--target "${target}")
done

echo "[build-live-demo] targets: 53 core53 tests + 2 task demos"
"${SCRIPT_DIR}/build.sh" "${BUILD_ARGS[@]}"
echo "[build-live-demo] PASS"
