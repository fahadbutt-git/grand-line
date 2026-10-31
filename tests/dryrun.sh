#!/usr/bin/env bash
# Runs the whole setup in dry-run mode against an empty home folder, with the
# Mac-only commands replaced by stubs. Passes when setup plans every step and
# leaves the home folder untouched.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

out="$tmp/out.txt"
env -i HOME="$tmp/home" PATH="$ROOT/tests/stubs:/usr/bin:/bin" TERM=dumb \
  bash "$ROOT/setup.sh" --dry-run > "$out" 2>&1
status=$?

fail=0
expect() {
  if ! grep -qF -- "$1" "$out"; then echo "dry run never planned: $1"; fail=1; fi
}

[[ $status -eq 0 ]] || { echo "setup.sh --dry-run exited with $status"; fail=1; }
# A test machine may already have Homebrew; either path is correct.
grep -qF "Homebrew/install/HEAD/install.sh" "$out" || grep -qF "Homebrew already installed" "$out" \
  || { echo "dry run neither installed nor found Homebrew"; fail=1; }
expect "brew bundle --file="
expect "install WordCraft from the latest release of github.com/storytold/wordcraft"
expect "install PdfCraft from the latest release of github.com/storytold/pdfcraft"
expect "install.packages"
expect "ln -s $ROOT $tmp/home/.mac-setup"
expect "ln -s $ROOT/config/aerospace/aerospace.toml $tmp/home/.aerospace.toml"
expect "cp $ROOT/config/karabiner/karabiner.json $tmp/home/.config/karabiner/karabiner.json"
expect "ln -s $ROOT/config/tmux $tmp/home/.config/tmux"
expect "config/zsh/mac-setup.zsh"
expect "swiftc -O $ROOT/tools/ocr.swift"
expect "swiftc -O $ROOT/tools/pdfshrink.swift"
expect "defaults write NSGlobalDomain KeyRepeat -int 2"
expect "duti -s"
expect ".docx all"
expect ".pdf all"
expect "bin/theme set graphite"
expect "Setup finished."

if [[ -n "$(ls -A "$tmp/home")" ]]; then
  echo "dry run wrote into the home folder:"; ls -A "$tmp/home"; fail=1
fi

# --list and --only work
env -i HOME="$tmp/home" PATH="$ROOT/tests/stubs:/usr/bin:/bin" bash "$ROOT/setup.sh" --list | grep -qx artcraft \
  || { echo "--list does not show the artcraft step"; fail=1; }
env -i HOME="$tmp/home" PATH="$ROOT/tests/stubs:/usr/bin:/bin" bash "$ROOT/setup.sh" --dry-run --only folders > "$tmp/only.txt" 2>&1
if grep -q "brew bundle" "$tmp/only.txt" || ! grep -q "== folders ==" "$tmp/only.txt"; then
  echo "--only folders ran the wrong steps"; fail=1
fi

[[ $fail -eq 1 ]] && { echo "---- full output ----"; cat "$out"; }
exit $fail
