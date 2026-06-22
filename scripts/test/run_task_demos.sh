#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build-zx"
DO_BUILD=1
REPEAT=5
LEAK_CHECK=0
SCALE_SWEEP=0
SCALES="1,2,3,4,5,6"
REQUIRE_VISUALIZATION_DEPS=0
SKIP_TIMING_VALIDATION=0

usage() {
  cat <<'USAGE'
Usage: scripts/test/run_task_demos.sh [options]

Options:
  --build-dir DIR       Build directory (default: build-zx)
  --build               Build task demo targets before running (default)
  --no-build            Skip build
  --repeat N            Repeat count passed to each demo (default: 5)
  --scale-sweep         Run Task1/Task2 across scale levels and write scale reports
  --scales LIST         Comma-separated scale levels for --scale-sweep (default: 1,2,3,4,5,6)
  --leak-check          Also run compute-sanitizer memcheck when available
  --require-visualization-deps
                        Fail instead of skipping when numpy/matplotlib/scipy are missing
  --skip-timing-validation
                        Keep timing metrics but skip task timing pass/fail gates
  -h, --help            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --build)
      DO_BUILD=1
      shift
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --repeat)
      REPEAT="$2"
      shift 2
      ;;
    --scale-sweep)
      SCALE_SWEEP=1
      shift
      ;;
    --scales)
      SCALES="$2"
      shift 2
      ;;
    --leak-check)
      LEAK_CHECK=1
      shift
      ;;
    --require-visualization-deps)
      REQUIRE_VISUALIZATION_DEPS=1
      shift
      ;;
    --skip-timing-validation)
      SKIP_TIMING_VALIDATION=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[task-demos] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "${REPEAT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "[task-demos] --repeat must be a positive integer" >&2
  exit 2
fi

IFS=',' read -r -a SCALE_ITEMS <<<"${SCALES}"
for scale in "${SCALE_ITEMS[@]}"; do
  if ! [[ "${scale}" =~ ^[1-6]$ ]]; then
    echo "[task-demos] --scales must contain only levels 1..6: ${SCALES}" >&2
    exit 2
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

