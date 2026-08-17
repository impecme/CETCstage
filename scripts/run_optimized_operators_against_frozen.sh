#!/usr/bin/env bash
set -euo pipefail

# Run only the current/optimized operator binaries and compare their report to
# the immutable historical GPU snapshot. This entrypoint never builds or runs
# the baseline source.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_ROOT="$PROJECT_ROOT/operator_gpu_baseline_75a700d_protocol"
OUTPUT_ROOT=""
BUILD_DIR=""
JOBS=""
NO_BUILD=0
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage: scripts/run_optimized_operators_against_frozen.sh [options]

Run all81 x L1-L6 on the optimized/current source only, using the frozen
baseline manifests and then writing a paired comparison report.

Options:
  --baseline-root PATH  Frozen baseline directory
  --output-root PATH    Optimized result directory
  --build-dir PATH      Build directory
  --jobs N              Build parallelism
  --no-build            Reuse existing optimized binaries
  --verbose             Pass verbose mode to operator tests
  -h, --help            Show this help
USAGE
}

resolve_path() {
  if [[ "$1" = /* ]]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$PROJECT_ROOT/$1"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-root)
      [[ $# -ge 2 ]] || { echo "--baseline-root requires a value" >&2; exit 2; }
      BASELINE_ROOT="$(resolve_path "$2")"
      shift 2
      ;;
    --output-root)
      [[ $# -ge 2 ]] || { echo "--output-root requires a value" >&2; exit 2; }
      OUTPUT_ROOT="$(resolve_path "$2")"
      shift 2
      ;;
    --build-dir)
      [[ $# -ge 2 ]] || { echo "--build-dir requires a value" >&2; exit 2; }
      BUILD_DIR="$(resolve_path "$2")"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || { echo "--jobs requires a value" >&2; exit 2; }
      JOBS="$2"
      shift 2
      ;;
    --no-build)
      NO_BUILD=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUTPUT_ROOT" ]]; then
  OUTPUT_ROOT="$PROJECT_ROOT/data/reports/operator_gpu_optimized_frozen_$(date +%Y%m%d_%H%M%S)"
fi

python3 "$SCRIPT_DIR/operator_gpu_protocol.py" --validate-baseline "$BASELINE_ROOT"
baseline_csv="$BASELINE_ROOT/gpu_baseline.csv"
baseline_frozen="$BASELINE_ROOT/FROZEN"
baseline_csv_sha256="$(sha256sum "$baseline_csv" | awk '{print $1}')"
baseline_frozen_sha256="$(sha256sum "$baseline_frozen" | awk '{print $1}')"

build_args=()
[[ -n "$BUILD_DIR" ]] && build_args+=(--build-dir "$BUILD_DIR")
[[ -n "$JOBS" ]] && build_args+=(--jobs "$JOBS")
(( NO_BUILD )) && build_args+=(--no-build)

source_label="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || printf 'working-tree')"
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]]; then
  source_label+="+working-tree"
fi

performance_args=(
  --operators
  --operator-set all81
  --scale all
  --warmup 5
  --repeat 30
  --case-set full
  --frozen-baseline "$BASELINE_ROOT"
  --output-root "$OUTPUT_ROOT"
)
(( VERBOSE )) && performance_args+=(--verbose)

"$SCRIPT_DIR/performance.sh" "${build_args[@]}" "${performance_args[@]}"

after_csv_sha256="$(sha256sum "$baseline_csv" | awk '{print $1}')"
after_frozen_sha256="$(sha256sum "$baseline_frozen" | awk '{print $1}')"
[[ "$baseline_csv_sha256" == "$after_csv_sha256" ]] || {
  echo "[optimized-operators] frozen gpu_baseline.csv changed during run" >&2
  exit 1
}
[[ "$baseline_frozen_sha256" == "$after_frozen_sha256" ]] || {
  echo "[optimized-operators] frozen marker changed during run" >&2
  exit 1
}

optimized_csv="$OUTPUT_ROOT/units/benchmarks/operator_scales.csv"
comparison_root="$OUTPUT_ROOT/comparison"
python3 "$SCRIPT_DIR/compare_operator_gpu_baseline.py" \
  --baseline-root "$BASELINE_ROOT" \
  --optimized-csv "$optimized_csv" \
  --output-root "$comparison_root" \
  --optimized-source "$source_label"

echo "[optimized-operators] PASS output=$OUTPUT_ROOT"
echo "[optimized-operators] comparison=$comparison_root/operator_gpu_comparison.md"
