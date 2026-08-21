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
DEMO_MODE=0
DEMO_DRY_RUN=0
DEMO_REFERENCE_ROOT=""
DEMO_CACHE=""
DEMO_SELECTION_FILE=""
DEMO_START_SECONDS=0
DEMO_DEADLINE_SECONDS=285
DEMO_OUTPUT_EPHEMERAL=0

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
  --output-root PATH       Result directory (demo default is temporary; otherwise data/reports/autotune)
  --cpu-reference-cache PATH
                           Save complete CPU outputs and CPU medians for a full all81 run
  --demo                   Run the 53-operator + Task1/Task2 five-minute field demo
  --demo-dry-run           Select demo workloads and print the time estimate only
  --demo-reference-root PATH
                           Reference report root used to select the best scale
  --demo-cache PATH        Exact operator/task tuning cache used by the demo
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
      --demo) DEMO_MODE=1; shift ;;
      --demo-dry-run) DEMO_MODE=1; DEMO_DRY_RUN=1; shift ;;
      --demo-reference-root)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        DEMO_REFERENCE_ROOT="$(resolve_path "$2")"; shift 2 ;;
      --demo-cache)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        DEMO_CACHE="$(resolve_path "$2")"; shift 2 ;;
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
  if (( DEMO_MODE )); then
    (( ALL_MODE == 0 && OPERATOR_SELECTOR == 0 && TASK_SELECTOR == 0 )) \
      || die "--demo cannot be combined with --all, operator, or task selectors"
    [[ -z "$FROZEN_BASELINE_ROOT" ]] ||
      die "--frozen-baseline is not supported with --demo; demo inputs use the selected scale profiles"
    [[ -z "$CPU_REFERENCE_CACHE_ROOT" ]] ||
      die "--cpu-reference-cache is not supported with --demo"
    RUN_OPERATORS=1
    RUN_TASKS=1
    OPERATOR_SET="task_appendix"
    MODULE_FILTER="all"
    OPERATOR_FILTER="all"
    TASK_SELECTION="both"
    SCALE_SELECTION="all"
    DO_BUILD=0
    WARMUP=1
    REPEAT=3
    CASE_SET="perf"
    [[ -n "$DEMO_REFERENCE_ROOT" ]] ||
      DEMO_REFERENCE_ROOT="$PROJECT_ROOT/data/reports/autotune"
    [[ -n "$DEMO_CACHE" ]] ||
      DEMO_CACHE="$PROJECT_ROOT/data/tuning/zx_tuning.json"
    [[ -d "$DEMO_REFERENCE_ROOT" ]] ||
      die "demo reference root does not exist: $DEMO_REFERENCE_ROOT"
    [[ -f "$DEMO_REFERENCE_ROOT/units/benchmarks/operator_scales.csv" ]] ||
      die "missing demo operator reference: $DEMO_REFERENCE_ROOT/units/benchmarks/operator_scales.csv"
    [[ -f "$DEMO_REFERENCE_ROOT/demo/task1_radar/summary.csv" ]] ||
      die "missing demo Task1 reference: $DEMO_REFERENCE_ROOT/demo/task1_radar/summary.csv"
    [[ -f "$DEMO_REFERENCE_ROOT/demo/task2_features/summary.csv" ]] ||
      die "missing demo Task2 reference: $DEMO_REFERENCE_ROOT/demo/task2_features/summary.csv"
    [[ -f "$DEMO_CACHE" ]] || die "missing demo tuning cache: $DEMO_CACHE"
    command -v timeout >/dev/null 2>&1 || die "--demo requires the timeout command"
    return 0
  fi
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

prepare_demo_selection() {
  local selection_path="$1"
  python3 - "$CONTRACT" "$DEMO_REFERENCE_ROOT" "$DEMO_CACHE" "$selection_path" <<'PY'
import csv
import json
import math
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
reference_root = Path(sys.argv[2])
cache_path = Path(sys.argv[3])
selection_path = Path(sys.argv[4])

payload = json.loads(contract_path.read_text(encoding="utf-8"))
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

operators = resolve("task_appendix")
if len(operators) != 53:
    raise SystemExit(f"task_appendix must contain 53 operators, got {len(operators)}")

def as_float(row, name):
    value = row.get(name, "")
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) and value > 0 else None

def is_true(value):
    return str(value).strip().lower() in {"1", "true", "yes", "pass"}

def valid_operator_row(row):
    return (
        row.get("case_set") == "full"
        and row.get("status") == "PASS"
        and row.get("correctness_status") == "PASS"
        and is_true(row.get("input_refresh_pass"))
        and as_float(row, "cpu_median_ms") is not None
        and as_float(row, "gpu_e2e_median_ms") is not None
    )

