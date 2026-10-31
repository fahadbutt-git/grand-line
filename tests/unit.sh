#!/usr/bin/env bash
# Behaviour tests for the menus, shortcut list, themes and ArtCraft download
# choice. Mac-only commands are replaced by the stubs in tests/stubs.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

FAIL=0
t_ok()   { printf '    ok    %s\n' "$1"; }
t_fail() { printf '    FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '          %s\n' "$2"; FAIL=1; }

export HOME="$tmp/home"
export PATH="$ROOT/tests/stubs:$PATH"
export MAC_SETUP_TEST_PATH="$ROOT/tests/stubs"
export STUB_LOG="$tmp/stub.log"
export CHOOSE_ANSWERS="$tmp/answers"
export CHOOSE_SEEN="$tmp/seen"
mkdir -p "$HOME/.mac-setup/bin"
: > "$STUB_LOG"

answers() { printf '%s\n' "$@" > "$CHOOSE_ANSWERS"; : > "$CHOOSE_SEEN"; }

# --- menu: groups, nesting, running the chosen command
cat > "$tmp/menu.tsv" <<EOF
# test menu
Capture/Screenshot of an area	echo area > "$tmp/ran"
Capture/Deeper/Item	echo deep > "$tmp/ran"
System/Lock	echo lock > "$tmp/ran"
EOF
export MENU_FILE="$tmp/menu.tsv"

answers "Capture ›" "Screenshot of an area"
"$ROOT/bin/menu"
if [[ "$(cat "$tmp/ran" 2>/dev/null)" == area ]]; then t_ok "menu opens a group and runs the chosen item"; else t_fail "menu did not run the chosen item"; fi
if head -2 "$CHOOSE_SEEN" | tr '\n' '|' | grep -q '^Capture ›|System ›|$'; then t_ok "menu lists top-level groups in file order"
else t_fail "top level shown wrong" "$(head -3 "$CHOOSE_SEEN" | tr '\n' '|')"; fi
if sed -n '/^--$/,$p' "$CHOOSE_SEEN" | grep -qx "Deeper ›"; then t_ok "menu marks nested groups"; else t_fail "nested group not marked"; fi

rm -f "$tmp/ran"; answers "Deeper ›" "Item"
"$ROOT/bin/menu" Capture
[[ "$(cat "$tmp/ran" 2>/dev/null)" == deep ]] && t_ok "menu opens straight into a group by name" || t_fail "direct group open failed"

rm -f "$tmp/ran"; answers ""
"$ROOT/bin/menu"
[[ ! -f "$tmp/ran" ]] && t_ok "pressing Escape in the menu runs nothing" || t_fail "Escape still ran something"

answers "x"
if ! "$ROOT/bin/menu" Nowhere 2>/dev/null; then t_ok "unknown group fails cleanly"; else t_fail "unknown group did not fail"; fi
unset MENU_FILE

# The real menu file parses and shows its groups
answers ""
MENU_FILE="$ROOT/config/mac-setup/menu.tsv" "$ROOT/bin/menu"
if grep -qx "System ›" "$CHOOSE_SEEN" && grep -qx "Capture ›" "$CHOOSE_SEEN"; then t_ok "real menu.tsv shows its groups"; else t_fail "real menu.tsv failed"; fi

# --- shortcut list
cat > "$HOME/.mac-setup/bin/menu" <<EOF
#!/bin/bash
echo "menu \$*" > "$tmp/ran"
EOF
chmod +x "$HOME/.mac-setup/bin/menu"
rm -f "$tmp/ran"; answers "Caps + Escape   ·   System menu (lock, sleep, restart, shut down)"
KEYBINDINGS_FILE="$ROOT/config/mac-setup/keybindings.tsv" "$ROOT/bin/keybindings"
[[ "$(cat "$tmp/ran" 2>/dev/null)" == "menu System" ]] && t_ok "shortcut list runs the chosen shortcut" || t_fail "shortcut list did not run it" "$(cat "$tmp/ran" 2>/dev/null)"

lines="$(KEYBINDINGS_FILE="$ROOT/config/mac-setup/keybindings.tsv" "$ROOT/bin/keybindings" --print | wc -l | tr -d ' ')"
[[ "$lines" -ge 90 ]] && t_ok "shortcut list prints all $lines shortcuts" || t_fail "shortcut list printed $lines lines"

# --- themes
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1
if grep -q "background = 2e3440" "$HOME/.config/ghostty/theme.conf" 2>/dev/null; then t_ok "theme writes terminal colours"; else t_fail "theme did not write terminal colours"; fi
grep -q "palette = 15=#eceff4" "$HOME/.config/ghostty/theme.conf" && t_ok "theme writes all 16 terminal colours" || t_fail "theme palette missing"
[[ "$(head -1 "$HOME/.local/state/mac-setup/nvim-theme" 2>/dev/null)" == nord ]] && t_ok "theme picks the matching Neovim scheme" || t_fail "theme did not set the Neovim scheme"
grep -q -- "-f SFProText-Regular" "$HOME/.local/state/mac-setup/menu-flags" && t_ok "theme gives the menus the system font and theme colours" || t_fail "menu style not written"
[[ "$(cat "$HOME/.local/state/mac-setup/theme" 2>/dev/null)" == nord ]] && t_ok "theme remembers the current theme" || t_fail "theme state not saved"
grep -q "defaults write -g AppleAccentColor -int 4" "$STUB_LOG" && t_ok "theme sets the accent colour" || t_fail "accent colour not set"
if ! "$ROOT/bin/theme" set nonexistent >/dev/null 2>&1; then t_ok "unknown theme fails cleanly"; else t_fail "unknown theme did not fail"; fi

mkdir -p "$HOME/Pictures/Backgrounds"
touch "$HOME/Pictures/Backgrounds/a.jpg" "$HOME/Pictures/Backgrounds/b.jpg" "$HOME/Pictures/Backgrounds/c.png"
echo "$HOME/Pictures/Backgrounds/c.png" > "$HOME/.local/state/mac-setup/background"
"$ROOT/bin/theme" next-background
[[ "$(cat "$HOME/.local/state/mac-setup/background")" == "$HOME/Pictures/Backgrounds/a.jpg" ]] \
  && t_ok "next background wraps around to the first image" || t_fail "next background did not wrap"
"$ROOT/bin/theme" next-background
[[ "$(cat "$HOME/.local/state/mac-setup/background")" == "$HOME/Pictures/Backgrounds/b.jpg" ]] \
  && t_ok "next background advances" || t_fail "next background did not advance"

# --- setup.sh options
if ! bash "$ROOT/setup.sh" --dry-run --only artcraf >/dev/null 2>&1; then t_ok "setup rejects a misspelled step name"; else t_fail "misspelled step name was accepted"; fi
steps_listed="$(bash "$ROOT/setup.sh" --list | tr '\n' ' ')"
steps_files="$(for f in "$ROOT"/steps/[0-9][0-9]-*.sh; do n="$(basename "$f" .sh)"; printf '%s ' "${n#[0-9][0-9]-}"; done)"
[[ "$steps_listed" == "$steps_files" ]] && t_ok "every step file is a step, in file order" || t_fail "steps differ" "$steps_listed vs $steps_files"
for f in "$ROOT"/steps/[0-9][0-9]-*.sh; do
  n="$(basename "$f" .sh)"; n="${n#[0-9][0-9]-}"
  grep -q "^step_${n//-/_}()" "$f" || t_fail "$(basename "$f") has no function step_${n//-/_}"
done
t_ok "every step file defines its step function"

# --- ArtCraft: choosing the right download from a release
if command -v jq >/dev/null 2>&1; then
  REPO_DIR="$ROOT"
  # shellcheck source=lib/common.sh
  source "$ROOT/lib/common.sh"
  # shellcheck source=steps/03-artcraft.sh
  source "$ROOT/steps/03-artcraft.sh"
  got="$(artcraft_pick_asset < "$ROOT/tests/fixtures/release-mixed.json")"
  [[ "$got" == "wordcraft-0.4.2-macos-universal.dmg"$'\t'"https://example.com/universal.dmg"$'\t' ]] \
    && t_ok "ArtCraft: prefers the Apple silicon or universal .dmg" || t_fail "ArtCraft picked: $got"
  got="$(artcraft_pick_asset < "$ROOT/tests/fixtures/release-zip-only.json")"
  [[ "$got" == pdfcraft-v0.1.0-aarch64-apple-darwin.zip* ]] \
    && t_ok "ArtCraft: falls back to the Apple silicon .zip, never Intel" || t_fail "ArtCraft picked: $got"
  got="$(artcraft_pick_asset < "$ROOT/tests/fixtures/release-other-platforms.json")"
  [[ "$got" == "wordcraft-macos-arm64.zip"$'\t'"https://example.com/mac.zip"$'\t'"sha256:abc123" ]] \
    && t_ok "ArtCraft: never picks Windows or Linux Arm builds, and keeps the checksum" || t_fail "ArtCraft picked: $got"
  got="$(artcraft_pick_asset < "$ROOT/tests/fixtures/release-no-mac.json")"
  [[ -z "$got" ]] && t_ok "ArtCraft: reports no Mac build instead of guessing" || t_fail "ArtCraft picked: $got"
else
  t_fail "jq is not installed, so the ArtCraft tests could not run"
fi

# --- tidy-downloads: rules, sources, age, clashes, never deleting
dl="$tmp/dl"; src="$tmp/sources"; mkdir -p "$dl/Documents" "$dl/My folder" "$src"
export MAC_SETUP_NO_RESCAN=1 XATTR_SOURCES="$src" MAC_SETUP_DOWNLOADS="$dl" MAC_SETUP_DOWNLOAD_RULES="$ROOT/config/mac-setup/downloads-rules.tsv"
age() { perl -e '$t = time - shift; utime $t, $t, @ARGV' "$1" "${@:2}"; }   # age SECONDS FILES
mk() { : > "$dl/$1"; age 120 "$dl/$1"; [[ -n "${2:-}" ]] && printf '%s' "$2" > "$src/$1"; }
mk report.pdf "https://claude.ai/api/files/x"
mk paper.pdf "https://pmc.ncbi.nlm.nih.gov/articles/x.pdf"
mk guide.docx "https://jamanetwork.com/author-guide"
mk data.csv
mk Notes.TXT; : > "$dl/Documents/Notes.TXT"
mk odd.xyz
mk old.xyz; age $((40 * 86400)) "$dl/old.xyz"
mk new.dmg
mk setup.dmg; age $((10 * 86400)) "$dl/setup.dmg"
: > "$dl/fresh.pdf"
mk part.pdf.crdownload; mk .hidden.pdf
before="$(cd "$dl" && find . | sort)"
plan="$("$ROOT/bin/tidy-downloads" --dry-run)"
[[ "$(cd "$dl" && find . | sort)" == "$before" ]] && t_ok "Downloads: dry run moves nothing" || t_fail "Downloads: dry run moved files"
grep -qx "report.pdf -> AI/Claude/report.pdf" <<<"$plan" && t_ok "Downloads: dry run shows the plan" || t_fail "Downloads: plan was" "$plan"
"$ROOT/bin/tidy-downloads"
check_at() { [[ -f "$dl/$1" ]] && t_ok "Downloads: $2" || t_fail "Downloads: $2" "$(cd "$dl" && find . -type f | sort | tr '\n' ' ')"; }
check_at "AI/Claude/report.pdf" "a file from Claude goes to AI/Claude"
check_at "Papers/paper.pdf" "a PDF from PubMed Central goes to Papers"
check_at "Documents/guide.docx" "the Papers rule only takes PDFs"
check_at "Data/data.csv" "a file with no source is sorted by type"
check_at "Documents/Notes 2.TXT" "a name clash keeps both files"
check_at "odd.xyz" "an unknown new file stays put"
[[ -n "$(find "$dl/Archive" -name old.xyz 2>/dev/null)" ]] && t_ok "Downloads: an old loose file is archived by month" || t_fail "Downloads: old file not archived"
check_at "Installers/new.dmg" "a new installer goes to Installers"
[[ -f "$HOME/.Trash/setup.dmg" ]] && t_ok "Downloads: an installer older than a week goes to the Trash" || t_fail "Downloads: old installer not trashed"
check_at "fresh.pdf" "a file still arriving is left alone"
check_at "part.pdf.crdownload" "an unfinished download is left alone"
check_at ".hidden.pdf" "hidden files are left alone"
[[ -d "$dl/My folder" ]] && t_ok "Downloads: folders are left alone" || t_fail "Downloads: a folder moved"
grep -q "report.pdf" "$HOME/Library/Logs/mac-setup/downloads.log" 2>/dev/null && t_ok "Downloads: every move is logged" || t_fail "Downloads: no log"
mkdir "${TMPDIR:-/tmp}/mac-setup-downloads.lock"; mk late.csv
"$ROOT/bin/tidy-downloads"; check_at "late.csv" "a second copy waits while one is running"
rmdir "${TMPDIR:-/tmp}/mac-setup-downloads.lock"
unset XATTR_SOURCES MAC_SETUP_DOWNLOADS MAC_SETUP_DOWNLOAD_RULES

# --- app install and remove keep the Brewfile in step
mkdir -p "$HOME/.mac-setup/config/mac-setup"
printf 'cask "zoom"\ncask "nikitabobko/tap/aerospace"\n' > "$HOME/.mac-setup/Brewfile"
printf 'WordCraft\tstorytold/wordcraft\tWord processor\nGridCraft\tstorytold/gridcraft\tSpreadsheets\n' > "$HOME/.mac-setup/config/mac-setup/artcraft.tsv"
export MAC_SETUP_DETACHED=1 BREW_CASKS="iina zoom" BREW_INSTALLED="zoom aerospace"
answers "iina"; "$ROOT/bin/app" install
grep -qx 'cask "iina"' "$HOME/.mac-setup/Brewfile" && t_ok "app install adds the app to the Brewfile" || t_fail "app install did not add to the Brewfile"
"$ROOT/bin/app" install iina; [[ "$(grep -c 'cask "iina"' "$HOME/.mac-setup/Brewfile")" == 1 ]] && t_ok "app install never adds a line twice" || t_fail "app install added a duplicate line"
"$ROOT/bin/app" remove aerospace
grep -q aerospace "$HOME/.mac-setup/Brewfile" && t_fail "app remove left a tap cask in the Brewfile" || t_ok "app remove takes a tap cask off the Brewfile"
grep -q 'cask "zoom"' "$HOME/.mac-setup/Brewfile" && t_ok "app remove leaves other apps alone" || t_fail "app remove touched other lines"
"$ROOT/bin/app" remove "GridCraft (ArtCraft)"
grep -q '^GridCraft' "$HOME/.mac-setup/config/mac-setup/artcraft.tsv" && t_fail "ArtCraft removal kept its row" || t_ok "app remove takes an ArtCraft app off its list"
grep -q '^WordCraft' "$HOME/.mac-setup/config/mac-setup/artcraft.tsv" && t_ok "ArtCraft removal leaves other rows" || t_fail "ArtCraft removal touched other rows"
grep -q "brew uninstall --cask aerospace" "$STUB_LOG" && ! grep -q -- "--zap" "$STUB_LOG" && t_ok "app remove keeps the app's data (no --zap)" || t_fail "app remove deleted data"
unset MAC_SETUP_DETACHED BREW_CASKS BREW_INSTALLED

# --- mac: history, undo, save, restore and experiments, on a scratch repository
r="$tmp/repo"; mkdir -p "$r"; git -C "$r" init -q -b main; git -C "$r" config user.email t@t; git -C "$r" config user.name t
echo one > "$r/a.txt"; git -C "$r" add -A; git -C "$r" commit -q -m "First"
export MAC_SETUP_REPO="$r" MAC_SETUP_NO_APPLY=1
"$ROOT/bin/mac" save "known good" >/dev/null
echo two > "$r/a.txt"; echo new > "$r/b.txt"; git -C "$r" add -A; git -C "$r" commit -q -m "Second"
hist="$("$ROOT/bin/mac" history)"; grep -q "Second" <<<"$hist" && t_ok "mac history lists changes" || t_fail "mac history"
"$ROOT/bin/mac" undo >/dev/null; [[ "$(cat "$r/a.txt")" == one && ! -e "$r/b.txt" ]] && t_ok "mac undo reverses the last change" || t_fail "mac undo"
"$ROOT/bin/mac" undo >/dev/null; [[ "$(cat "$r/a.txt")" == two ]] && t_ok "mac undo can undo an undo" || t_fail "mac undo of undo"
tag="$(git -C "$r" tag -l 'good-*' | head -1)"
"$ROOT/bin/mac" restore "$tag" >/dev/null; [[ "$(cat "$r/a.txt")" == one && ! -e "$r/b.txt" ]] && t_ok "mac restore returns to a saved version, removing later files" || t_fail "mac restore"
"$ROOT/bin/mac" try start idea >/dev/null; echo idea > "$r/a.txt"; "$ROOT/bin/mac" try drop >/dev/null
[[ "$(cat "$r/a.txt")" == one && "$(git -C "$r" branch --show-current)" == main ]] && t_ok "mac try drop throws an experiment away" || t_fail "mac try drop"
"$ROOT/bin/mac" try start better >/dev/null; echo better > "$r/a.txt"; "$ROOT/bin/mac" try keep >/dev/null
[[ "$(cat "$r/a.txt")" == better && "$(git -C "$r" branch --show-current)" == main ]] && t_ok "mac try keep keeps an experiment" || t_fail "mac try keep"
unset MAC_SETUP_REPO MAC_SETUP_NO_APPLY

exit $FAIL
