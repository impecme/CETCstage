#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(\cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(\cd "$SCRIPT_DIR/.." && pwd)"

# Auto mode is repository-self-contained by default.  An explicit cache path
# still wins, while a missing repository cache safely falls back to static
# dispatch in the runtime policy.
if [[ "${CUSIGNAL_ZX_TUNING_MODE:-}" == "auto" && -z "${CUSIGNAL_ZX_TUNING_CACHE:-}" ]]; then
  repo_tuning_cache="$PROJECT_ROOT/data/tuning/zx_tuning.json"
  if [[ -f "$repo_tuning_cache" ]]; then
    export CUSIGNAL_ZX_TUNING_CACHE="$repo_tuning_cache"
  fi
fi

CONTRACT="$PROJECT_ROOT/tests/contracts/operator_sets.json"
PROFILES="$PROJECT_ROOT/tests/contracts/operator_scale_profiles.json"

BUILD_DIR="$PROJECT_ROOT/build-zx"
BUILD_TYPE="Release"
JOBS=""
DO_BUILD=1
RUN_OPERATORS=0
RUN_TASKS=0
ALL_MODE=0
OPERATOR_SET="all81"
MODULE_FILTER="all"
OPERATOR_FILTER="all"
TASK_SELECTION="both"
SCALE_SELECTION="all"
WARMUP=5
REPEAT=30
# Formal performance runs include the performance case and its CPU/GPU
# correctness comparison.  Use --case-set perf only for an explicitly
# timing-only probe; such a report must not be treated as a correctness gate.
CASE_SET="full"
SKIP_TIMING_VALIDATION=0
VERBOSE=0
OUTPUT_ROOT=""
FROZEN_BASELINE_ROOT=""
CPU_REFERENCE_CACHE_ROOT=""
OPERATOR_SELECTOR=0
TASK_SELECTOR=0

usage() {
  cat <<'USAGE'
Usage: scripts/performance.sh [options]

Selection:
  --operators              Run operator performance tests
  --tasks                  Run task performance tests
  --all                    Run all 81 operators and both tasks
  --operator-set NAME      task_used|appendix_only|task_appendix|native_only|all81
  --module NAME            Restrict the selected operator set to one module
  --operator NAME          One operator, as module/operator
  --task NAME              task1|task2|both
  --scale LEVEL            L1|L2|L3|L4|L5|L6|all

Execution:
  --build-dir PATH         Build directory (default: build-zx)
  --build-type TYPE        CMake build type (default: Release)
  --jobs N                 Parallel build jobs
  --warmup N               Warm-up iterations (default: 5)
  --repeat N               Measured repeats (default: 30)
  --case-set SET           full (default), perf (timing-only), or smoke
  --frozen-baseline PATH   Reuse the immutable baseline inputs; run optimized operators only
  --no-build               Reuse existing binaries
  --output-root PATH       Result directory (default: data/reports/autotune)
  --cpu-reference-cache PATH
                           Save complete CPU outputs and CPU medians for a full all81 run
  --help                   Show this help
USAGE
}

die() { echo "[performance] error: $*" >&2; exit 2; }

resolve_path() {
  if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s\n' "$PROJECT_ROOT/$1"; fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --operators) RUN_OPERATORS=1; OPERATOR_SELECTOR=1; shift ;;
      --tasks) RUN_TASKS=1; TASK_SELECTOR=1; shift ;;
      --all) ALL_MODE=1; shift ;;
      --operator-set)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        RUN_OPERATORS=1; OPERATOR_SELECTOR=1; OPERATOR_SET="$2"; shift 2 ;;
      --module)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        RUN_OPERATORS=1; OPERATOR_SELECTOR=1; MODULE_FILTER="$2"; shift 2 ;;
      --operator)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        RUN_OPERATORS=1; OPERATOR_SELECTOR=1; OPERATOR_FILTER="$2"; shift 2 ;;
      --task)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        RUN_TASKS=1; TASK_SELECTOR=1; TASK_SELECTION="$2"; shift 2 ;;
      --scale)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        SCALE_SELECTION="$2"; shift 2 ;;
      --build-dir)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        BUILD_DIR="$(resolve_path "$2")"; shift 2 ;;
      --build-type)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        BUILD_TYPE="$2"; shift 2 ;;
      --jobs)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        JOBS="$2"; shift 2 ;;
      --warmup)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        WARMUP="$2"; shift 2 ;;
      --repeat)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        REPEAT="$2"; shift 2 ;;
      --no-build) DO_BUILD=0; shift ;;
      --output-root)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        OUTPUT_ROOT="$(resolve_path "$2")"; shift 2 ;;
      --cpu-reference-cache)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        CPU_REFERENCE_CACHE_ROOT="$(resolve_path "$2")"; shift 2 ;;
      --case-set)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        CASE_SET="$2"; shift 2 ;;
      --frozen-baseline)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        FROZEN_BASELINE_ROOT="$(resolve_path "$2")"; shift 2 ;;
      --skip-timing-validation) SKIP_TIMING_VALIDATION=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
}