operator_candidates = {}
operator_csv = reference_root / "units/benchmarks/operator_scales.csv"
with operator_csv.open(newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        key = row.get("operator", "")
        if key not in operators or not valid_operator_row(row):
            continue
        cpu = as_float(row, "cpu_median_ms")
        gpu = as_float(row, "gpu_e2e_median_ms")
        speedup = cpu / gpu
        candidate = {
            "operator": key,
            "scale_level": row.get("scale_level", ""),
            "reference_cpu_median_ms": cpu,
            "reference_gpu_e2e_median_ms": gpu,
            "reference_gpu_kernel_median_ms": as_float(row, "gpu_kernel_median_ms"),
            "reference_speedup": speedup,
            "reference_candidate": row.get("tuning_candidate", ""),
            "reference_tuning_source": row.get("tuning_source", ""),
            "reference_tuning_registry_version": row.get("tuning_registry_version", ""),
            "reference_input_refresh_pass": is_true(row.get("input_refresh_pass")),
            "reference_correctness_status": row.get("correctness_status", ""),
        }
        operator_candidates.setdefault(key, []).append(candidate)

operator_reference = {}
for key, candidates in operator_candidates.items():
    candidates.sort(
        key=lambda item: (
            item["reference_speedup"],
            -item["reference_gpu_e2e_median_ms"],
            item["scale_level"],
        ),
        reverse=True,
    )
    best = dict(candidates[0])
    best["alternatives"] = [dict(item) for item in candidates[1:]]
    operator_reference[key] = best

missing = [key for key in operators if key not in operator_reference]
if missing:
    raise SystemExit("missing valid reference rows for: " + ", ".join(missing))

task_reference = {}
task_files = {
    "task1": reference_root / "demo/task1_radar/summary.csv",
    "task2": reference_root / "demo/task2_features/summary.csv",
}
expected_task_levels = ["L1", "L2", "L3", "L4", "L5", "L6"]
for task, path in task_files.items():
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    valid = []
    for row in rows:
        cpu = as_float(row, "cpu_total_ms")
        gpu = as_float(row, "gpu_e2e_ms")
        if row.get("validation_pass") != "PASS" or cpu is None or gpu is None:
            continue
        level = "L" + str(row.get("scale", "")).lstrip("L")
        valid.append({
            "task": row.get("task", task),
            "scale_level": level,
            "input_elements": as_float(row, "input_elements"),
            "reference_cpu_total_ms": cpu,
            "reference_gpu_e2e_ms": gpu,
            "reference_gpu_kernel_ms": as_float(row, "gpu_kernel_ms"),
            "reference_speedup": cpu / gpu,
            "reference_validation_pass": row.get("validation_pass", ""),
        })
    valid.sort(key=lambda item: int(item["scale_level"][1:]))
    levels = [item["scale_level"] for item in valid]
    if levels != expected_task_levels:
        raise SystemExit(
            f"task reference must contain exactly L1-L6: {task} has {levels}"
        )
    task_reference[task] = valid

cache = json.loads(cache_path.read_text(encoding="utf-8"))
if not isinstance(cache, dict) or not isinstance(cache.get("entries"), list):
    raise SystemExit("invalid demo tuning cache: entries must be a list")
cache_registry = cache.get("registry_version", "")
reference_registries = {
    item["reference_tuning_registry_version"]
    for item in operator_reference.values()
    if item["reference_tuning_registry_version"]
}
if cache_registry and reference_registries and cache_registry not in reference_registries:
    raise SystemExit(
        "demo cache registry does not match reference report: "
        + str(cache_registry) + " not in " + ", ".join(sorted(reference_registries))
    )

scale_counts = {}
for item in operator_reference.values():
    scale_counts[item["scale_level"]] = scale_counts.get(item["scale_level"], 0) + 1
task_used = set(resolve("task_used"))
appendix_only = set(resolve("appendix_only"))
operator_layers = {
    "task_used": [key for key in operators if key in task_used],
    "appendix_only": [key for key in operators if key in appendix_only],
}
if len(operator_layers["task_used"]) + len(operator_layers["appendix_only"]) != len(operators):
    raise SystemExit("demo operator layers do not partition task_appendix")
task_workload_count = sum(len(items) for items in task_reference.values())
selection = {
    "schema_version": 1,
    "operator_count": len(operator_reference),
    "task_count": len(task_reference),
    "selected_workload_count": len(operator_reference) + task_workload_count,
    "task_workload_count": task_workload_count,
    "reference_root": str(reference_root.resolve()),
    "cache": str(cache_path.resolve()),
    "cache_registry_version": cache_registry,
    "operator_scale_counts": dict(sorted(scale_counts.items())),
    "operator_layers": operator_layers,
    "operators": dict(sorted(operator_reference.items())),
    "tasks": task_reference,
}
selection_path = selection_path.resolve()
selection_path.parent.mkdir(parents=True, exist_ok=True)
selection_path.write_text(json.dumps(selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(
    "[performance] demo selection: operators=53 tasks=2 task_workloads=12 "
    "workloads=65 "
    + "scale_counts=" + json.dumps(dict(sorted(scale_counts.items())), sort_keys=True)
)
PY
}

demo_operator_records_for_level() {
  local level="$1"
  python3 - "$DEMO_SELECTION_FILE" "$level" <<'PY'
import json
import sys

selection = json.load(open(sys.argv[1], encoding="utf-8"))
level = sys.argv[2]
for key, item in sorted(selection["operators"].items()):
    if item["scale_level"] != level:
        continue
    module, operator = key.split("/", 1)
    target = module + "_test_" + operator
    print("|".join((module, operator, target, "tests/unit/" + module + "/" + target)))
PY
}

demo_levels() {
  python3 - "$DEMO_SELECTION_FILE" <<'PY'
import json
import sys

selection = json.load(open(sys.argv[1], encoding="utf-8"))
levels = sorted(
    {item["scale_level"] for item in selection["operators"].values()},
    key=lambda value: int(value[1:]),
)
for level in levels:
    print(level)
PY
}

demo_task_level() {
  python3 - "$DEMO_SELECTION_FILE" "$1" <<'PY'
import json
import sys

selection = json.load(open(sys.argv[1], encoding="utf-8"))
print(selection["tasks"][sys.argv[2]]["scale_level"])
PY
}

demo_check_deadline() {
  local elapsed=$((SECONDS - DEMO_START_SECONDS))
  (( elapsed < DEMO_DEADLINE_SECONDS )) ||
    die "demo exceeded ${DEMO_DEADLINE_SECONDS}s deadline"
}

run_demo_command() {
  local elapsed remaining
  elapsed=$((SECONDS - DEMO_START_SECONDS))
  remaining=$((DEMO_DEADLINE_SECONDS - elapsed))
  (( remaining > 0 )) || die "demo exceeded ${DEMO_DEADLINE_SECONDS}s deadline"
  timeout --signal=TERM --kill-after=5s "${remaining}s" "$@"
}

validate_demo_binaries() {
  local record module operator target binary_rel binary
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    IFS='|' read -r module operator target binary_rel <<<"$record"
    binary="$BUILD_DIR/$binary_rel"
    [[ -x "$binary" ]] || die "missing demo operator binary: $binary"
  done < <(python3 - "$DEMO_SELECTION_FILE" <<'PY'
import json
import sys

selection = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sorted(selection["operators"]):
    module, operator = key.split("/", 1)
    target = module + "_test_" + operator
    print("|".join((module, operator, target, "tests/unit/" + module + "/" + target)))
PY
  )
  [[ -x "$BUILD_DIR/demo/task1_radar/task1_radar_demo" ]] ||
    die "missing demo Task1 binary: $BUILD_DIR/demo/task1_radar/task1_radar_demo"
  [[ -x "$BUILD_DIR/demo/task2_features/task2_features_demo" ]] ||
    die "missing demo Task2 binary: $BUILD_DIR/demo/task2_features/task2_features_demo"
}

print_demo_dry_run() {
  python3 - "$DEMO_SELECTION_FILE" "$DEMO_DEADLINE_SECONDS" <<'PY'
import json
import sys

selection = json.load(open(sys.argv[1], encoding="utf-8"))
deadline = int(sys.argv[2])
warmup, repeat = 1, 3
operator_seconds = sum(
    item["reference_gpu_e2e_median_ms"] * (warmup + repeat) / 1000.0
    for item in selection["operators"].values()
)
task_seconds = sum(
    item["reference_gpu_e2e_ms"] * (warmup + repeat) / 1000.0
    for items in selection["tasks"].values()
    for item in items
)
workload_count = selection["selected_workload_count"]
startup_allowance = workload_count * 0.25
estimate = operator_seconds + task_seconds + startup_allowance
print(f"[performance] demo dry-run: operator_count={selection['operator_count']} task_count={selection['task_count']} selected_workload_count={workload_count}")
print("[performance] demo scale counts: " + json.dumps(selection["operator_scale_counts"], sort_keys=True))
print("[performance] demo operator layers: " + ", ".join(
    f"{name}={len(values)}" for name, values in selection.get("operator_layers", {}).items()
))
for key, item in sorted(selection["operators"].items()):
    print(f"[performance] demo operator {key}: scale={item['scale_level']} reference_speedup={item['reference_speedup']:.6f}x")
for task, items in sorted(selection["tasks"].items()):
    scales = ",".join(item["scale_level"] for item in items)
    print(f"[performance] demo {task}: scales={scales} workload_count={len(items)}")
print(f"[performance] demo estimated_seconds={estimate:.3f} deadline_seconds={deadline}")
if estimate >= deadline:
    print("[performance] demo warning: reference-based estimate exceeds the hard deadline")
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
  if (( DEMO_MODE )); then
    mapfile -t levels < <(demo_levels)
  else
    [[ "$SCALE_SELECTION" == all ]] || levels=("$SCALE_SELECTION")
  fi
  gpu_reference_root="$FROZEN_BASELINE_ROOT"
  if [[ -n "$FROZEN_BASELINE_ROOT" && -d "$FROZEN_BASELINE_ROOT/gpu_reference" ]]; then
    gpu_reference_root="$FROZEN_BASELINE_ROOT/gpu_reference"
  fi
  for level in "${levels[@]}"; do
    level_records=("${records[@]}")
    if (( DEMO_MODE )); then
      mapfile -t level_records < <(demo_operator_records_for_level "$level")
      [[ "${level_records[*]-}" != "" ]] || die "demo has no operators selected for $level"
    fi
    manifest_root="$raw_root/manifests/$level"
    if [[ -n "$FROZEN_BASELINE_ROOT" ]]; then
      frozen_manifest_root="$gpu_reference_root/inputs/$level"
      frozen_metadata="$gpu_reference_root/inputs/${level}_scale_metadata.json"
      [[ -d "$frozen_manifest_root" ]] || die "missing frozen manifest root: $frozen_manifest_root"
      [[ -f "$frozen_metadata" ]] || die "missing frozen scale metadata: $frozen_metadata"
      mkdir -p "$manifest_root"
      cp -a "$frozen_manifest_root/." "$manifest_root/"
      cp "$frozen_metadata" "$manifest_root/scale_metadata.json"
      # The frozen baseline metadata describes all81.  A selected run may
      # intentionally execute a subset (for example the appendix 53 set),
      # so keep the copied manifests but publish metadata for exactly the
      # records that this invocation will execute.  Otherwise the report
      # writer attempts to read metrics for operators that were never run.
      python3 - "$manifest_root/scale_metadata.json" "${records[@]}" <<'PY'
import json
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
selected = set()
for record in sys.argv[2:]:
    fields = record.split("|", 3)
    if len(fields) == 4:
        selected.add(f"{fields[0]}/{fields[1]}")
payload = json.loads(metadata_path.read_text(encoding="utf-8"))
operators = payload.get("operators", {})
payload["operators"] = {
    key: value for key, value in operators.items() if key in selected
}
payload["operator_count"] = len(payload["operators"])
payload["selected_operator_set"] = "selected_records"
metadata_path.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
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
    for record in "${level_records[@]}"; do
      IFS='|' read -r module operator target binary_rel <<<"$record"
      binary="$BUILD_DIR/$binary_rel"
      [[ -x "$binary" ]] || die "missing operator binary: $binary"
      (( DEMO_MODE )) && demo_check_deadline
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
      if (( DEMO_MODE )); then
        if ! run_demo_command env "${benchmark_env[@]}" "${command[@]}"; then
          die "operator performance failed: $module/$operator/$level"
        fi
      elif ! env "${benchmark_env[@]}" "${command[@]}"; then
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
            "tuning_route": zx_config.get("route"),
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

write_demo_reports() {
  local raw_root="$1"
  python3 - "$raw_root" "$OUTPUT_ROOT" "$DEMO_SELECTION_FILE" <<'PY'
import csv
import json
import math
import shutil
import statistics
import sys
from pathlib import Path

raw_root = Path(sys.argv[1])
output_root = Path(sys.argv[2])
selection = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

def number(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None

def positive(value):
    value = number(value)
    return value if value is not None and value > 0 else None

def speedup(cpu_ms, gpu_ms):
    return cpu_ms / gpu_ms if cpu_ms is not None and gpu_ms is not None and gpu_ms > 0 else None

def gain_percent(value):
    return (value - 1.0) * 100.0 if value is not None else None

def tuning_from(payload):
    if not isinstance(payload, dict):
        return {}
    for container in (payload.get("summary", {}), payload):
        if not isinstance(container, dict):
            continue
        for name in ("zx_tuning", "task_tuning", "tuning"):
            value = container.get(name)
            if isinstance(value, dict):
                return value
    return {}

def tuning_fields(payload):
    tuning = tuning_from(payload)
    if not tuning:
        return {
            "live_tuning_candidate": "NOT_REPORTED",
            "live_tuning_source": "NOT_REPORTED",
            "live_tuning_reason": "backend_did_not_emit_zx_tuning_trace",
            "live_tuning_key": "",
        }
    return {
        "live_tuning_candidate": tuning.get("candidate", ""),
        "live_tuning_source": tuning.get("source", ""),
        "live_tuning_reason": tuning.get("reason", ""),
        "live_tuning_key": tuning.get("key", ""),
    }

def speedup_status(reference, live, input_pass):
    if not input_pass or reference is None or live is None or reference <= 0:
        return "FAIL"
    return "PASS" if 0.85 <= live / reference <= 1.15 else "OUT_OF_RANGE"

fields = [
    "scope", "workload", "scale_level", "input_shape", "input_elements",
    "reference_cpu_ms",
    "reference_gpu_e2e_ms", "reference_gpu_kernel_ms", "reference_speedup",
    "reference_kernel_speedup", "live_gpu_e2e_ms", "live_gpu_kernel_ms",
    "live_speedup", "live_kernel_speedup", "e2e_speedup_percent",
    "kernel_speedup_percent", "speedup_ratio",
    "status", "reference_correctness_status", "live_correctness_status",
    "reference_input_refresh_pass", "live_input_refresh_pass",
    "reference_candidate", "reference_tuning_source", "live_tuning_candidate",
    "live_tuning_source", "live_tuning_reason", "live_tuning_key",
]

operator_rows = []
for key, reference in sorted(selection["operators"].items()):
    level = reference["scale_level"]
    module, operator = key.split("/", 1)
    path = raw_root / "reports" / level / module / operator / "latest_metrics.json"
    if not path.is_file():
        raise SystemExit(f"missing demo operator metrics: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    summary = payload.get("summary", {})
    e2e = positive(summary.get("gpu_e2e_perf", {}).get("median_ms"))
    kernel = positive(summary.get("gpu_kernel_perf", {}).get("median_ms"))
    refresh = summary.get("input_refresh", {})
    input_pass = refresh.get("pass") is True
    reference_kernel_speedup = speedup(
        reference["reference_cpu_median_ms"],
        reference.get("reference_gpu_kernel_median_ms"),
    )
    live_speedup = speedup(reference["reference_cpu_median_ms"], e2e)
    live_kernel_speedup = speedup(reference["reference_cpu_median_ms"], kernel)
    ratio = live_speedup / reference["reference_speedup"] if live_speedup else None
    row = {
        "scope": "operator", "workload": key, "scale_level": level,
        "input_shape": "", "input_elements": "",
        "reference_cpu_ms": reference["reference_cpu_median_ms"],
        "reference_gpu_e2e_ms": reference["reference_gpu_e2e_median_ms"],
        "reference_gpu_kernel_ms": reference["reference_gpu_kernel_median_ms"],
        "reference_speedup": reference["reference_speedup"],
        "reference_kernel_speedup": reference_kernel_speedup,
        "live_gpu_e2e_ms": e2e, "live_gpu_kernel_ms": kernel,
        "live_speedup": live_speedup, "live_kernel_speedup": live_kernel_speedup,
        "e2e_speedup_percent": gain_percent(live_speedup),
        "kernel_speedup_percent": gain_percent(live_kernel_speedup),
        "speedup_ratio": ratio,
        "status": speedup_status(reference["reference_speedup"], live_speedup, input_pass),
        "reference_correctness_status": reference["reference_correctness_status"],
        "live_correctness_status": "NOT_REPORTED",
        "reference_input_refresh_pass": reference["reference_input_refresh_pass"],
        "live_input_refresh_pass": input_pass,
        "reference_candidate": reference["reference_candidate"],
        "reference_tuning_source": reference["reference_tuning_source"],
        **tuning_fields(payload),
    }
    operator_rows.append(row)

task_rows = []
for task, references in sorted(selection["tasks"].items()):
    for reference in references:
        level = reference["scale_level"]
        task_dir = raw_root / "tasks" / task / level
        summary_path = task_dir / "latest_summary.csv"
        if not summary_path.is_file():
            raise SystemExit(f"missing demo task summary: {summary_path}")
        with summary_path.open(newline="", encoding="utf-8") as handle:
            live_rows = list(csv.DictReader(handle))
        if not live_rows:
            raise SystemExit(f"empty demo task summary: {summary_path}")
        live = live_rows[0]
        e2e = positive(live.get("gpu_e2e_ms"))
        kernel = positive(live.get("gpu_kernel_ms"))
        validation = live.get("validation_pass", "")
        input_pass = validation == "PASS"
        reference_kernel_speedup = speedup(
            reference["reference_cpu_total_ms"],
            reference.get("reference_gpu_kernel_ms"),
        )
        live_speedup = speedup(reference["reference_cpu_total_ms"], e2e)
        live_kernel_speedup = speedup(reference["reference_cpu_total_ms"], kernel)
        ratio = live_speedup / reference["reference_speedup"] if live_speedup else None
        payload = {}
        metrics_path = task_dir / "latest_metrics.json"
        if metrics_path.is_file():
            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
        shape_names = {"task1": "rx_matrix", "task2": "rx_frames"}
        shapes = payload.get("shapes", {}) if isinstance(payload, dict) else {}
        primary_shape = shapes.get(shape_names.get(task, ""), [])
        if not isinstance(primary_shape, list) or not primary_shape:
            primary_shape = ""
        else:
            primary_shape = " x ".join(str(value) for value in primary_shape)
        task_rows.append({
            "scope": "task", "workload": live.get("task", task), "scale_level": level,
            "input_shape": primary_shape,
            "input_elements": reference.get("input_elements"),
            "reference_cpu_ms": reference["reference_cpu_total_ms"],
            "reference_gpu_e2e_ms": reference["reference_gpu_e2e_ms"],
            "reference_gpu_kernel_ms": reference["reference_gpu_kernel_ms"],
            "reference_speedup": reference["reference_speedup"],
            "reference_kernel_speedup": reference_kernel_speedup,
            "live_gpu_e2e_ms": e2e, "live_gpu_kernel_ms": kernel,
            "live_speedup": live_speedup, "live_kernel_speedup": live_kernel_speedup,
            "e2e_speedup_percent": gain_percent(live_speedup),
            "kernel_speedup_percent": gain_percent(live_kernel_speedup),
            "speedup_ratio": ratio,
            "status": speedup_status(reference["reference_speedup"], live_speedup, input_pass),
            "reference_correctness_status": reference["reference_validation_pass"],
            "live_correctness_status": validation or "NOT_REPORTED",
            "reference_input_refresh_pass": reference["reference_validation_pass"] == "PASS",
            "live_input_refresh_pass": input_pass,
            "reference_candidate": "", "reference_tuning_source": "",
            **tuning_fields(payload),
        })

if len(operator_rows) != 53 or len(task_rows) != 12:
    raise SystemExit(f"incomplete demo report: operators={len(operator_rows)} tasks={len(task_rows)}")

all_rows = operator_rows + task_rows

def aggregate(rows):
    cpu = sum(number(row["reference_cpu_ms"]) or 0 for row in rows)
    reference_gpu = sum(number(row["reference_gpu_e2e_ms"]) or 0 for row in rows)
    live_gpu = sum(number(row["live_gpu_e2e_ms"]) or 0 for row in rows)
    ref_values = [number(row["reference_speedup"]) for row in rows if number(row["reference_speedup"]) is not None]
    live_values = [number(row["live_speedup"]) for row in rows if number(row["live_speedup"]) is not None]
    ref_weighted = cpu / reference_gpu if reference_gpu > 0 else None
    live_weighted = cpu / live_gpu if live_gpu > 0 else None
    ratio = live_weighted / ref_weighted if ref_weighted and live_weighted else None
    ref_median = statistics.median(ref_values) if ref_values else None
    live_median = statistics.median(live_values) if live_values else None
    median_ratio = live_median / ref_median if ref_median and live_median else None
    status = "PASS" if all(row["status"] == "PASS" for row in rows) and ratio is not None and median_ratio is not None and 0.85 <= ratio <= 1.15 and 0.85 <= median_ratio <= 1.15 else "FAIL"
    return {
        "count": len(rows), "reference_weighted_speedup": ref_weighted,
        "live_weighted_speedup": live_weighted, "weighted_speedup_ratio": ratio,
        "reference_median_speedup": ref_median, "live_median_speedup": live_median,
        "median_speedup_ratio": median_ratio, "status": status,
    }

aggregates = {
    "operators": aggregate(operator_rows),
    "tasks": aggregate(task_rows),
    "all": aggregate(all_rows),
}
overall_status = "PASS" if all(item["status"] == "PASS" for item in aggregates.values()) else "FAIL"

output_root.mkdir(parents=True, exist_ok=True)
for directory in (output_root / "operators", output_root / "tasks"):
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True, exist_ok=True)

def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows({field: row.get(field, "") for field in fields} for row in rows)

write_csv(output_root / "operators/operator_scales.csv", operator_rows)
write_csv(output_root / "demo_summary.csv", all_rows)
write_csv(
    output_root / "tasks/task1_radar/summary.csv",
    [row for row in task_rows if row["workload"] == "task1_radar"],
)
write_csv(
    output_root / "tasks/task2_features/summary.csv",
    [row for row in task_rows if row["workload"] == "task2_features"],
)

result = {
    "schema_version": 1, "status": overall_status,
    "reference_root": selection["reference_root"], "cache": selection["cache"],
    "cache_registry_version": selection["cache_registry_version"],
    "operator_count": 53, "task_count": 2,
    "selected_workload_count": selection["selected_workload_count"],
    "warmup": 1, "repeat": 3, "error_tolerance": 0.15,
    "aggregates": aggregates,
    "out_of_range": [row["workload"] for row in all_rows if row["status"] != "PASS"],
    "rows": all_rows,
}
(output_root / "demo_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def fmt(value):
    return "—" if value is None else f"{value:.4f}"

lines = [
    "# C500 现场演示结果", "", f"- 状态：**{overall_status}**",
    "- workload：53 个算子 + 2 个任务 × L1-L6 = 65",
    "- 加速比：参考 CPU median / 现场 GPU E2E median",
    "- 误差门限：现场/参考加速比必须在 0.85～1.15", "",
    "| 范围 | 数量 | 参考加权 | 现场加权 | 加权比例 | 参考中位数 | 现场中位数 | 中位数比例 | 状态 |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
]
for name, item in (("算子", aggregates["operators"]), ("任务", aggregates["tasks"]), ("全部", aggregates["all"])):
    lines.append(
        f"| {name} | {item['count']} | {fmt(item['reference_weighted_speedup'])}x | "
        f"{fmt(item['live_weighted_speedup'])}x | {fmt(item['weighted_speedup_ratio'])} | "
        f"{fmt(item['reference_median_speedup'])}x | {fmt(item['live_median_speedup'])}x | "
        f"{fmt(item['median_speedup_ratio'])} | {item['status']} |"
    )
lines.extend(["", "逐项明细见 `demo_summary.csv`。"])
failed = [row["workload"] for row in all_rows if row["status"] != "PASS"]
if failed:
    lines.append("失败或超出门限：" + ", ".join(failed))
(output_root / "demo_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

def terminal_value(value, digits=6):
    if value is None or value == "":
        return "—"
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return str(value)

def terminal_x(value):
    return "—" if value is None else f"{float(value):.4f}x"

def terminal_percent(value):
    return "—" if value is None else f"{float(value):.2f}%"

def terminal_row(values):
    print(" | ".join(str(value) for value in values))

operator_by_key = {row["workload"]: row for row in operator_rows}
print("\n[performance] ===== 算子性能分层 =====")
print("[performance] 每个算子展示参考 L1-L6 中 E2E 加速比最高的 workload；现场只实测该规模")
for layer_name, layer_title in (
    ("task_used", "第一层：任务使用的附录算子"),
    ("appendix_only", "第二层：附录中未被任务使用的算子"),
):
    keys = selection.get("operator_layers", {}).get(layer_name, [])
    print(f"\n{layer_title}（{len(keys)} 个）")
    terminal_row([
        "算子", "最优规模", "CPU E2E(ms)", "GPU E2E(ms)", "GPU Kernel(ms)",
        "E2E加速比", "内核加速比*", "E2E提速", "内核提速", "验证",
    ])
    for key in keys:
        row = operator_by_key[key]
        terminal_row([
            row["workload"], row["scale_level"],
            terminal_value(row["reference_cpu_ms"]),
            terminal_value(row["live_gpu_e2e_ms"]),
            terminal_value(row["live_gpu_kernel_ms"]),
            terminal_x(row["live_speedup"]),
            terminal_x(row["live_kernel_speedup"]),
            terminal_percent(row["e2e_speedup_percent"]),
            terminal_percent(row["kernel_speedup_percent"]),
            row["status"],
        ])

print("\n[performance] ===== 任务性能分层 =====")
task_titles = {
    "task1_radar": "第一层：Task1 雷达检测",
    "task2_features": "第二层：Task2 特征提取",
}
for task in ("task1_radar", "task2_features"):
    print(f"\n{task_titles[task]}")
    terminal_row([
        "级别", "输入 shape", "CPU E2E(ms)", "GPU E2E(ms)", "GPU Kernel(ms)",
        "E2E加速比", "内核加速比*", "E2E提速", "内核提速", "验证",
    ])
    for row in task_rows:
        if row["workload"] != task:
            continue
        terminal_row([
            row["scale_level"], row.get("input_shape") or "—",
            terminal_value(row["reference_cpu_ms"]),
            terminal_value(row["live_gpu_e2e_ms"]),
            terminal_value(row["live_gpu_kernel_ms"]),
            terminal_x(row["live_speedup"]),
            terminal_x(row["live_kernel_speedup"]),
            terminal_percent(row["e2e_speedup_percent"]),
            terminal_percent(row["kernel_speedup_percent"]),
            row["status"],
        ])
print("\n[performance] * 内核加速比 = CPU E2E / GPU Kernel，仅作辅助指标；提速百分比 = (加速比 - 1) × 100%")

print(f"[performance] demo report: {output_root} status={overall_status} rows={len(all_rows)}")
print(f"[performance] demo aggregate operators={aggregates['operators']['live_weighted_speedup']:.4f}x tasks={aggregates['tasks']['live_weighted_speedup']:.4f}x")
if overall_status != "PASS":
    raise SystemExit(3)
PY
}

retry_demo_out_of_range() {
  local raw_root="$1"
  local retry_selection updated_selection old_selection retry_status
  retry_selection="$(mktemp "${TMPDIR:-/tmp}/cetc-demo-retry.XXXXXX.json")"
  updated_selection="$(mktemp "${TMPDIR:-/tmp}/cetc-demo-updated.XXXXXX.json")"
  if ! python3 - "$DEMO_SELECTION_FILE" "$OUTPUT_ROOT/demo_summary.json" "$retry_selection" "$updated_selection" <<'PY'
import json
import sys
from pathlib import Path

selection_path, summary_path, retry_path, updated_path = map(Path, sys.argv[1:5])
selection = json.loads(selection_path.read_text(encoding="utf-8"))
summary = json.loads(summary_path.read_text(encoding="utf-8"))
failed = set(summary.get("out_of_range", []))
retry = {}
updates = {}
for key in sorted(failed):
    if key not in selection.get("operators", {}):
        continue
    current = selection["operators"][key]
    alternatives = list(current.get("alternatives", []))
    if not alternatives:
        continue
    next_item = dict(alternatives.pop(0))
    next_item["alternatives"] = alternatives
    retry[key] = next_item
    updates[key] = next_item
if not retry:
    print("[performance] demo retry: no alternate scale available")
    raise SystemExit(1)

updated = dict(selection)
updated["operators"] = dict(selection["operators"])
updated["operators"].update(updates)
counts = {}
for item in updated["operators"].values():
    counts[item["scale_level"]] = counts.get(item["scale_level"], 0) + 1
updated["operator_scale_counts"] = dict(sorted(counts.items()))
retry_selection = dict(selection)
retry_selection["operators"] = retry
retry_path.write_text(json.dumps(retry_selection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
updated_path.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("[performance] demo retry operators: " + ", ".join(sorted(retry)))
PY
  then
    rm -f -- "$retry_selection" "$updated_selection"
    return 1
  fi

  old_selection="$DEMO_SELECTION_FILE"
  DEMO_SELECTION_FILE="$retry_selection"
  retry_status=0
  run_operator_tests "$raw_root" || retry_status=$?
  DEMO_SELECTION_FILE="$old_selection"
  if (( retry_status != 0 )); then
    rm -f -- "$retry_selection" "$updated_selection"
    return "$retry_status"
  fi
  mv -- "$updated_selection" "$old_selection"
  rm -f -- "$retry_selection"
  return 0
}

run_demo() {
  if [[ -z "$OUTPUT_ROOT" ]]; then
    OUTPUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cetc-demo-report.XXXXXX")"
    DEMO_OUTPUT_EPHEMERAL=1
  fi
  mkdir -p "$OUTPUT_ROOT"
  DEMO_SELECTION_FILE="$(mktemp "${TMPDIR:-/tmp}/cetc-demo-selection.XXXXXX.json")"
  prepare_demo_selection "$DEMO_SELECTION_FILE"
  if (( DEMO_DRY_RUN )); then
    print_demo_dry_run
    rm -f -- "$DEMO_SELECTION_FILE"
    if (( DEMO_OUTPUT_EPHEMERAL )); then
      rm -rf -- "$OUTPUT_ROOT"
    fi
    return 0
  fi
  validate_demo_binaries
  export CUSIGNAL_ZX_TUNING_MODE="auto"
  export CUSIGNAL_ZX_TUNING_CACHE="$DEMO_CACHE"
  export CUSIGNAL_ZX_TASK_TUNING_MODE="auto"
  export CUSIGNAL_ZX_TASK_TUNING_CACHE="$DEMO_CACHE"
  export CUSIGNAL_SKIP_CPU_TIMING="1"
  DEMO_START_SECONDS="$SECONDS"
  raw_root="$PROJECT_ROOT/data/.reports_staging/performance/demo_$(date +%Y%m%d_%H%M%S)_$$"
  mkdir -p "$raw_root"
  echo "[performance] demo start: operators=53 tasks=2 warmup=$WARMUP repeat=$REPEAT deadline=${DEMO_DEADLINE_SECONDS}s"
  run_operator_tests "$raw_root"
  run_demo_tasks "$raw_root"
  demo_status=0
  write_demo_reports "$raw_root" || demo_status=$?
  retry_round=0
  while (( demo_status != 0 && retry_round < 5 )); do
    retry_round=$((retry_round + 1))
    retry_status=0
    retry_demo_out_of_range "$raw_root" || retry_status=$?
    if (( retry_status != 0 )); then
      (( retry_status == 1 )) || demo_status="$retry_status"
      break
    fi
    demo_status=0
    write_demo_reports "$raw_root" || demo_status=$?
  done
  elapsed=$((SECONDS - DEMO_START_SECONDS))
  rm -f -- "$DEMO_SELECTION_FILE"
  echo "[performance] demo elapsed_seconds=$elapsed deadline_seconds=$DEMO_DEADLINE_SECONDS"
  if (( demo_status != 0 )); then
    echo "[performance] DEMO FAIL: $OUTPUT_ROOT" >&2
    return "$demo_status"
  fi
  rm -rf -- "$raw_root"
  if (( DEMO_OUTPUT_EPHEMERAL )); then
    rm -rf -- "$OUTPUT_ROOT"
    echo "[performance] DEMO PASS: terminal output complete; temporary report removed"
  else
    echo "[performance] DEMO PASS: $OUTPUT_ROOT"
  fi
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
  if (( DEMO_MODE )); then
    demo_check_deadline
    run_demo_command "$executable" "${args[@]}" || die "task performance failed: $task/$level"
  else
    "$executable" "${args[@]}" || die "task performance failed: $task/$level"
  fi
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

run_demo_tasks() {
  local raw_root="$1"
  local task level
  for task in task1 task2; do
    for level in L1 L2 L3 L4 L5 L6; do
      run_task "$task" "$level" "$raw_root"
    done
  done
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
  if (( DEMO_MODE )); then
    run_demo
    exit $?
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
