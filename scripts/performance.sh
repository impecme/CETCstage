#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(\cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(\cd "$SCRIPT_DIR/.." && pwd)"
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
CASE_SET="perf"
SKIP_TIMING_VALIDATION=0
VERBOSE=0
OUTPUT_ROOT=""
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
  --no-build               Reuse existing binaries
  --output-root PATH       Result directory (default: data/reports)
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
      --case-set)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        CASE_SET="$2"; shift 2 ;;
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
  case "$CASE_SET" in perf|smoke) ;; *) die "unsupported case set: $CASE_SET" ;; esac
  [[ "$WARMUP" =~ ^[0-9]+$ ]] || die "--warmup must be a non-negative integer"
  [[ "$REPEAT" =~ ^[1-9][0-9]*$ ]] || die "--repeat must be a positive integer"
  [[ -z "$JOBS" || "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
  if [[ "$CASE_SET" == smoke ]]; then WARMUP=0; REPEAT=1; SCALE_SELECTION=L3; else (( REPEAT >= 3 )) || die "performance repeat must be >= 3"; fi
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
  for level in "${levels[@]}"; do
    manifest_root="$raw_root/manifests/$level"
    prepare_operator_inputs "$manifest_root" "$level"
    rm -rf -- "$PROJECT_ROOT/data/.reports_staging/unit"
    echo "[performance] operators $level: $OPERATOR_SET"
    for record in "${records[@]}"; do
      IFS='|' read -r module operator target binary_rel <<<"$record"
      binary="$BUILD_DIR/$binary_rel"
      [[ -x "$binary" ]] || die "missing operator binary: $binary"
      command=("$binary" --case-set perf --warmup "$WARMUP" --repeat "$REPEAT" --emit-report)
      (( VERBOSE )) && command+=(--verbose)
      echo "[performance] operator $module/$operator"
      # Formal operator E2E timing must upload the host input on every measured
      # iteration. Workspace/allocation caches remain enabled, while backend
      # value caches are bypassed by this benchmark-only switch.
      if ! CUSIGNAL_GENERATED_UNIT_ROOT="$manifest_root" \
           CUSIGNAL_PERF_FRESH_INPUT=1 "${command[@]}"; then
        die "operator performance failed: $module/$operator/$level"
      fi
      source_metrics="$PROJECT_ROOT/data/.reports_staging/unit/$module/$operator/latest_metrics.json"
      [[ -f "$source_metrics" ]] || die "missing operator report: $source_metrics"
      mkdir -p "$raw_root/reports/$level/$module/$operator"
      cp "$source_metrics" "$raw_root/reports/$level/$module/$operator/latest_metrics.json"
    done
    cp "$manifest_root/scale_metadata.json" "$raw_root/reports/$level/scale_metadata.json"
  done
}

write_operator_report() {
  raw_root="$1"
  python3 - "$raw_root/reports" "$OUTPUT_ROOT/units/benchmarks" "$OPERATOR_SET" "$SCALE_SELECTION" "$WARMUP" "$REPEAT" <<'PY'
import csv
import json
import math
import sys
from pathlib import Path

raw_root, output_root = Path(sys.argv[1]), Path(sys.argv[2])
operator_set, selection = sys.argv[3:5]
warmup_runs, measured_repeat_runs = map(int, sys.argv[5:7])
levels = [f"L{n}" for n in range(1, 7)] if selection == "all" else [selection]
rows = []
for level in levels:
    metadata = json.loads((raw_root / level / "scale_metadata.json").read_text(encoding="utf-8"))["operators"]
    for key, item in metadata.items():
        module, operator = key.split("/", 1)
        payload = json.loads((raw_root / level / module / operator / "latest_metrics.json").read_text(encoding="utf-8"))
        summary = payload.get("summary", {})
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
        cpu, e2e = timing("cpu_perf"), timing("gpu_e2e_perf")
        kernel = timing("gpu_kernel_perf", allow_missing=True)
        if kernel is not None and kernel <= 0:
            kernel = None
        if cpu is None or e2e is None or cpu <= 0 or e2e <= 0:
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
            "cpu_median_ms": cpu,
            "gpu_e2e_median_ms": e2e,
            "gpu_kernel_median_ms": kernel,
            "gpu_e2e_speedup": cpu / e2e,
            "gpu_kernel_speedup": cpu / kernel if kernel and kernel > 0.0 else None,
            "gpu_acceleration_eligible": summary.get("gpu_acceleration_eligible"),
            "path_kind": summary.get("path_kind"),
            "input_kind": summary.get("input_kind"),
            # Unit tests do not claim a stage split unless the backend reports
            # one explicitly.  Missing stages remain null/blank rather than
            # being inferred from the E2E number.
            "host_input_ms": optional_stage_timing("host_input_perf"),
            "h2d_ms": optional_stage_timing("h2d_perf"),
            "gpu_compute_ms": optional_stage_timing("gpu_compute_perf"),
            "d2h_ms": optional_stage_timing("d2h_perf"),
            "host_output_ms": optional_stage_timing("host_output_perf"),
            "status": "PASS",
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
    actual_operators = len({row["operator"] for row in rows})
    expected_rows = expected_operators * len(levels)
    if actual_operators != expected_operators or len(rows) != expected_rows:
        raise RuntimeError(
            f"incomplete operator report for {operator_set}: "
            f"operators={actual_operators}/{expected_operators} rows={len(rows)}/{expected_rows}"
        )
output_root.mkdir(parents=True, exist_ok=True)
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
    "schema_version": 1,
    "operator_set": operator_set,
    "operator_count": len({row["operator"] for row in rows}),
    "scale_levels": levels,
    "warmup": warmup_runs,
    "repeat": measured_repeat_runs,
    "rows": rows,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
lines = [
    "# 算子性能汇总", "",
    "- 算子集合：" + operator_set,
    "- 规模：" + ", ".join(levels),
    f"- 计时：warmup={warmup_runs}，repeat={measured_repeat_runs}，正式结果取中位数", "",
    "| 算子 | 规模 | warmup | repeat | CPU median ms | GPU E2E median ms | GPU kernel median ms | E2E 加速比 | kernel 加速比 |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
]
for row in rows:
    kernel = "—" if row["gpu_kernel_median_ms"] is None else f"{row['gpu_kernel_median_ms']:.6f}"
    kernel_speedup = "—/不适用" if row["gpu_kernel_speedup"] is None else f"{row['gpu_kernel_speedup']:.3f}x"
    lines.append("| {operator} | {scale} | {warmup} | {repeat} | {cpu:.6f} | {e2e:.6f} | {kernel} | {es:.3f}x | {ks} |".format(
        operator=row["operator"], scale=row["scale_level"], cpu=row["cpu_median_ms"],
        warmup=row["warmup"], repeat=row["repeat"],
        e2e=row["gpu_e2e_median_ms"], kernel=kernel,
        es=row["gpu_e2e_speedup"], ks=kernel_speedup))
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
    OUTPUT_ROOT="$PROJECT_ROOT/data/reports"
  fi
  mkdir -p "$OUTPUT_ROOT"
  raw_root="$PROJECT_ROOT/data/.reports_staging/performance/run_$(date +%Y%m%d_%H%M%S)_$$"
  mkdir -p "$raw_root"
  build_selected
  if (( RUN_OPERATORS )); then
    run_operator_tests "$raw_root"
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
