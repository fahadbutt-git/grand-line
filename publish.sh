#!/usr/bin/env bash
# Puts this package in a new private GitHub repository under your account.
# Run once, from this folder, on a Mac where the gh command is signed in:
#   bash publish.sh            creates "grand-line"
#   bash publish.sh NAME       creates NAME instead
# It lists every file it would send, checks them for keys and tokens, and asks
# before anything leaves this Mac. Later changes go with: grandline publish

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
name="${1:-grand-line}"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first: gh auth login"; exit 1; }
[[ -t 0 ]] || { echo "Run this in a terminal: it asks before sending anything."; exit 1; }

ask() {
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == [yY]* ]]
}

if [[ ! -d .git ]]; then
  git init -q -b main
fi
git add -A
if ! git diff --cached --quiet; then
  echo "Files to be saved and sent:"
  git diff --cached --name-status | sed 's/^/  /'
  bash tests/security-checks.sh --secrets || { echo "Nothing sent: remove the lines above first."; exit 1; }
  ask "Save and send these files?" || { git reset -q; echo "Nothing saved or sent."; exit 1; }
  git commit -q -m "Grand Line"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git --no-pager log --oneline '@{u}..HEAD' 2>/dev/null || git --no-pager log --oneline -n 20
  ask "Send these commits to $(git remote get-url origin)?" || { echo "Nothing sent."; exit 1; }
  git push -u origin main
else
  gh repo create "$name" --private --source=. --remote=origin --push
fi
echo
echo "Published: $(gh repo view --json url -q .url)"
echo "Tests run automatically on GitHub. See the Actions tab."
