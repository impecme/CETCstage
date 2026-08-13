#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: scripts/smoke.sh [performance selection options]

Run correctness smoke tests for selected operators and/or tasks.  The default
is all 81 operators and both tasks at the fixed representative L3 workload.
Selection options are forwarded to performance.sh:
  --operators, --tasks, --all
  --operator-set NAME, --module NAME, --operator module/operator
  --task task1|task2|both
  --build-dir PATH, --no-build, --jobs N
USAGE
  exit 0
fi

"$SCRIPT_DIR/performance.sh" --case-set smoke --repeat 1 --warmup 0 --skip-timing-validation "$@"
