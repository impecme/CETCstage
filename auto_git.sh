./scripts/clean_data.sh
git add docs/ data/ include/ src/ tests/ CMakeLists.txt README.md scripts/ .gitignore auto_git.sh demo/ AGENT.md copy_to_container.sh replace_container_project.sh

if git diff --cached --quiet; then
	echo "No staged changes to commit."
	exit 1
fi

git commit -m "$1"
git push