validate_args() {
  if (( ALL_MODE )); then
    (( OPERATOR_SELECTOR == 0 && TASK_SELECTOR == 0 )) || die "--all cannot be combined with selectors"
    RUN_OPERATORS=1; RUN_TASKS=1; OPERATOR_SET="all81"; MODULE_FILTER="all"; OPERATOR_FILTER="all"; TASK_SELECTION="both"
  elif (( RUN_OPERATORS == 0 && RUN_TASKS == 0 )); then
    RUN_OPERATORS=1; RUN_TASKS=1
  fi
  if [[ "$OPERATOR_FILTER" == */* ]]; then
    operator_module="${OPERATOR_FILTER%%/*}"
    operator_name="${OPERATOR_FILTER#*/}"
    [[ -n "$operator_module" && -n "$operator_name" ]] || die "--operator must be module/operator"
    [[ "$MODULE_FILTER" == "all" || "$MODULE_FILTER" == "$operator_module" ]] || die "--operator conflicts with --module"
    MODULE_FILTER="$operator_module"; OPERATOR_FILTER="$operator_name"
  elif [[ "$OPERATOR_FILTER" != "all" && "$MODULE_FILTER" == "all" ]]; then
    die "--operator must be module/operator when --module is omitted"
  fi
  case "$TASK_SELECTION" in task1|task2|both) ;; *) die "--task must be task1, task2, or both" ;; esac
  case "$SCALE_SELECTION" in L1|L2|L3|L4|L5|L6|all) ;; *) die "--scale must be L1, L2, L3, L4, L5, L6, or all" ;; esac
  case "$CASE_SET" in full|perf|smoke) ;; *) die "unsupported case set: $CASE_SET" ;; esac
  [[ "$WARMUP" =~ ^[0-9]+$ ]] || die "--warmup must be a non-negative integer"
  [[ "$REPEAT" =~ ^[1-9][0-9]*$ ]] || die "--repeat must be a positive integer"
  [[ -z "$JOBS" || "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
  if [[ "$CASE_SET" == smoke ]]; then WARMUP=0; REPEAT=1; SCALE_SELECTION=L3; else (( REPEAT >= 3 )) || die "performance repeat must be >= 3"; fi
  if [[ -n "$FROZEN_BASELINE_ROOT" ]]; then
    (( RUN_OPERATORS == 1 && RUN_TASKS == 0 )) || die "--frozen-baseline is only valid for operator-only runs"
    [[ -d "$FROZEN_BASELINE_ROOT" ]] || die "frozen baseline directory does not exist: $FROZEN_BASELINE_ROOT"
    python3 "$SCRIPT_DIR/operator_gpu_protocol.py" --validate-baseline "$FROZEN_BASELINE_ROOT" ||
      die "frozen baseline validation failed"
  fi
  if [[ -n "$CPU_REFERENCE_CACHE_ROOT" ]]; then
    (( RUN_OPERATORS == 1 && RUN_TASKS == 0 )) ||
      die "--cpu-reference-cache is only valid for operator-only runs"
    [[ "$OPERATOR_SET" == "all81" ]] ||
      die "--cpu-reference-cache requires --operator-set all81"
    [[ "$SCALE_SELECTION" == "all" ]] ||
      die "--cpu-reference-cache requires --scale all"
    [[ "$CASE_SET" == "full" ]] ||
      die "--cpu-reference-cache requires --case-set full"
    [[ -n "$FROZEN_BASELINE_ROOT" ]] ||
      die "--cpu-reference-cache requires --frozen-baseline"
    [[ ! -e "$CPU_REFERENCE_CACHE_ROOT" ]] ||
      die "CPU reference cache path already exists; choose a new path: $CPU_REFERENCE_CACHE_ROOT"
  fi
}

selected_operator_records() {
  python3 - "$CONTRACT" "$OPERATOR_SET" "$MODULE_FILTER" "$OPERATOR_FILTER" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
set_name, module_filter, operator_filter = sys.argv[2:5]
payload = json.loads(path.read_text(encoding="utf-8"))
sets = payload.get("sets", {})
all81 = sets.get("all81", {}).get("operators", [])
if len(all81) != 81:
    raise SystemExit("invalid all81 operator set")

def resolve(name, stack=()):
    if name in stack:
        raise SystemExit("operator-set cycle: " + name)
    item = sets.get(name)
    if not isinstance(item, dict):
        raise SystemExit("unknown operator set: " + name)
    if "operators" in item:
        values = list(item["operators"])
    else:
        included = set()
        for child in item.get("include_sets", []):
            included.update(resolve(child, stack + (name,)))
        excluded = set()
        for child in item.get("exclude_sets", []):
            excluded.update(resolve(child, stack + (name,)))
        values = [key for key in all81 if key in included and key not in excluded]
    if len(values) != item.get("expected_count") or len(set(values)) != len(values):
        raise SystemExit("operator-set count mismatch: " + name)
    return values

records = []
for key in resolve(set_name):
    module, operator = key.split("/", 1)
    if module_filter != "all" and module != module_filter:
        continue
    if operator_filter != "all" and operator != operator_filter:
        continue
    target = module + "_test_" + operator
    records.append((module, operator, target, "tests/unit/" + module + "/" + target))
if not records:
    raise SystemExit("no operator matched the requested selectors")
for record in records:
    print("|".join(record))
PY
}

build_selected() {
  (( DO_BUILD )) || return 0
  args=(--build-dir "$BUILD_DIR" --build-type "$BUILD_TYPE")
  [[ -n "$JOBS" ]] && args+=(--jobs "$JOBS")
  if (( ALL_MODE )); then
    args+=(--all)
  else
    if (( RUN_OPERATORS )); then
      args+=(--operators --operator-set "$OPERATOR_SET")
      [[ "$MODULE_FILTER" != all ]] && args+=(--module "$MODULE_FILTER")
      [[ "$OPERATOR_FILTER" != all ]] && args+=(--operator "$MODULE_FILTER/$OPERATOR_FILTER")
    fi
    if (( RUN_TASKS )); then args+=(--tasks "$TASK_SELECTION"); fi
  fi
  printf '[performance] build selection:'
  printf ' %s' "${args[@]}"
  printf '\n'
  "$SCRIPT_DIR/build.sh" "${args[@]}"
}

prepare_operator_inputs() {
  output_root="$1"
  level="$2"
  python3 - "$CONTRACT" "$PROFILES" "$OPERATOR_SET" "$MODULE_FILTER" "$OPERATOR_FILTER" "$level" \
    "$PROJECT_ROOT/data/generated/unit" "$output_root" <<'PY'
import copy
import json
import math
import sys
from pathlib import Path

contract_path, profile_path = Path(sys.argv[1]), Path(sys.argv[2])
set_name, module_filter, operator_filter, level = sys.argv[3:7]
source_root, output_root = Path(sys.argv[7]), Path(sys.argv[8])
contract = json.loads(contract_path.read_text(encoding="utf-8"))
profiles_payload = json.loads(profile_path.read_text(encoding="utf-8"))
sets = contract["sets"]
all81 = sets["all81"]["operators"]

def resolve(name, stack=()):
    if name in stack:
        raise RuntimeError("operator-set cycle: " + name)
    item = sets[name]
    if "operators" in item:
        return list(item["operators"])
    included = set()
    for child in item.get("include_sets", []):
        included.update(resolve(child, stack + (name,)))
    excluded = set()
    for child in item.get("exclude_sets", []):
        excluded.update(resolve(child, stack + (name,)))
    return [key for key in all81 if key in included and key not in excluded]

operators = []
for key in resolve(set_name):
    module, operator = key.split("/", 1)
    if module_filter != "all" and module != module_filter:
        continue
    if operator_filter != "all" and operator != operator_filter:
        continue
    operators.append(key)
if not operators:
    raise RuntimeError("no operator matched the requested selectors")
levels = profiles_payload["levels"]
if level not in levels:
    raise RuntimeError("invalid scale level: " + level)
specs = profiles_payload["operators"]
profiles = profiles_payload["profiles"]
index = levels.index(level)

def set_path(payload, path, value, allow_create=False):
    parts = path.split(".")
    current = payload
    for part in parts[:-1]:
        if not isinstance(current, dict) or part not in current:
            raise RuntimeError("missing manifest field: " + path)
        current = current[part]
    if not isinstance(current, dict) or (parts[-1] not in current and not allow_create):
        raise RuntimeError("missing manifest field: " + path)
    current[parts[-1]] = copy.deepcopy(value)

def product(value):
    if isinstance(value, list) and value and all(isinstance(item, int) and item > 0 for item in value):
        return math.prod(value)
    return None

output_root.mkdir(parents=True, exist_ok=True)
metadata = {"schema_version": 1, "scale_level": level, "operator_set": set_name, "operators": {}}
for key in operators:
    manifest_path = source_root / key / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError("missing operator manifest: " + str(manifest_path))
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    cases = payload.get("perf_cases")
    if not isinstance(cases, list) or not cases or not isinstance(cases[0], dict):
        raise RuntimeError("invalid perf_cases: " + str(manifest_path))
    spec = specs[key]
    profile = profiles[spec["profile"]]
    values = profile["levels"][index]
    reduced = copy.deepcopy(cases[0])
    applied = {}
    for target, source in spec["fields"].items():
        if source not in values:
            raise RuntimeError("missing profile field " + source + ": " + key)
        set_path(reduced, target, values[source], target in spec.get("create_fields", []))
        applied[target] = copy.deepcopy(values[source])
    reduced["scale_level"] = level
    reduced["scale_kind"] = profile["scale_kind"]
    payload["perf_cases"] = [reduced]
    destination = output_root / key / "manifest.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    workload = []
    for value in applied.values():
        candidate = product(value)
        if candidate is None and isinstance(value, int) and value > 0:
            candidate = value
        if isinstance(candidate, int) and candidate > 0:
            workload.append(candidate)
    metadata["operators"][key] = {
        "operator": key,
        "scale_level": level,
        "scale_kind": profile["scale_kind"],
        "scale_profile": spec["profile"],
        "scale_fields": applied,
        "input_elements": max(workload, default=0),
        "power_of_two_dimensions": all(
            all(isinstance(item, int) and item > 0 and (item & (item - 1)) == 0 for item in value)
            for value in applied.values() if isinstance(value, list) and value
        ),
    }
(output_root / "scale_metadata.json").write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

run_operator_tests() {
  raw_root="$1"
  mapfile -t records < <(selected_operator_records)
  [[ "${records[*]-}" != "" ]] || die "no operator matched the requested selectors"
  if [[ "$CASE_SET" == smoke ]]; then
    rm -rf -- "$PROJECT_ROOT/data/.reports_staging/unit"
    for record in "${records[@]}"; do
      IFS='|' read -r module operator target binary_rel <<<"$record"
      binary="$BUILD_DIR/$binary_rel"
      [[ -x "$binary" ]] || die "missing operator binary: $binary"
      command=("$binary" --case-set smoke --warmup 0 --repeat 1 --emit-report)
      (( VERBOSE )) && command+=(--verbose)
      echo "[performance] smoke operator $module/$operator"
      "${command[@]}" || die "operator smoke failed: $module/$operator"
    done
    return 0
  fi

  levels=(L1 L2 L3 L4 L5 L6)
  [[ "$SCALE_SELECTION" == all ]] || levels=("$SCALE_SELECTION")
  gpu_reference_root="$FROZEN_BASELINE_ROOT"
  if [[ -n "$FROZEN_BASELINE_ROOT" && -d "$FROZEN_BASELINE_ROOT/gpu_reference" ]]; then
    gpu_reference_root="$FROZEN_BASELINE_ROOT/gpu_reference"
  fi
  for level in "${levels[@]}"; do
    manifest_root="$raw_root/manifests/$level"
    if [[ -n "$FROZEN_BASELINE_ROOT" ]]; then
      frozen_manifest_root="$gpu_reference_root/inputs/$level"
      frozen_metadata="$gpu_reference_root/inputs/${level}_scale_metadata.json"
      [[ -d "$frozen_manifest_root" ]] || die "missing frozen manifest root: $frozen_manifest_root"
      [[ -f "$frozen_metadata" ]] || die "missing frozen scale metadata: $frozen_metadata"
      mkdir -p "$manifest_root"
      cp -a "$frozen_manifest_root/." "$manifest_root/"
      cp "$frozen_metadata" "$manifest_root/scale_metadata.json"
      echo "[performance] operators $level: using frozen baseline manifests"
    else
      prepare_operator_inputs "$manifest_root" "$level"
    fi
    run_manifest_root="$manifest_root"
    if [[ -n "$CPU_REFERENCE_CACHE_ROOT" ]]; then
      cache_level_root="$CPU_REFERENCE_CACHE_ROOT/$level"
      mkdir -p "$cache_level_root"
      cp -a "$manifest_root/." "$cache_level_root/"
      run_manifest_root="$cache_level_root"
    fi
    rm -rf -- "$PROJECT_ROOT/data/.reports_staging/unit"
    echo "[performance] operators $level: $OPERATOR_SET"
    for record in "${records[@]}"; do
      IFS='|' read -r module operator target binary_rel <<<"$record"
      binary="$BUILD_DIR/$binary_rel"
      [[ -x "$binary" ]] || die "missing operator binary: $binary"
      command=("$binary" --case-set "$CASE_SET" --warmup "$WARMUP" --repeat "$REPEAT" --emit-report)
      (( VERBOSE )) && command+=(--verbose)
      echo "[performance] operator $module/$operator"
      # Formal operator E2E timing must upload the host input on every measured
      # iteration. Workspace/allocation caches remain enabled, while backend
      # value caches are bypassed by this benchmark-only switch.
      benchmark_env=(
        "CUSIGNAL_GENERATED_UNIT_ROOT=$run_manifest_root"
        "CUSIGNAL_PERF_FRESH_INPUT=1"
      )
      if [[ -n "$CPU_REFERENCE_CACHE_ROOT" ]]; then
        benchmark_env+=("CUSIGNAL_CPU_REFERENCE_CACHE_WRITE=1")
      fi
      [[ -n "${CUSIGNAL_SKIP_CPU_TIMING:-}" ]] &&
        benchmark_env+=("CUSIGNAL_SKIP_CPU_TIMING=$CUSIGNAL_SKIP_CPU_TIMING")
      if ! env "${benchmark_env[@]}" "${command[@]}"; then
        die "operator performance failed: $module/$operator/$level"
      fi
      source_metrics="$PROJECT_ROOT/data/.reports_staging/unit/$module/$operator/latest_metrics.json"
      [[ -f "$source_metrics" ]] || die "missing operator report: $source_metrics"
      mkdir -p "$raw_root/reports/$level/$module/$operator"
      cp "$source_metrics" "$raw_root/reports/$level/$module/$operator/latest_metrics.json"
      for artifact in latest_cases.csv latest_summary.md; do
        source_artifact="$PROJECT_ROOT/data/.reports_staging/unit/$module/$operator/$artifact"
        if [[ -f "$source_artifact" ]]; then
          cp "$source_artifact" "$raw_root/reports/$level/$module/$operator/$artifact"
        fi
      done
      if [[ -n "$CPU_REFERENCE_CACHE_ROOT" ]]; then
        cp "$source_metrics" "$run_manifest_root/$module/$operator/latest_metrics.json"
      fi
    done
    cp "$manifest_root/scale_metadata.json" "$raw_root/reports/$level/scale_metadata.json"
  done
}

write_cpu_reference_cache_metadata() {
  [[ -n "$CPU_REFERENCE_CACHE_ROOT" ]] || return 0
  python3 - "$CPU_REFERENCE_CACHE_ROOT" "$FROZEN_BASELINE_ROOT" "$WARMUP" "$REPEAT" "$PROJECT_ROOT" <<'PY'
import csv
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

cache_root = Path(sys.argv[1]).resolve()
baseline_root = Path(sys.argv[2]).resolve()
warmup, repeat = map(int, sys.argv[3:5])
project_root = Path(sys.argv[5]).resolve()

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def current_commit() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=project_root, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"

levels = [f"L{index}" for index in range(1, 7)]
workloads = []
errors = []
for level in levels:
    metadata_path = cache_root / level / "scale_metadata.json"
    if not metadata_path.is_file():
        errors.append(f"missing scale metadata: {metadata_path}")
        continue
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    operators = metadata.get("operators", {})
    if not isinstance(operators, dict):
        errors.append(f"invalid scale metadata: {metadata_path}")
        continue
    for key, item in sorted(operators.items()):
        workload_error_count = len(errors)
        operator_dir = cache_root / level / key
        manifest_path = operator_dir / "manifest.json"
        metrics_path = operator_dir / "latest_metrics.json"
        cpu_files = sorted((operator_dir / "output_samples").glob("*__cpu__*.csv"))
        if not manifest_path.is_file():
            errors.append(f"missing manifest: {level}/{key}")
        if not metrics_path.is_file():
            errors.append(f"missing metrics: {level}/{key}")
        if not cpu_files:
            errors.append(f"missing complete CPU output files: {level}/{key}")
        file_records = []
        for path in cpu_files:
            if path.stat().st_size == 0:
                errors.append(f"empty CPU output file: {path}")
                continue
            with path.open(encoding="utf-8") as handle:
                row_count = max(sum(1 for _ in handle) - 1, 0)
            file_records.append({
                "path": path.relative_to(cache_root).as_posix(),
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
                "data_rows": row_count,
            })
        cpu_median_ms = None
        if metrics_path.is_file():
            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            summary = payload.get("summary", {})
            cpu = summary.get("cpu_perf", {})
            if isinstance(cpu, dict):
                cpu_median_ms = cpu.get("median_ms")
        workloads.append({
            "operator": key,
            "scale_level": level,
            "scale_profile": item.get("scale_profile"),
            "scale_fields": item.get("scale_fields", {}),
            "input_elements": item.get("input_elements"),
            "manifest": {
                "path": manifest_path.relative_to(cache_root).as_posix(),
                "sha256": sha256(manifest_path) if manifest_path.is_file() else None,
            },
            "metrics": {
                "path": metrics_path.relative_to(cache_root).as_posix(),
                "sha256": sha256(metrics_path) if metrics_path.is_file() else None,
                "cpu_median_ms": cpu_median_ms,
            },
            "cpu_output_files": file_records,
            "cpu_reference_complete": bool(file_records) and len(errors) == workload_error_count,
        })

metadata = {
    "schema_version": 1,
    "status": "COMPLETE" if not errors and len(workloads) == 486 else "INCOMPLETE",
    "created_at": datetime.now(timezone.utc).isoformat(),
    "source_commit": current_commit(),
    "source_tree": "working-tree",
    "operator_set": "all81",
    "operator_count": 81,
    "expected_workloads": 486,
    "workload_count": len(workloads),
    "scale_levels": levels,
    "warmup": warmup,
    "repeat": repeat,
    "input_refresh_policy": "per_iteration_reconstruct",
    "input_values_policy": "manifest_clone",
    "output_policy": "complete_cpu_outputs_not_32_value_samples",
    "frozen_baseline": {
        "root": str(baseline_root),
        "gpu_baseline_sha256": sha256(baseline_root / "gpu_baseline.csv"),
        "frozen_sha256": sha256(baseline_root / "FROZEN"),
    },
    "workloads": workloads,
    "errors": errors,
}
(cache_root / "cache_metadata.json").write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
if errors or len(workloads) != 486:
    raise SystemExit("CPU reference cache incomplete; see cache_metadata.json")
print(f"[performance] CPU reference cache: COMPLETE workloads={len(workloads)} root={cache_root}")
PY
  python3 "$SCRIPT_DIR/cpu_reference_cache.py" "$CPU_REFERENCE_CACHE_ROOT"
}

write_operator_report() {
  raw_root="$1"
  selected_operator_count="$(selected_operator_records | wc -l)"
  python3 - "$raw_root/reports" "$OUTPUT_ROOT/units/benchmarks" "$OPERATOR_SET" "$SCALE_SELECTION" "$WARMUP" "$REPEAT" "$CASE_SET" "$MODULE_FILTER" "$OPERATOR_FILTER" "$selected_operator_count" <<'PY'
import csv
import json
import math
import os
import sys
from pathlib import Path

raw_root, output_root = Path(sys.argv[1]), Path(sys.argv[2])
operator_set, selection = sys.argv[3:5]
warmup_runs, measured_repeat_runs = map(int, sys.argv[5:7])
case_set = sys.argv[7]
module_filter, operator_filter = (sys.argv[8:10] if len(sys.argv) >= 10 else ("all", "all"))
selected_operator_count = int(sys.argv[10]) if len(sys.argv) >= 11 else None
skip_cpu_timing = os.environ.get("CUSIGNAL_SKIP_CPU_TIMING", "").lower() in {"1", "true", "on"}
levels = [f"L{n}" for n in range(1, 7)] if selection == "all" else [selection]
rows = []
for level in levels:
    metadata = json.loads((raw_root / level / "scale_metadata.json").read_text(encoding="utf-8"))["operators"]
    for key, item in metadata.items():
        module, operator = key.split("/", 1)
        if module_filter != "all" and module != module_filter:
            continue
        if operator_filter != "all" and operator != operator_filter:
            continue
        payload = json.loads((raw_root / level / module / operator / "latest_metrics.json").read_text(encoding="utf-8"))
        summary = payload.get("summary", {})
        zx_tuning = summary.get("zx_tuning", {})
        if not isinstance(zx_tuning, dict):
            zx_tuning = {}
        zx_config = zx_tuning.get("config", {})
        if not isinstance(zx_config, dict):
            zx_config = {}
        if case_set == "full" and int(summary.get("accuracy_cases", 0) or 0) <= 0:
            raise RuntimeError("formal operator report has no accuracy cases: " + key + "/" + level)
        input_refresh = summary.get("input_refresh", {})
        if case_set == "full" and input_refresh.get("pass") is not True:
            raise RuntimeError("input refresh protocol failed: " + key + "/" + level)
        non_kernel_overhead = summary.get("non_kernel_overhead", {})
        memory_policy = summary.get("memory_policy", {})
        non_kernel_overhead_fields = (
            "allocation_calls",
            "allocation_bytes",
            "plan_create_calls",
            "plan_destroy_calls",
            "event_create_calls",
            "event_destroy_calls",
            "explicit_device_sync_calls",
            "h2d_calls",
            "h2d_bytes",
            "d2h_calls",
            "d2h_bytes",
            "materialize_calls",
        )

        def non_kernel_overhead_value(name):
            # Counts are protocol values, never timing estimates.  Keep the
            # explicit N/A marker for legacy reports or uninstrumented paths.
            if not isinstance(non_kernel_overhead, dict):
                return "N/A"
            value = non_kernel_overhead.get(name)
            if value == "N/A" or value is None:
                return "N/A"
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                return "N/A"
            return value

        def memory_value(name, string=False):
            # Memory telemetry is optional for legacy reports.  Do not infer
            # peak usage from cumulative H2D bytes or from kernel time.
            if not isinstance(memory_policy, dict):
                return "N/A" if string else None
            value = memory_policy.get(name)
            if string:
                return value if isinstance(value, str) and value else "N/A"
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                return None
            if not math.isfinite(float(value)) or value < 0:
                return None
            return value

        def timing(name, allow_missing=False):
            value = summary.get(name, {}).get("median_ms")
            if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
                if allow_missing:
                    return None
                raise RuntimeError("missing timing " + name + ": " + key + "/" + level)
            return float(value)
        def optional_stage_timing(name):
            value = summary.get(name, {}).get("median_ms")
            if not isinstance(value, (int, float)) or not math.isfinite(float(value)) or value <= 0:
                return None
            return float(value)

        error_fields = ("max_abs_error", "max_rel_error", "mixed_error", "rmse", "l2_error")

        def merge_error_objects(objects):
            values = {field: [] for field in error_fields}
            exact_values = []
            for obj in objects:
                if not isinstance(obj, dict):
                    continue
                for field in error_fields:
                    value = obj.get(field)
                    if isinstance(value, (int, float)) and math.isfinite(float(value)):
                        values[field].append(float(value))
                if isinstance(obj.get("exact_match"), bool):
                    exact_values.append(obj["exact_match"])
            merged = {
                field: (max(items) if items else None) for field, items in values.items()
            }
            merged["exact_match"] = all(exact_values) if exact_values else None
            return merged

        def cpu_gpu_error_record(case_key="cpu_gpu_error", summary_key="cpu_gpu_error", include_flat_summary=True):
            if case_set != "full":
                # A timing-only run intentionally has no correctness sample.
                return merge_error_objects([])
            perf_objects = [
                case[case_key]
                for case in payload.get("cases", [])
                if isinstance(case, dict)
                and case.get("category") == "perf"
                and isinstance(case.get(case_key), dict)
            ]
            if perf_objects:
                # The published scale row must describe the current scale's
                # perf input, not the unrelated fixed-size accuracy cases.
                return merge_error_objects(perf_objects)
            objects = []
            if summary_key and isinstance(summary.get(summary_key), dict):
                objects.append(summary[summary_key])
            for case in payload.get("cases", []):
                if isinstance(case, dict) and isinstance(case.get(case_key), dict):
                    objects.append(case[case_key])
            if include_flat_summary:
                flat = {field: summary.get(field) for field in error_fields}
                if any(value is not None for value in flat.values()):
                    objects.append(flat)
            return merge_error_objects(objects)

        cpu_gpu_error = cpu_gpu_error_record()
        correctness_status = (
            "PASS" if case_set == "full" and summary.get("pass") is True else
            "FAIL" if case_set == "full" and summary.get("pass") is False else
            "NOT_REPORTED"
        )
        cpu = timing("cpu_perf", allow_missing=skip_cpu_timing)
        e2e = timing("gpu_e2e_perf")
        kernel = timing("gpu_kernel_perf", allow_missing=True)
        if kernel is not None and kernel <= 0:
            kernel = None
        if e2e is None or e2e <= 0 or (cpu is not None and cpu <= 0):
            raise RuntimeError("invalid timing: " + key + "/" + level)
        rows.append({
            "operator": key,
            "module": module,
            "name": operator,
            "scale_level": level,
            "scale_kind": item["scale_kind"],
            "scale_profile": item["scale_profile"],
            "scale_fields": json.dumps(item["scale_fields"], ensure_ascii=False, sort_keys=True),
            "input_elements": item["input_elements"],
            "power_of_two_dimensions": item["power_of_two_dimensions"],
            "warmup": warmup_runs,
            "repeat": measured_repeat_runs,
            "case_set": case_set,
            "cpu_median_ms": cpu,
            "gpu_e2e_median_ms": e2e,
            "gpu_kernel_median_ms": kernel,
            "gpu_e2e_speedup": cpu / e2e if cpu is not None else None,
            "gpu_kernel_speedup": cpu / kernel if cpu is not None and kernel and kernel > 0.0 else None,
            "gpu_acceleration_eligible": summary.get("gpu_acceleration_eligible"),
            "path_kind": summary.get("path_kind"),
            "tuning_family": zx_tuning.get("family"),
            "tuning_operator_id": zx_tuning.get("operator_id"),
            "tuning_registry_version": zx_tuning.get("registry_version"),
            "tuning_key": zx_tuning.get("key"),
            "tuning_candidate": zx_tuning.get("candidate"),
            "tuning_source": zx_tuning.get("source"),
            "tuning_reason": zx_tuning.get("reason"),
            "tuning_threads": zx_config.get("threads"),
            "tuning_tile_rows": zx_config.get("tile_rows"),
            "tuning_tile_cols": zx_config.get("tile_cols"),
            "tuning_elements_per_thread": zx_config.get("elements_per_thread"),
            "tuning_rows_per_block": zx_config.get("rows_per_block"),
            "tuning_vector_width": zx_config.get("vector_width"),
            "tuning_stages": zx_config.get("stages"),
            "tuning_scan_elements": zx_config.get("scan_elements"),
            "tuning_buffer_count": zx_config.get("buffer_count"),
            "tuning_batch_tile": zx_config.get("batch_tile"),
            "tuning_memory_tier": zx_config.get("memory_tier"),
            "tuning_plan_variant": zx_config.get("plan_variant"),
            "tuning_workspace_bytes": zx_config.get("workspace_bytes"),
            "tuning_workspace_peak_bytes": zx_config.get("workspace_peak_bytes"),
            "tuning_device_id": zx_tuning.get("device", {}).get("id") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_device_name": zx_tuning.get("device", {}).get("name") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_runtime_version": zx_tuning.get("device", {}).get("runtime_version") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_compute_major": zx_tuning.get("device", {}).get("compute_major") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_compute_minor": zx_tuning.get("device", {}).get("compute_minor") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_total_global_mem": zx_tuning.get("device", {}).get("total_global_mem") if isinstance(zx_tuning.get("device"), dict) else None,
            "tuning_device_target": zx_tuning.get("device", {}).get("target") if isinstance(zx_tuning.get("device"), dict) else None,
            "input_kind": summary.get("input_kind"),
            "input_refresh_pass": input_refresh.get("pass"),
            "input_refresh_expected_iterations": input_refresh.get("expected_iterations"),
            "input_refresh_observed_iterations": input_refresh.get("observed_iterations"),
            "input_h2d_copy_calls": input_refresh.get("h2d_copy_calls"),
            "input_h2d_bytes": input_refresh.get("h2d_bytes"),
            "input_iterations_with_h2d": input_refresh.get("iterations_with_h2d"),
            "input_min_h2d_bytes_per_iteration": input_refresh.get("min_h2d_bytes_per_iteration"),
            "input_max_h2d_bytes_per_iteration": input_refresh.get("max_h2d_bytes_per_iteration"),
            # Unit tests do not claim a stage split unless the backend reports
            # one explicitly.  Missing stages remain null/blank rather than
            # being inferred from the E2E number.
            "host_input_ms": optional_stage_timing("host_input_perf"),
            "h2d_ms": optional_stage_timing("h2d_perf"),
            "gpu_compute_ms": optional_stage_timing("gpu_compute_perf"),
            "d2h_ms": optional_stage_timing("d2h_perf"),
            "host_output_ms": optional_stage_timing("host_output_perf"),
            "cpu_gpu_max_abs_error": cpu_gpu_error["max_abs_error"],
            "cpu_gpu_max_rel_error": cpu_gpu_error["max_rel_error"],
            "cpu_gpu_mixed_error": cpu_gpu_error["mixed_error"],
            "cpu_gpu_rmse": cpu_gpu_error["rmse"],
            "cpu_gpu_l2_error": cpu_gpu_error["l2_error"],
            "cpu_gpu_exact_match": cpu_gpu_error["exact_match"],
            "error_scope": "perf_case_cpu_gpu" if case_set == "full" else "not_reported",
            "correctness_status": correctness_status,
            "error_threshold_source": "existing_operator_test_contract",
            "status": correctness_status,
        })
        for field in non_kernel_overhead_fields:
            rows[-1]["non_kernel_overhead_" + field] = non_kernel_overhead_value(field)
        rows[-1].update({
            "gpu_total_memory_bytes": memory_value("gpu_total_memory_bytes"),
            "gpu_peak_used_bytes": memory_value("gpu_peak_used_bytes"),
            "gpu_peak_used_ratio": memory_value("gpu_peak_used_ratio"),
            "workspace_peak_bytes": memory_value("workspace_peak_bytes"),
            "device_cache_peak_bytes": memory_value("device_cache_peak_bytes"),
            "memory_budget_bytes": memory_value("memory_budget_bytes"),
            "chunk_elements": memory_value("chunk_elements"),
            "chunk_count": memory_value("chunk_count"),
            "memory_policy": memory_value("memory_policy", string=True),
            "memory_fallback_reason": memory_value("memory_fallback_reason", string=True),
        })
rows.sort(key=lambda row: (row["operator"], row["scale_level"]))
if not rows:
    raise RuntimeError("operator report is empty")
expected_operators = {
    "all81": 81,
    "task_appendix": 53,
    "task_used": 18,
    "appendix_only": 37,
    "native_only": 26,
}.get(operator_set)
if selection == "all" and expected_operators is not None:
    if (module_filter != "all" or operator_filter != "all") and selected_operator_count is not None:
        expected_operators = selected_operator_count
    actual_operators = len({row["operator"] for row in rows})
    expected_rows = expected_operators * len(levels)
    if actual_operators != expected_operators or len(rows) != expected_rows:
        raise RuntimeError(
            f"incomplete operator report for {operator_set}: "
            f"operators={actual_operators}/{expected_operators} rows={len(rows)}/{expected_rows}"
        )
output_root.mkdir(parents=True, exist_ok=True)
# Keep the aggregate report and the historical per-operator artifacts under
# the same formal output root.  The direct-writer unit test passes a generic
# output directory instead of the production */units/benchmarks directory.
units_root = output_root.parent if output_root.name == "benchmarks" else output_root / "units"
for row in rows:
    source_root = raw_root / row["scale_level"] / row["module"] / row["name"]
    unit_root = units_root / row["module"] / row["name"] / row["scale_level"]
    unit_root.mkdir(parents=True, exist_ok=True)
    for source_name, published_name in (
        ("latest_metrics.json", "metrics.json"),
        ("latest_cases.csv", "cases.csv"),
        ("latest_summary.md", "summary.md"),
    ):
        destination = unit_root / published_name
        if destination.exists():
            destination.unlink()
        source = source_root / source_name
        if source.is_file():
            destination.write_bytes(source.read_bytes())
# Remove the pre-unified aggregate names so a rerun cannot leave two
# competing performance versions in the published directory.
for legacy in (output_root / "summary.csv", output_root / "summary.json"):
    if legacy.exists():
        legacy.unlink()
fields = list(rows[0])
with (output_root / "operator_scales.csv").open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
(output_root / "operator_scales.json").write_text(json.dumps({
    "schema_version": 3,
    "operator_set": operator_set,
    "operator_count": len({row["operator"] for row in rows}),
    "scale_levels": levels,
    "warmup": warmup_runs,
    "repeat": measured_repeat_runs,
    "case_set": case_set,
    "correctness_gate": case_set == "full",
    "non_kernel_overhead_protocol_version": 1,
    "non_kernel_overhead_missing_value": "N/A",
    "memory_policy_protocol_version": 1,
    "memory_policy_missing_value": "N/A",
    "rows": rows,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
lines = [
    "# 算子性能汇总", "",
    "- 算子集合：" + operator_set,
    "- 规模：" + ", ".join(levels),
    f"- 计时：warmup={warmup_runs}，repeat={measured_repeat_runs}，正式结果取中位数", "",
    "| 算子 | 规模 | CPU median ms | GPU E2E median ms | CPU→GPU E2E 加速比 | GPU kernel median ms | max_abs | max_rel | mixed | RMSE | 正确性 |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
]
for row in rows:
    kernel = "—" if row["gpu_kernel_median_ms"] is None else f"{row['gpu_kernel_median_ms']:.6f}"
    def metric(name):
        value = row.get(name)
        return "—" if value is None else f"{value:.6g}"
    def timing(name, digits=6):
        value = row.get(name)
        return "—" if value is None else f"{value:.{digits}f}"
    def speedup(name):
        value = row.get(name)
        return "—" if value is None else f"{value:.3f}x"
    lines.append("| {operator} | {scale} | {cpu} | {e2e} | {es} | {kernel} | {abs} | {rel} | {mixed} | {rmse} | {correctness} |".format(
        operator=row["operator"], scale=row["scale_level"],
        cpu=timing("cpu_median_ms"), e2e=timing("gpu_e2e_median_ms"),
        es=speedup("gpu_e2e_speedup"), kernel=kernel,
        abs=metric("cpu_gpu_max_abs_error"),
        rel=metric("cpu_gpu_max_rel_error"), mixed=metric("cpu_gpu_mixed_error"),
        rmse=metric("cpu_gpu_rmse"), correctness=row["correctness_status"]))
lines.extend([
    "", "## 非内核开销协议", "",
    "缺失或未接入 backend 的计数统一记为 `N/A`；不从 E2E 推算。", "",
    "| 算子 | 规模 | allocation calls | allocation bytes | plan create | plan destroy | event create | event destroy | device sync | H2D calls | H2D bytes | D2H calls | D2H bytes | materialize |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
])
for row in rows:
    def counter(name):
        value = row.get("non_kernel_overhead_" + name, "N/A")
        return "N/A" if value in (None, "") else str(value)
    lines.append("| {operator} | {scale} | {allocation_calls} | {allocation_bytes} | {plan_create_calls} | {plan_destroy_calls} | {event_create_calls} | {event_destroy_calls} | {explicit_device_sync_calls} | {h2d_calls} | {h2d_bytes} | {d2h_calls} | {d2h_bytes} | {materialize_calls} |".format(
        operator=row["operator"], scale=row["scale_level"],
        allocation_calls=counter("allocation_calls"), allocation_bytes=counter("allocation_bytes"),
        plan_create_calls=counter("plan_create_calls"), plan_destroy_calls=counter("plan_destroy_calls"),
        event_create_calls=counter("event_create_calls"), event_destroy_calls=counter("event_destroy_calls"),
        explicit_device_sync_calls=counter("explicit_device_sync_calls"),
        h2d_calls=counter("h2d_calls"), h2d_bytes=counter("h2d_bytes"),
        d2h_calls=counter("d2h_calls"), d2h_bytes=counter("d2h_bytes"),
        materialize_calls=counter("materialize_calls")))
lines.extend([
    "", "## 容量感知显存与分块", "",
    "峰值显存来自分配器统计和独立 memory audit；`input_h2d_bytes` 仍是迭代累计值，不能替代峰值显存。", "",
    "| 算子 | 规模 | total bytes | peak used bytes | peak ratio | workspace peak | cache peak | budget | chunk elements | chunk count | policy | fallback |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
])
for row in rows:
    def memory_text(name):
        value = row.get(name)
        return "N/A" if value is None or value == "" else str(value)
    lines.append("| {operator} | {scale} | {total} | {peak} | {ratio} | {workspace} | {cache} | {budget} | {chunk} | {count} | {policy} | {reason} |".format(
        operator=row["operator"], scale=row["scale_level"],
        total=memory_text("gpu_total_memory_bytes"), peak=memory_text("gpu_peak_used_bytes"),
        ratio=memory_text("gpu_peak_used_ratio"), workspace=memory_text("workspace_peak_bytes"),
        cache=memory_text("device_cache_peak_bytes"), budget=memory_text("memory_budget_bytes"),
        chunk=memory_text("chunk_elements"), count=memory_text("chunk_count"),
        policy=memory_text("memory_policy"), reason=memory_text("memory_fallback_reason")))
(output_root / "operator_scales.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("[performance] operator report: " + str(output_root) + " (" + str(len(rows)) + " rows)")
PY
}

print_published_summary() {
  python3 - "$OUTPUT_ROOT" "$RUN_OPERATORS" "$RUN_TASKS" <<'PY'
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1])
run_operators = sys.argv[2] == "1"
run_tasks = sys.argv[3] == "1"

def value(row, key, default="—"):
    value = row.get(key, "")
    return value if value not in (None, "") else default

if run_operators:
    path = root / "units/benchmarks/operator_scales.csv"
    if not path.is_file():
        raise SystemExit(f"missing final operator report: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    operators = {row.get("operator") for row in rows}
    scales = sorted({row.get("scale_level") for row in rows})
    print(f"[performance] FINAL operators rows={len(rows)} operators={len(operators)} scales={','.join(scales)}")
    print("operator,scale,warmup,repeat,cpu_median_ms,gpu_e2e_median_ms,gpu_kernel_median_ms,e2e_speedup,cpu_wall_over_gpu_kernel,status")
    for row in rows:
        print(",".join([
            value(row, "operator"), value(row, "scale_level"),
            value(row, "warmup"), value(row, "repeat"),
            value(row, "cpu_median_ms"), value(row, "gpu_e2e_median_ms"),
            value(row, "gpu_kernel_median_ms"), value(row, "gpu_e2e_speedup"),
            value(row, "gpu_kernel_speedup"), value(row, "status"),
        ]))

if run_tasks:
    for task in ("task1_radar", "task2_features"):
        path = root / "demo" / task / "summary.csv"
        if not path.is_file():
            raise SystemExit(f"missing final task report: {path}")
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        print(f"[performance] FINAL task={task} rows={len(rows)}")
        print("task,scale,cpu_total_ms,gpu_e2e_ms,gpu_kernel_ms,e2e_speedup,validation_pass")
        for row in rows:
            print(",".join([
                value(row, "task"), value(row, "scale"),
                value(row, "cpu_total_ms"), value(row, "gpu_e2e_ms"),
                value(row, "gpu_kernel_ms"), value(row, "e2e_speedup"),
                value(row, "validation_pass"),
            ]))
PY
}

run_task() {
  task="$1"
  level="$2"
  raw_root="$3"
  if [[ "$task" == task1 ]]; then
    executable="$BUILD_DIR/demo/task1_radar/task1_radar_demo"
    report_name=task1_radar
  else
    executable="$BUILD_DIR/demo/task2_features/task2_features_demo"
    report_name=task2_features
  fi
  [[ -x "$executable" ]] || die "missing task binary: $executable"
  scale_number="${level#L}"
  args=(--warmup "$WARMUP" --repeat "$REPEAT" --scale-level "$scale_number" --invalid-input-checks --unified-scale-protocol)
  (( SKIP_TIMING_VALIDATION )) && args+=(--skip-timing-validation)
  echo "[performance] $task $level"
  "$executable" "${args[@]}" || die "task performance failed: $task/$level"
  source_root="$PROJECT_ROOT/data/.reports_staging/demo/$report_name"
  [[ -f "$source_root/latest_metrics.json" ]] || die "missing task report: $source_root"
  [[ -f "$source_root/latest_summary.csv" ]] || die "missing task summary CSV: $source_root/latest_summary.csv"
  [[ -f "$source_root/latest_operators.csv" ]] || die "missing task operator CSV: $source_root/latest_operators.csv"
  [[ -f "$source_root/latest_stages.csv" ]] || die "missing task stage CSV: $source_root/latest_stages.csv"
  destination="$raw_root/tasks/$task/$level"
  mkdir -p "$destination"
  for artifact in "$source_root"/latest_*; do
    [[ -f "$artifact" ]] && cp "$artifact" "$destination/"
  done
  scenario="$PROJECT_ROOT/data/generated/demo/$report_name/input/scenario.json"
  [[ -f "$scenario" ]] && cp "$scenario" "$destination/input_scenario.json"
}

run_task_tests() {
  raw_root="$1"
  levels=(L1 L2 L3 L4 L5 L6)
  [[ "$SCALE_SELECTION" == all ]] || levels=("$SCALE_SELECTION")
  tasks=(task1 task2)
  [[ "$TASK_SELECTION" == both ]] || tasks=("$TASK_SELECTION")
  [[ "$CASE_SET" == smoke ]] && levels=(L3)
  for level in "${levels[@]}"; do
    for task in "${tasks[@]}"; do
      run_task "$task" "$level" "$raw_root"
    done
  done
  echo "[performance] task reports: $raw_root/tasks"
}

publish_task_reports() {
  raw_root="$1"
  destination_root="$2"
  for task in task1 task2; do
    [[ "$TASK_SELECTION" == both || "$TASK_SELECTION" == "$task" ]] || continue
    if [[ "$task" == task1 ]]; then
      report_name=task1_radar
    else
      report_name=task2_features
    fi
    task_report_root="$destination_root/demo/$report_name"
    mkdir -p "$task_report_root"
    # The task contract has one authoritative aggregate CSV and one
    # per-scale operator directory. Remove legacy task report families from
    # this generated destination so stale Host+H2D artifacts cannot remain
    # part of the formal result set.
    rm -rf "$task_report_root/scales" "$task_report_root/final"
    rm -f "$task_report_root/metrics.json" "$task_report_root/stage_timings.csv" \
      "$task_report_root/step_metrics.csv" "$task_report_root/step_metrics.json" \
      "$task_report_root/summary.md"
    rm -rf "$task_report_root/operators" "$task_report_root/stages"
    mkdir -p "$task_report_root/operators"
    mkdir -p "$task_report_root/stages"
    for level in L1 L2 L3 L4 L5 L6; do
      [[ "$SCALE_SELECTION" == all || "$SCALE_SELECTION" == "$level" ]] || continue
      source="$raw_root/tasks/$task/$level"
      [[ -d "$source" ]] || continue
      [[ ! -f "$source/latest_summary.csv" ]] || cp "$source/latest_summary.csv" "$task_report_root/.summary_$level.csv"
      if [[ -f "$source/latest_operators.csv" ]]; then
        cp "$source/latest_operators.csv" "$task_report_root/operators/$level.csv"
      fi
      if [[ -f "$source/latest_stages.csv" ]]; then
        cp "$source/latest_stages.csv" "$task_report_root/stages/$level.csv"
      fi
    done
    python3 - "$task_report_root" <<'PY'
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = []
for path in sorted(root.glob(".summary_L*.csv")):
    with path.open(newline="", encoding="utf-8") as handle:
        rows.extend(csv.DictReader(handle))
if rows:
    with (root / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
for path in root.glob(".summary_L*.csv"):
    path.unlink()
PY
  done
}

main() {
  parse_args "$@"
  validate_args
  cd "$PROJECT_ROOT"
  if [[ -f /zq500/sdk/env.sh ]]; then
    set +u
    # shellcheck source=/dev/null
    source /zq500/sdk/env.sh ""
    set -u
  fi
  if [[ -z "$OUTPUT_ROOT" ]]; then
    OUTPUT_ROOT="$PROJECT_ROOT/data/reports/autotune"
  fi
  mkdir -p "$OUTPUT_ROOT"
  raw_root="$PROJECT_ROOT/data/.reports_staging/performance/run_$(date +%Y%m%d_%H%M%S)_$$"
  mkdir -p "$raw_root"
  build_selected
  if (( RUN_OPERATORS )); then
    run_operator_tests "$raw_root"
    write_cpu_reference_cache_metadata
    [[ "$CASE_SET" == smoke ]] || write_operator_report "$raw_root"
  fi
  if (( RUN_TASKS )); then
    run_task_tests "$raw_root"
    publish_task_reports "$raw_root" "$OUTPUT_ROOT"
  fi
  if [[ "$CASE_SET" == perf ]]; then
    print_published_summary
  fi
  echo "[performance] PASS: $OUTPUT_ROOT"
}

main "$@"