if [[ "${BUILD_DIR}" = /* ]]; then
  BUILD_PATH="${BUILD_DIR}"
else
  BUILD_PATH="${REPO_ROOT}/${BUILD_DIR}"
fi
REPORT_ROOT="${REPO_ROOT}/data/reports/demo"
GENERATED_ROOT="${REPO_ROOT}/data/generated/demo"
LEAK_ROOT="${REPORT_ROOT}/leak_check"

mkdir -p "${REPORT_ROOT}" "${LEAK_ROOT}"

if [[ "${DO_BUILD}" -eq 1 ]]; then
  if ! command -v dlcc >/dev/null 2>&1 && [[ -f /zq500/sdk/env.sh ]]; then
    set +u
    # shellcheck source=/dev/null
    source /zq500/sdk/env.sh
    set -u
  fi
  ZHONGKEXIN_CXX="${ZHONGKEXIN_CXX_COMPILER:-$(command -v dlcc || true)}"
  if [[ -z "${ZHONGKEXIN_CXX}" ]]; then
    echo "[task-demos] error: dlcc was not found for ZHONGKEXIN build" >&2
    exit 2
  fi
  echo "[task-demos] configuring ${BUILD_PATH} with ${ZHONGKEXIN_CXX}"
  cmake -S "${REPO_ROOT}" -B "${BUILD_PATH}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
    -DCMAKE_CXX_COMPILER="${ZHONGKEXIN_CXX}"
  cmake --build "${BUILD_PATH}" --target task1_radar_demo task2_features_demo --parallel
fi

TASK1_EXE="${BUILD_PATH}/demo/task1_radar/task1_radar_demo"
TASK2_EXE="${BUILD_PATH}/demo/task2_features/task2_features_demo"
VISUALIZATION_DEPS_STATUS="unknown"

has_visualization_deps() {
  python3 - <<'PY' >/dev/null 2>&1
import matplotlib
import numpy
import scipy
PY
}

run_visualization() {
  local name="$1"
  local viz="$2"
  if [[ "${VISUALIZATION_DEPS_STATUS}" == "unknown" ]]; then
    if has_visualization_deps; then
      VISUALIZATION_DEPS_STATUS="available"
    else
      VISUALIZATION_DEPS_STATUS="missing"
    fi
  fi

  if [[ "${VISUALIZATION_DEPS_STATUS}" == "missing" ]]; then
    if [[ "${REQUIRE_VISUALIZATION_DEPS}" -eq 1 ]]; then
      echo "[task-demos] error: ${name} visualization requires python numpy/matplotlib/scipy" >&2
      exit 2
    fi
    echo "[task-demos] skipping ${name} visualization: python numpy/matplotlib/scipy not available"
    return
  fi

  echo "[task-demos] visualizing ${name}: ${viz}"
  python3 "${viz}"
  if [[ "${REQUIRE_VISUALIZATION_DEPS}" -eq 1 ]]; then
    local figure_dir="${REPORT_ROOT}/${name}/figures"
    if ! compgen -G "${figure_dir}/*.png" >/dev/null || [[ ! -f "${figure_dir}/README.md" ]]; then
      echo "[task-demos] error: ${name} visualization did not produce expected figures under ${figure_dir}" >&2
      exit 2
    fi
  fi
}

run_demo() {
  local name="$1"
  local exe="$2"
  local viz="$3"
  local scale_level="${4:-}"
  local args=(--repeat "${REPEAT}" --invalid-input-checks)
  if [[ "${SKIP_TIMING_VALIDATION}" -eq 1 ]]; then
    args+=(--skip-timing-validation)
  fi
  if [[ -n "${scale_level}" ]]; then
    args+=(--scale-level "${scale_level}")
  fi
  echo "[task-demos] running ${name}: ${exe} ${args[*]}"
  "${exe}" "${args[@]}"
  run_visualization "${name}" "${viz}"
}

run_scale_case() {
  local name="$1"
  local exe="$2"
  local scale_level="$3"
  local args=(--repeat "${REPEAT}" --scale-level "${scale_level}" --invalid-input-checks)
  if [[ "${SKIP_TIMING_VALIDATION}" -eq 1 ]]; then
    args+=(--skip-timing-validation)
  fi
  local scale_dir="${REPORT_ROOT}/${name}/scales/L${scale_level}"
  echo "[task-demos] scale L${scale_level} ${name}: ${exe} ${args[*]}"
  "${exe}" "${args[@]}"
  mkdir -p "${scale_dir}"
  cp "${REPORT_ROOT}/${name}/latest_metrics.json" "${scale_dir}/latest_metrics.json"
  cp "${REPORT_ROOT}/${name}/latest_summary.md" "${scale_dir}/latest_summary.md"
  cp "${REPORT_ROOT}/${name}/latest_stage_timings.csv" "${scale_dir}/latest_stage_timings.csv"
  cp "${REPORT_ROOT}/${name}/latest_step_metrics.csv" "${scale_dir}/latest_step_metrics.csv"
  cp "${REPORT_ROOT}/${name}/latest_step_metrics.json" "${scale_dir}/latest_step_metrics.json"
  cp "${REPORT_ROOT}/${name}/latest_step_metrics.md" "${scale_dir}/latest_step_metrics.md"
  if [[ -f "${GENERATED_ROOT}/${name}/input/scenario.json" ]]; then
    cp "${GENERATED_ROOT}/${name}/input/scenario.json" "${scale_dir}/input_scenario.json"
  fi
}

if [[ "${SCALE_SWEEP}" -eq 1 ]]; then
  for scale in "${SCALE_ITEMS[@]}"; do
    run_scale_case "task1_radar" "${TASK1_EXE}" "${scale}"
    run_scale_case "task2_features" "${TASK2_EXE}" "${scale}"
  done
  run_demo "task1_radar" "${TASK1_EXE}" "${REPO_ROOT}/demo/task1_radar/visualize_task1.py" 3
  run_demo "task2_features" "${TASK2_EXE}" "${REPO_ROOT}/demo/task2_features/visualize_task2.py" 3
else
  run_demo "task1_radar" "${TASK1_EXE}" "${REPO_ROOT}/demo/task1_radar/visualize_task1.py"
  run_demo "task2_features" "${TASK2_EXE}" "${REPO_ROOT}/demo/task2_features/visualize_task2.py"
fi

COMPUTE_SANITIZER_STATUS="not_requested"
ASAN_STATUS="not_requested"
if [[ "${LEAK_CHECK}" -eq 1 ]]; then
  ASAN_STATUS="skipped"
  cp "${REPORT_ROOT}/task1_radar/latest_metrics.json" "${LEAK_ROOT}/task1_radar_latest_metrics.normal.json"
  cp "${REPORT_ROOT}/task1_radar/latest_summary.md" "${LEAK_ROOT}/task1_radar_latest_summary.normal.md"
  cp "${REPORT_ROOT}/task1_radar/latest_stage_timings.csv" "${LEAK_ROOT}/task1_radar_latest_stage_timings.normal.csv"
  cp "${REPORT_ROOT}/task1_radar/latest_step_metrics.csv" "${LEAK_ROOT}/task1_radar_latest_step_metrics.normal.csv"
  cp "${REPORT_ROOT}/task1_radar/latest_step_metrics.json" "${LEAK_ROOT}/task1_radar_latest_step_metrics.normal.json"
  cp "${REPORT_ROOT}/task2_features/latest_metrics.json" "${LEAK_ROOT}/task2_features_latest_metrics.normal.json"
  cp "${REPORT_ROOT}/task2_features/latest_summary.md" "${LEAK_ROOT}/task2_features_latest_summary.normal.md"
  cp "${REPORT_ROOT}/task2_features/latest_stage_timings.csv" "${LEAK_ROOT}/task2_features_latest_stage_timings.normal.csv"
  cp "${REPORT_ROOT}/task2_features/latest_step_metrics.csv" "${LEAK_ROOT}/task2_features_latest_step_metrics.normal.csv"
  cp "${REPORT_ROOT}/task2_features/latest_step_metrics.json" "${LEAK_ROOT}/task2_features_latest_step_metrics.normal.json"
  if command -v compute-sanitizer >/dev/null 2>&1; then
    COMPUTE_SANITIZER_STATUS="passed"
    for item in "task1_radar:${TASK1_EXE}" "task2_features:${TASK2_EXE}"; do
      name="${item%%:*}"
      exe="${item#*:}"
      log_path="${LEAK_ROOT}/${name}_compute_sanitizer.log"
      echo "[task-demos] compute-sanitizer ${name} -> ${log_path}"
      if ! compute-sanitizer --tool memcheck "${exe}" --repeat 1 --scale-level 3 --invalid-input-checks --skip-timing-validation >"${log_path}" 2>&1; then
        COMPUTE_SANITIZER_STATUS="failed"
      fi
    done
  else
    COMPUTE_SANITIZER_STATUS="skipped"
  fi
  cp "${LEAK_ROOT}/task1_radar_latest_metrics.normal.json" "${REPORT_ROOT}/task1_radar/latest_metrics.json"
  cp "${LEAK_ROOT}/task1_radar_latest_summary.normal.md" "${REPORT_ROOT}/task1_radar/latest_summary.md"
  cp "${LEAK_ROOT}/task1_radar_latest_stage_timings.normal.csv" "${REPORT_ROOT}/task1_radar/latest_stage_timings.csv"
  cp "${LEAK_ROOT}/task1_radar_latest_step_metrics.normal.csv" "${REPORT_ROOT}/task1_radar/latest_step_metrics.csv"
  cp "${LEAK_ROOT}/task1_radar_latest_step_metrics.normal.json" "${REPORT_ROOT}/task1_radar/latest_step_metrics.json"
  cp "${LEAK_ROOT}/task2_features_latest_metrics.normal.json" "${REPORT_ROOT}/task2_features/latest_metrics.json"
  cp "${LEAK_ROOT}/task2_features_latest_summary.normal.md" "${REPORT_ROOT}/task2_features/latest_summary.md"
  cp "${LEAK_ROOT}/task2_features_latest_stage_timings.normal.csv" "${REPORT_ROOT}/task2_features/latest_stage_timings.csv"
  cp "${LEAK_ROOT}/task2_features_latest_step_metrics.normal.csv" "${REPORT_ROOT}/task2_features/latest_step_metrics.csv"
  cp "${LEAK_ROOT}/task2_features_latest_step_metrics.normal.json" "${REPORT_ROOT}/task2_features/latest_step_metrics.json"
fi

TASK_DEMO_REPEAT="${REPEAT}" \
TASK_DEMO_LEAK_CHECK="${LEAK_CHECK}" \
TASK_DEMO_SCALE_SWEEP="${SCALE_SWEEP}" \
TASK_DEMO_SCALES="${SCALES}" \
TASK_DEMO_COMPUTE_SANITIZER_STATUS="${COMPUTE_SANITIZER_STATUS}" \
TASK_DEMO_ASAN_STATUS="${ASAN_STATUS}" \
TASK_DEMO_VISUALIZATION_STATUS="${VISUALIZATION_DEPS_STATUS}" \
python3 - <<'PY'
import csv
import json
import math
import os
from pathlib import Path

repo = Path.cwd()
report_root = repo / "data" / "reports" / "demo"

def f(value, default=0.0):
    try:
        number = float(value)
    except Exception:
        return default
    return number if math.isfinite(number) else default

def median(values):
    values = sorted(f(value) for value in values if math.isfinite(f(value)))
    if not values:
        return 0.0
    mid = len(values) // 2
    if len(values) % 2:
        return values[mid]
    return 0.5 * (values[mid - 1] + values[mid])

def rel(path):
    return str(path.relative_to(repo))

def check_value(validation, name):
    for check in validation.get("checks", []):
        if check.get("name") == name:
            return f(check.get("value"))
    return 0.0

def errors_from(data):
    return {
        key: value
        for key, value in data.items()
        if key.endswith("_error") and isinstance(value, dict)
    }

def max_mixed_error(data):
    return max((f(value.get("mixed_error")) for value in errors_from(data).values()), default=0.0)

def total_medians(data):
    runs = data.get("repeat_runs", [])
    cpu_values = [run.get("cpu_total_ms") for run in runs if isinstance(run, dict)]
    gpu_values = [run.get("gpu_total_ms") for run in runs if isinstance(run, dict)]
    if not cpu_values or not gpu_values:
        total = data.get("timings", {}).get("total", {})
        return f(total.get("cpu_ms")), f(total.get("gpu_ms"))
    return median(cpu_values), median(gpu_values)

def task_summary(name):
    metrics_path = report_root / name / "latest_metrics.json"
    summary_path = report_root / name / "latest_summary.md"
    data = json.loads(metrics_path.read_text())
    validation = data.get("validation", {})
    failed = [c for c in validation.get("checks", []) if not c.get("pass")]
    cpu_ms, gpu_ms = total_medians(data)
    scenario = data.get("scenario", {})
    return {
        "name": name,
        "scale_level": int(scenario.get("scale_level", 3)),
        "scale_value": int(scenario.get("scale_value", 0)),
        "metrics_path": rel(metrics_path),
        "summary_path": rel(summary_path),
        "validation_pass": bool(validation.get("pass")),
        "failed_checks": failed,
        "cpu_total_ms": cpu_ms,
        "gpu_total_ms": gpu_ms,
        "speedup": cpu_ms / gpu_ms if gpu_ms > 0 else 0.0,
        "max_mixed_error": max_mixed_error(data),
        "resource_usage": data.get("resource_usage", {}),
        "repeat_runs": data.get("repeat_runs", []),
    }

def scale_row(name, scale):
    scale_dir = report_root / name / "scales" / f"L{scale}"
    metrics_path = scale_dir / "latest_metrics.json"
    summary_path = scale_dir / "latest_summary.md"
    timings_path = scale_dir / "latest_stage_timings.csv"
    data = json.loads(metrics_path.read_text())
    scenario = data.get("scenario", {})
    validation = data.get("validation", {})
    cpu_ms, gpu_ms = total_medians(data)
    primary = scenario.get("num_pulses", scenario.get("num_frames", ""))
    samples = scenario.get("samples_per_pulse", scenario.get("samples_per_frame", ""))
    return {
        "task": name,
        "scale_level": int(scenario.get("scale_level", scale)),
        "scale_value": int(scenario.get("scale_value", 0)),
        "primary_dim": primary,
        "samples": samples,
        "template_length": scenario.get("template_length", ""),
        "repeat": int(os.environ.get("TASK_DEMO_REPEAT", "0")),
        "validation_pass": bool(validation.get("pass")),
        "cpu_median_total_ms": cpu_ms,
        "gpu_median_total_ms": gpu_ms,
        "speedup": cpu_ms / gpu_ms if gpu_ms > 0 else 0.0,
        "max_mixed_error": max_mixed_error(data),
        "gpu_total_jitter": check_value(validation, "gpu_total_stability"),
        "gpu_free_drift_mib": check_value(validation, "gpu_free_memory_drift_mib"),
        "rss_current_drift_mib": check_value(validation, "rss_current_drift_mib"),
        "metrics_path": rel(metrics_path),
        "summary_path": rel(summary_path),
        "stage_timings_path": rel(timings_path),
    }

tasks = [task_summary("task1_radar"), task_summary("task2_features")]
leak = {
    "requested": os.environ.get("TASK_DEMO_LEAK_CHECK") == "1",
    "compute_sanitizer": os.environ.get("TASK_DEMO_COMPUTE_SANITIZER_STATUS", "not_requested"),
    "asan_lsan": os.environ.get("TASK_DEMO_ASAN_STATUS", "not_requested"),
}
overall_pass = all(task["validation_pass"] for task in tasks) and leak["compute_sanitizer"] != "failed"
payload = {
    "pass": overall_pass,
    "repeat": int(os.environ.get("TASK_DEMO_REPEAT", "0")),
    "tasks": tasks,
    "leak_check": leak,
    "visualization": os.environ.get("TASK_DEMO_VISUALIZATION_STATUS", "unknown"),
}

json_path = report_root / "latest_task_demo_report.json"
md_path = report_root / "latest_task_demo_report.md"
json_path.write_text(json.dumps(payload, indent=2) + "\n")

lines = ["# Task Demo Validation Report", ""]
lines.append(f"- pass: `{str(overall_pass).lower()}`")
lines.append(f"- repeat: `{payload['repeat']}`")
lines.append(f"- compute_sanitizer: `{leak['compute_sanitizer']}`")
lines.append(f"- asan_lsan: `{leak['asan_lsan']}`")
lines.append(f"- visualization: `{payload['visualization']}`")
lines.append("")
lines.append("| task | scale | validation | gpu_ms | cpu_ms | speedup | max_mixed_error | failed_checks |")
lines.append("| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |")
for task in tasks:
    failed_names = ", ".join(check.get("name", "") for check in task["failed_checks"]) or "-"
    lines.append(
        f"| {task['name']} | L{task['scale_level']} | {str(task['validation_pass']).lower()} | "
        f"{task['gpu_total_ms']:.6f} | {task['cpu_total_ms']:.6f} | "
        f"{task['speedup']:.3f} | {task['max_mixed_error']:.6g} | {failed_names} |"
    )
lines.append("")
lines.append("## Artifacts")
lines.append("")
for task in tasks:
    lines.append(f"- {task['name']} metrics: `{task['metrics_path']}`")
    lines.append(f"- {task['name']} summary: `{task['summary_path']}`")
lines.append(f"- aggregate json: `{rel(json_path)}`")
lines.append(f"- aggregate markdown: `{rel(md_path)}`")
md_path.write_text("\n".join(lines) + "\n")

print(f"[task-demos] wrote {rel(json_path)}")
print(f"[task-demos] wrote {rel(md_path)}")

scale_pass = True
if os.environ.get("TASK_DEMO_SCALE_SWEEP") == "1":
    requested_scales = [int(item) for item in os.environ.get("TASK_DEMO_SCALES", "1,2,3,4,5,6").split(",") if item]
    scale_rows = [scale_row(name, scale) for scale in requested_scales for name in ("task1_radar", "task2_features")]
    scale_pass = all(row["validation_pass"] for row in scale_rows)

    scale_json_path = report_root / "latest_task_demo_scale_report.json"
    scale_csv_path = report_root / "latest_task_demo_scale_benchmark.csv"
    scale_md_path = report_root / "latest_task_demo_scale_report.md"
    scale_payload = {
        "pass": scale_pass,
        "repeat": int(os.environ.get("TASK_DEMO_REPEAT", "0")),
        "scales": requested_scales,
        "rows": scale_rows,
    }
    scale_json_path.write_text(json.dumps(scale_payload, indent=2) + "\n")
    columns = [
        "task",
        "scale_level",
        "scale_value",
        "primary_dim",
        "samples",
        "template_length",
        "repeat",
        "validation_pass",
        "cpu_median_total_ms",
        "gpu_median_total_ms",
        "speedup",
        "max_mixed_error",
        "gpu_total_jitter",
        "gpu_free_drift_mib",
        "rss_current_drift_mib",
        "metrics_path",
        "summary_path",
        "stage_timings_path",
    ]
    with scale_csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for row in scale_rows:
            writer.writerow({key: (str(value).lower() if isinstance(value, bool) else value)
                             for key, value in row.items()})

    md = ["# Task Demo Scale Benchmark", ""]
    md.append(f"- pass: `{str(scale_pass).lower()}`")
    md.append(f"- repeat: `{os.environ.get('TASK_DEMO_REPEAT', '0')}`")
    md.append("")
    md.append("| task | scale | size | validation | gpu_ms | cpu_ms | speedup | max_mixed_error | jitter | gpu_drift_mib | rss_drift_mib |")
    md.append("| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in scale_rows:
        md.append(
            f"| {row['task']} | L{row['scale_level']} | {row['primary_dim']}x{row['samples']} | "
            f"{str(row['validation_pass']).lower()} | {row['gpu_median_total_ms']:.6f} | "
            f"{row['cpu_median_total_ms']:.6f} | {row['speedup']:.3f} | "
            f"{row['max_mixed_error']:.6g} | {row['gpu_total_jitter']:.6g} | "
            f"{row['gpu_free_drift_mib']:.6g} | {row['rss_current_drift_mib']:.6g} |"
        )
    md.append("")
    md.append("## Artifacts")
    md.append("")
    md.append(f"- scale csv: `{rel(scale_csv_path)}`")
    md.append(f"- scale json: `{rel(scale_json_path)}`")
    md.append(f"- scale markdown: `{rel(scale_md_path)}`")
    scale_md_path.write_text("\n".join(md) + "\n")
    print(f"[task-demos] wrote {rel(scale_csv_path)}")
    print(f"[task-demos] wrote {rel(scale_json_path)}")
    print(f"[task-demos] wrote {rel(scale_md_path)}")

if not overall_pass or not scale_pass:
    raise SystemExit(1)
PY

if [[ "${SCALE_SWEEP}" -eq 1 ]]; then
  if [[ "${VISUALIZATION_DEPS_STATUS}" == "unknown" ]]; then
    if has_visualization_deps; then
      VISUALIZATION_DEPS_STATUS="available"
    else
      VISUALIZATION_DEPS_STATUS="missing"
    fi
  fi
  if [[ "${VISUALIZATION_DEPS_STATUS}" == "missing" ]]; then
    if [[ "${REQUIRE_VISUALIZATION_DEPS}" -eq 1 ]]; then
      echo "[task-demos] error: scale visualization requires python numpy/matplotlib/scipy" >&2
      exit 2
    fi
    echo "[task-demos] skipping scale visualization: python numpy/matplotlib/scipy not available"
  else
    python3 "${SCRIPT_DIR}/plot_task_demo_scale_benchmark.py" \
      --csv "${REPORT_ROOT}/latest_task_demo_scale_benchmark.csv" \
      --output-root "${REPORT_ROOT}"
    if [[ "${REQUIRE_VISUALIZATION_DEPS}" -eq 1 ]] && \
        [[ ! -f "${REPORT_ROOT}/task1_radar/task1_l1_l6_scale_performance.png" ||
           ! -f "${REPORT_ROOT}/task2_multidomain_l1_l6_scale_performance.png" ]]; then
      echo "[task-demos] error: scale visualization did not produce expected figures under ${REPORT_ROOT}" >&2
      exit 2
    fi
  fi
fi
