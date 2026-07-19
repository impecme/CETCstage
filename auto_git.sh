#!/usr/bin/env bash

./scripts/clean.sh
git add docs/ data/ include/ src/ tests/ CMakeLists.txt README.md scripts/ .gitignore auto_git.sh demo/ DELIVERY_FILES.txt third_party/fftw/dist/fftw-3.3.10.tar.gz

if git diff --cached --quiet; then
	echo "No staged changes to commit."
	exit 1
fi

git commit -m "$1"
git push
