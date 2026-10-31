#!/usr/bin/env bash
# Puts this package in a new private GitHub repository under your account.
# Run once, from this folder, on a Mac where the gh command is signed in:
#   bash publish.sh            creates "mac-setup"
#   bash publish.sh NAME       creates NAME instead

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
name="${1:-mac-setup}"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first: gh auth login"; exit 1; }

if [[ ! -d .git ]]; then
  git init -q -b main
fi
git add -A
git diff --cached --quiet || git commit -q -m "Mac setup package"

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin main
else
  gh repo create "$name" --private --source=. --remote=origin --push
fi
echo
echo "Published: $(gh repo view --json url -q .url)"
echo "Tests run automatically on GitHub. See the Actions tab."
