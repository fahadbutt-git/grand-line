#!/usr/bin/env bash
# Runs the whole setup in dry-run mode against an empty home folder, with the
# Mac-only commands replaced by stubs. Passes when setup plans every step and
# leaves the home folder untouched.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

# Every run below gets its own pretend Homebrew folder and stubs, so the result
# never depends on what the test machine has installed.
sandbox() {
  env -i HOME="$tmp/home" PATH="$ROOT/tests/stubs:/usr/bin:/bin" TERM=dumb \
    GRAND_LINE_BREW_PREFIX="$tmp/brew" bash "$ROOT/setup.sh" "$@"
}

out="$tmp/out.txt"
sandbox --dry-run > "$out" 2>&1
status=$?

fail=0
expect() {
  if ! grep -qF -- "$1" "$out"; then echo "dry run never planned: $1"; fail=1; fi
}

[[ $status -eq 0 ]] || { echo "setup.sh --dry-run exited with $status"; fail=1; }
expect "Homebrew/install/HEAD/install.sh"
expect "brew bundle --file="
expect "install WordCraft from the latest release of github.com/storytold/wordcraft"
expect "install PdfCraft from the latest release of github.com/storytold/pdfcraft"
expect "install.packages"
expect "ln -s $ROOT $tmp/home/.grand-line"
expect "ln -s $ROOT/config/aerospace/aerospace.toml $tmp/home/.aerospace.toml"
expect "cp $ROOT/config/karabiner/karabiner.json $tmp/home/.config/karabiner/karabiner.json"
expect "ln -s $ROOT/config/tmux $tmp/home/.config/tmux"
expect "config/zsh/grand-line.zsh"
for src in "$ROOT"/tools/*.swift; do expect "swiftc -O $src"; done
expect "write the finishing checklist"
expect "carry the renamed apps' settings and index over"
expect "ln -s $ROOT/config/ghostty $tmp/home/.config/ghostty"
expect "ln -s $ROOT/config/starship.toml $tmp/home/.config/starship.toml"
expect "include.path $tmp/home/.grand-line/config/git/config"
expect "point Docker at"
expect "defaults write NSGlobalDomain KeyRepeat -int 2"
expect "duti -s"
expect ".docx all"
expect ".pdf all"
expect "bin/theme set graphite"
expect "grand-line.downloads.plist and load it"
expect "espanso/match/grand-line.yml"
expect "ln -s $ROOT/config/nvim $tmp/home/.config/nvim"
expect "defaults write com.apple.dock persistent-apps -array"
expect "mru-spaces -bool false"
expect "socketfilterfw --setglobalstate on"
expect "CriticalUpdateInstall -bool true"
expect "Setup finished."
expect "bin/migrate --mark-all"
for sample in "$ROOT"/config/grand-line/hooks/*.sample; do
  expect "cp $sample $tmp/home/.config/grand-line/hooks/${sample##*/}"
done

if [[ -n "$(ls -A "$tmp/home")" ]]; then
  echo "dry run wrote into the home folder:"; ls -A "$tmp/home"; fail=1
fi

# A Mac that already has Homebrew skips the Homebrew install.
mkdir -p "$tmp/brew/bin"
printf '#!/bin/bash\nexit 0\n' > "$tmp/brew/bin/brew"; chmod +x "$tmp/brew/bin/brew"
sandbox --dry-run --only homebrew > "$tmp/brew.txt" 2>&1
if ! grep -qF "Homebrew already installed" "$tmp/brew.txt" || grep -qF "Homebrew/install" "$tmp/brew.txt"; then
  echo "an existing Homebrew was not detected"; cat "$tmp/brew.txt"; fail=1
fi
rm -rf "$tmp/brew"

# --list and --only work
sandbox --list | grep -qx artcraft || { echo "--list does not show the artcraft step"; fail=1; }
sandbox --dry-run --only folders > "$tmp/only.txt" 2>&1
if grep -q "brew bundle" "$tmp/only.txt" || ! grep -q "== folders ==" "$tmp/only.txt"; then
  echo "--only folders ran the wrong steps"; fail=1
fi

# A Mac already set up keeps its migrations to run, keeps its own hooks, and
# gets its own shortcuts (bindings.local.tsv) merged into the Karabiner copy.
h2="$tmp/home2"; mkdir -p "$h2/.local/state/grand-line" "$h2/.config/grand-line/hooks"
echo graphite > "$h2/.local/state/grand-line/theme"
echo mine > "$h2/.config/grand-line/hooks/post-update.sample"
printf 'Caps + Shift + Z\tApps\tZotero\topen -a Zotero\n' > "$h2/.config/grand-line/bindings.local.tsv"
env -i HOME="$h2" PATH="$ROOT/tests/stubs:/usr/bin:/bin" TERM=dumb GRAND_LINE_BREW_PREFIX="$tmp/brew" \
  bash "$ROOT/setup.sh" --dry-run --only dotfiles > "$tmp/again.txt" 2>&1
grep -q "mark-all" "$tmp/again.txt" && { echo "an existing Mac had its migrations marked done"; fail=1; }
grep -q "hooks/post-update.sample" "$tmp/again.txt" && { echo "setup would replace a hook sample you already have"; fail=1; }
grep -qF "merge $h2/.config/grand-line/bindings.local.tsv into the Caps Lock shortcuts" "$tmp/again.txt" \
  || { echo "your own shortcuts were not merged"; cat "$tmp/again.txt"; fail=1; }
[[ "$(cat "$h2/.config/grand-line/hooks/post-update.sample")" == mine ]] || { echo "dry run changed a hook"; fail=1; }

[[ $fail -eq 1 ]] && { echo "---- full output ----"; cat "$out"; }
exit $fail
