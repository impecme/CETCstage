#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"

if [[ "$#" -ne 1 || -z "$1" ]]; then
	echo "Usage: ${BASH_SOURCE[0]} <commit-message>" >&2
	exit 2
fi

cd "${PROJECT_ROOT}"

if ! "${SCRIPT_DIR}/scripts/clean.sh"; then
	echo "[auto-git] clean failed; aborting before staging, commit, or push." >&2
	exit 1
fi

git fetch --quiet origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
	echo "[auto-git] origin/main is not an ancestor of HEAD; integrate remote changes before retrying." >&2
	echo "[auto-git] remote-only commits:" >&2
	git --no-pager log --oneline --decorate HEAD..origin/main >&2
	exit 1
fi

git add docs/ data/ include/ src/ tests/ CMakeLists.txt README.md scripts/ .gitignore auto_git.sh demo/ DELIVERY_FILES.txt third_party/fftw/dist/fftw-3.3.10.tar.gz

if git diff --cached --quiet; then
	echo "No staged changes to commit."
	exit 1
fi

git commit -m "$1"
if ! git push; then
	echo "[auto-git] push failed; the local commit is preserved. Integrate origin/main before retrying." >&2
	exit 1
fi
