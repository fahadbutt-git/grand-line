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
cur="$HOME/.local/state/mac-setup/current/theme"
mkdir -p "$HOME/.claude"
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1
if grep -q "background = 2e3440" "$HOME/.config/ghostty/theme.conf" 2>/dev/null; then t_ok "theme writes terminal colours"; else t_fail "theme did not write terminal colours"; fi
grep -q "palette = 15=#eceff4" "$HOME/.config/ghostty/theme.conf" && t_ok "theme writes all 16 terminal colours" || t_fail "theme palette missing"
[[ "$(head -1 "$cur/nvim-theme" 2>/dev/null)" == nord ]] && t_ok "theme picks the matching Neovim scheme" || t_fail "theme did not set the Neovim scheme"
grep -q -- "-f SFProText-Regular" "$cur/menu-flags" && t_ok "theme gives the menus the system font and theme colours" || t_fail "menu style not written"
grep -q 'pane-active-border-style "fg=#88c0d0"' "$cur/tmux.conf" && t_ok "theme renders tmux colours" || t_fail "tmux colours not rendered"
grep -q 'theme\[hi_fg\]="#88c0d0"' "$HOME/.config/btop/themes/mac-setup.theme" 2>/dev/null && t_ok "theme installs a btop theme" || t_fail "btop theme missing"
grep -qx 'color_theme = "mac-setup"' "$HOME/.config/btop/btop.conf" && t_ok "theme chooses it in btop when you had not" || t_fail "btop setting not written"
[[ -L "$HOME/Library/Application Support/lazygit/config.yml" ]] && t_ok "theme links lazygit's colours when it had no settings" || t_fail "lazygit not linked"
jq -e '.base == "dark" and .overrides.claude == "#88c0d0"' "$HOME/.claude/themes/mac-setup.json" >/dev/null 2>&1 \
  && t_ok "theme writes a Claude Code custom theme" || t_fail "Claude Code theme missing or invalid"
printf 'color_theme = "Default"\n' > "$HOME/.config/btop/btop.conf"
"$ROOT/bin/theme" set daylight --no-wallpaper >/dev/null 2>&1
grep -qx 'color_theme = "mac-setup"' "$HOME/.config/btop/btop.conf" && t_ok "theme takes over btop's own Default setting" || t_fail "btop Default not replaced"
printf 'color_theme = "nord"\n' > "$HOME/.config/btop/btop.conf"
rm "$HOME/Library/Application Support/lazygit/config.yml"; echo "mine: true" > "$HOME/Library/Application Support/lazygit/config.yml"
mkdir -p "$HOME/.config/mac-setup/themed"; echo "mine {{ LABEL }} {{ COLOR1 }} {{ NOPE }}" > "$HOME/.config/mac-setup/themed/menu-flags.tpl"
"$ROOT/bin/theme" set daylight --no-wallpaper >/dev/null 2>&1
grep -qx 'color_theme = "nord"' "$HOME/.config/btop/btop.conf" && t_ok "theme leaves a btop theme you chose" || t_fail "btop setting overwritten"
grep -qx "mine: true" "$HOME/Library/Application Support/lazygit/config.yml" && t_ok "theme leaves your own lazygit settings" || t_fail "lazygit settings replaced"
[[ "$(cat "$cur/menu-flags")" == "mine Daylight d70015 {{ NOPE }}" ]] && t_ok "your own template overrides the package's, unknown keys stay as written" \
  || t_fail "user template not used" "$(cat "$cur/menu-flags")"
[[ "$(sed -n 2p "$cur/nvim-theme")" == light && ! -d "$HOME/.local/state/mac-setup/current/next-theme" ]] \
  && t_ok "theme swaps the rendered folder in whole" || t_fail "rendered folder not swapped"
rm -rf "$HOME/.config/mac-setup/themed"
# Every built-in template fills every placeholder, in every theme.
# shellcheck source=lib/templates.sh
source "$ROOT/lib/templates.sh"
for th in "$ROOT"/config/themes/*.theme; do
  n="$(basename "$th" .theme)"; render_templates "$th" "$n" "$tmp/render-$n" "$ROOT/config/themed"
  left="$(grep -l '{{' "$tmp/render-$n"/* 2>/dev/null)"
  [[ -z "$left" ]] && t_ok "templates: $n fills every placeholder" || t_fail "templates: $n left placeholders" "$left"
  jq -e . "$tmp/render-$n/claude.json" >/dev/null 2>&1 || t_fail "templates: $n claude.json is not valid JSON"
done
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1
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
cmds="$("$ROOT/bin/mac" commands)"
if grep -q "^migrate  *Run the package" <<<"$cmds" && [[ "$(grep -c . <<<"$cmds")" == "$(find "$ROOT/bin" -type f | wc -l | tr -d ' ')" ]] && ! grep -qE '^[^ ]+ *$' <<<"$cmds"; then
  t_ok "mac commands lists each command with its summary"; else t_fail "mac commands" "$cmds"; fi
unset MAC_SETUP_REPO MAC_SETUP_NO_APPLY

# --- menu: guards, check marks (all in one process), and your own entries
cat > "$tmp/menu.tsv" <<EOF
Toggle/Always	echo always > "$tmp/ran"
Toggle/Hidden	echo hidden	?false
Toggle/On	echo on > "$tmp/ran"		✓true
Toggle/Shown not checked	echo x	?true	✓false
Toggle/Theme	echo t		✓theme_is nord
Toggle/Old	echo old
EOF
export MENU_FILE="$tmp/menu.tsv" MENU_LOCAL="$tmp/menu.local.tsv"
printf 'Toggle/Old\t-\nToggle/Always\techo mine > "%s/ran"\nToggle/Mine\techo new\n' "$tmp" > "$MENU_LOCAL"
rm -f "$tmp/ran"; answers "On ✓"
"$ROOT/bin/menu" Toggle
seen="$(sed '/^--$/d' "$CHOOSE_SEEN" | tr '\n' '|')"
[[ "$seen" == "Always|On ✓|Shown not checked|Theme ✓|Mine|" ]] && t_ok "menu hides failed guards, checks passing tests, merges your entries" \
  || t_fail "menu showed" "$seen"
[[ "$(cat "$tmp/ran" 2>/dev/null)" == on ]] && t_ok "menu runs a checked entry" || t_fail "checked entry did not run"
rm -f "$tmp/ran"; answers "Always"; "$ROOT/bin/menu" Toggle
[[ "$(cat "$tmp/ran" 2>/dev/null)" == mine ]] && t_ok "menu.local.tsv replaces a shipped entry" || t_fail "local entry did not replace the shipped one"
printf 'G/A\techo a\t?echo $$ >> "%s/pids"\t\xe2\x9c\x93echo $$ >> "%s/pids"\nG/B\techo b\t?echo $$ >> "%s/pids"\nG/C\techo c\t\t\xe2\x9c\x93echo $$ >> "%s/pids"\n' "$tmp" "$tmp" "$tmp" "$tmp" > "$tmp/menu.tsv"
: > "$tmp/pids"; rm -f "$MENU_LOCAL"; answers ""; "$ROOT/bin/menu" G
[[ "$(wc -l < "$tmp/pids" | tr -d ' ')" == 4 && "$(sort -u "$tmp/pids" | wc -l | tr -d ' ')" == 1 ]] \
  && t_ok "menu runs every guard and check in one bash process" || t_fail "menu guard processes" "$(tr '\n' ' ' < "$tmp/pids")"
printf 'G/A\t-\n' > "$MENU_LOCAL"; answers ""; "$ROOT/bin/menu" G
[[ "$(sed '/^--$/d' "$CHOOSE_SEEN" | tr '\n' '|')" == "B|C ✓|" ]] && t_ok "a \"-\" line in menu.local.tsv removes an entry" || t_fail "menu.local removal" "$(cat "$CHOOSE_SEEN")"
unset MENU_FILE MENU_LOCAL

# --- your own shortcuts, merged into the installed copy and the shortcut list
printf 'Caps + Shift + Z\tApps\tZotero\topen -a Zotero\nunbind\tCaps + X\nCaps + Shift + Return\tApps\tMy browser\techo mine\n' > "$tmp/bindings.local.tsv"
REPO_DIR="$ROOT"
# shellcheck source=lib/overlay.sh
source "$ROOT/lib/overlay.sh"
merged="$(karabiner_with_overlay "$ROOT/config/karabiner/karabiner.json" "$tmp/bindings.local.tsv")"
m() { jq -c "[.profiles[0].complex_modifications.rules[1].manipulators[] | select($1)]" <<<"$merged"; }
[[ "$(m '.from.key_code == "z" and .from.modifiers.mandatory == ["shift"]')" == *'"open -a Zotero"'* ]] && t_ok "overlay adds a shortcut" || t_fail "overlay did not add Caps + Shift + Z"
[[ "$(m '.from.key_code == "x" and .from.modifiers == null')" == "[]" ]] && t_ok "overlay unbinds a shortcut" || t_fail "overlay did not unbind Caps + X"
got="$(m '.from.key_code == "return_or_enter" and .from.modifiers.mandatory == ["shift"]')"
[[ "$got" == *'"echo mine"'* && "$(jq length <<<"$got")" == 1 ]] && t_ok "overlay replaces a shipped shortcut" || t_fail "overlay replace" "$got"
[[ "$(m '.from.key_code == "c" and .from.modifiers == null')" != "[]" ]] && t_ok "overlay leaves other shortcuts alone" || t_fail "overlay removed Caps + C"
list="$(KEYBINDINGS_FILE="$ROOT/config/mac-setup/keybindings.tsv" KEYBINDINGS_LOCAL="$tmp/bindings.local.tsv" "$ROOT/bin/keybindings" --print)"
grep -q "^Caps + Shift + Z .*Zotero" <<<"$list" && ! grep -q "^Caps + X " <<<"$list" && grep -q "My browser" <<<"$list" \
  && t_ok "the shortcut list shows your shortcuts too" || t_fail "shortcut list ignores bindings.local.tsv"

# --- migrations: run once each, in order, stop at a failure
mr="$tmp/mrepo"; mkdir -p "$mr/migrations"
cp -R "$ROOT/lib" "$mr/lib"
printf 'echo first >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000000-first.sh"
printf 'echo second >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000100-second.sh"
export MAC_SETUP_REPO="$mr"
[[ "$("$ROOT/bin/migrate" --pending | tr '\n' ' ')" == "1700000000-first.sh 1700000100-second.sh " ]] && t_ok "migrate --pending lists them in order" || t_fail "pending list"
"$ROOT/bin/migrate" >/dev/null; "$ROOT/bin/migrate" >/dev/null
[[ "$(tr '\n' ' ' < "$tmp/order")" == "first second " ]] && t_ok "migrations run once each, oldest first" || t_fail "migration order" "$(cat "$tmp/order")"
[[ -f "$HOME/.local/state/mac-setup/migrations/1700000100-second.sh" ]] && t_ok "migrations leave a marker" || t_fail "no marker"
! "$ROOT/bin/migrate" --pending >/dev/null && t_ok "migrate --pending fails when none are left" || t_fail "pending with none left"
printf 'exit 3\n' > "$mr/migrations/1700000200-broken.sh"; printf 'echo after >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000300-after.sh"
if ! "$ROOT/bin/migrate" >/dev/null 2>&1 && ! grep -q after "$tmp/order" && [[ ! -f "$HOME/.local/state/mac-setup/migrations/1700000200-broken.sh" ]]; then
  t_ok "a failed migration stops the run and runs again next time"; else t_fail "failed migration handling"; fi
"$ROOT/bin/migrate" --mark-all
[[ "$("$ROOT/bin/migrate")" == "No one-time changes waiting." ]] && t_ok "migrate says when nothing is waiting" || t_fail "migrate with none waiting"
! "$ROOT/bin/migrate" --pending >/dev/null && ! grep -q after "$tmp/order" && t_ok "migrate --mark-all records all without running them" || t_fail "mark-all"
unset MAC_SETUP_REPO
# The real first migration moves the old Desktop checklist to the Trash.
mkdir -p "$HOME/Desktop"; echo old > "$HOME/Desktop/Finish setup.txt"
MAC_SETUP_REPO="$ROOT" bash "$ROOT/migrations/1793404800-desktop-checklist-to-trash.sh"
[[ ! -e "$HOME/Desktop/Finish setup.txt" && -f "$HOME/.Trash/Finish setup.txt" ]] && t_ok "migration: the old Desktop checklist goes to the Trash" || t_fail "Desktop checklist migration"
MAC_SETUP_REPO="$ROOT" bash "$ROOT/migrations/1793404800-desktop-checklist-to-trash.sh" && t_ok "migration: running it again is harmless" || t_fail "Desktop migration not repeatable"
# The template migration re-applies the current theme, and moves Paper to Daylight.
echo paper > "$HOME/.local/state/mac-setup/theme"; rm -rf "$HOME/.local/state/mac-setup/current"
MAC_SETUP_REPO="$ROOT" bash "$ROOT/migrations/1793404860-render-theme-templates.sh" >/dev/null 2>&1
[[ "$(cat "$HOME/.local/state/mac-setup/theme")" == daylight && -f "$HOME/.local/state/mac-setup/current/theme/tmux.conf" ]] \
  && t_ok "migration: the old Paper theme becomes Daylight, rendered from the templates" || t_fail "theme template migration"
rm -f "$HOME/.local/state/mac-setup/theme"
MAC_SETUP_REPO="$ROOT" bash "$ROOT/migrations/1793404860-render-theme-templates.sh" && t_ok "migration: with no theme yet it does nothing" || t_fail "theme migration with no theme"
# A fresh install marks every migration done; a Mac with a theme does not.
fh="$tmp/fresh"; mkdir -p "$fh"
plan="$(HOME="$fh" bash "$ROOT/setup.sh" --dry-run --only folders 2>&1)"
grep -q "bin/migrate --mark-all" <<<"$plan" && t_ok "a fresh install marks the migrations done" || t_fail "fresh install marking not planned"
mkdir -p "$fh/.local/state/mac-setup"; echo nord > "$fh/.local/state/mac-setup/theme"
plan="$(HOME="$fh" bash "$ROOT/setup.sh" --dry-run --only folders 2>&1)"
grep -q "mark-all" <<<"$plan" && t_fail "an existing Mac had its migrations marked" || t_ok "an existing Mac keeps its migrations to run"

# --- hooks: the named file and NAME.d/ in order, never .sample or non-executable
hd="$HOME/.config/mac-setup/hooks"; mkdir -p "$hd/theme-set.d"
mkhook() { printf '#!/bin/bash\necho "%s $*" >> "%s/hooks.log"\n' "$2" "$tmp" > "$1"; chmod +x "$1"; }
mkhook "$hd/theme-set" main; mkhook "$hd/theme-set.d/20-b" b; mkhook "$hd/theme-set.d/10-a" a
mkhook "$hd/theme-set.d/30-c.sample" sample; mkhook "$hd/theme-set.d/40-off" off; chmod -x "$hd/theme-set.d/40-off"
printf '#!/bin/bash\nexit 1\n' > "$hd/theme-set.d/15-fails"; chmod +x "$hd/theme-set.d/15-fails"
"$ROOT/bin/hook" theme-set nord 2>/dev/null
[[ "$(tr '\n' '|' < "$tmp/hooks.log")" == "main nord|a nord|b nord|" ]] && t_ok "hooks run in order with their arguments, skipping samples, plain files and failures" \
  || t_fail "hooks ran" "$(cat "$tmp/hooks.log")"
! "$ROOT/bin/hook" ../x 2>/dev/null && t_ok "a hook name cannot leave the hooks folder" || t_fail "hook name not checked"
: > "$tmp/hooks.log"; "$ROOT/bin/theme" set forest --no-wallpaper >/dev/null 2>&1
grep -q "^main forest" "$tmp/hooks.log" && t_ok "theme set fires the theme-set hook with the theme name" || t_fail "theme-set hook not fired"
rm -rf "$hd"

# --- focus or open, web apps, update lock and window
export AEROSPACE_WINDOWS=$'7|Ghostty|~\n9|Google Chrome|Inbox (3) - Gmail'
: > "$STUB_LOG"; "$ROOT/bin/focus-or-open" Ghostty
grep -q "aerospace focus --window-id 7" "$STUB_LOG" && ! grep -q "open -a" "$STUB_LOG" && t_ok "an app key focuses its open window" || t_fail "focus-or-open did not focus" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; "$ROOT/bin/focus-or-open" Notion
grep -q "open -a Notion" "$STUB_LOG" && t_ok "an app key opens an app with no window" || t_fail "focus-or-open did not open"
: > "$STUB_LOG"; "$ROOT/bin/webapp" "https://mail.google.com" "Gmail"
grep -q "aerospace focus --window-id 9" "$STUB_LOG" && ! grep -q "open " "$STUB_LOG" && t_ok "a web app key focuses its open window" || t_fail "webapp did not focus"
: > "$STUB_LOG"; "$ROOT/bin/webapp" "https://www.youtube.com" "YouTube"
grep -q "open " "$STUB_LOG" && t_ok "a web app key opens a window when none matches" || t_fail "webapp did not open"
unset AEROSPACE_WINDOWS
locktmp="$(mktemp -d)"; lock="$locktmp/mac-setup-update.lock"
mkdir "$lock"; echo "$$" > "$lock/pid"
out="$(TMPDIR="$locktmp" "$ROOT/bin/update" 2>&1)"
grep -q "Another update is running" <<<"$out" && t_ok "a second update waits for the first" || t_fail "update lock" "$out"
rm -rf "$locktmp"
: > "$STUB_LOG"; "$ROOT/bin/update" --window
grep -q "open -na Ghostty --args -e .*/bin/in-window --run .*/bin/update" "$STUB_LOG" && t_ok "update --window opens its own Ghostty window" || t_fail "update --window" "$(cat "$STUB_LOG")"
code="$("$ROOT/bin/in-window" --run false </dev/null 2>/dev/null; echo "$?")"
[[ "$code" == *"Failed (1)"*1 ]] && t_ok "the window reports a failure with its code" || t_fail "in-window failure" "$code"
[[ "$("$ROOT/bin/in-window" --run bash -c 'echo "$MAC_SETUP_IN_WINDOW"' </dev/null 2>/dev/null | head -1)" == 1 ]] \
  && t_ok "the window tells the command it is in sight" || t_fail "in-window did not set MAC_SETUP_IN_WINDOW"
: > "$STUB_LOG"; "$ROOT/bin/app" install --window zoom
grep -q "open -na Ghostty --args -e .*/bin/in-window --run .*/bin/app install zoom" "$STUB_LOG" \
  && t_ok "app install from the menu works in its own window" || t_fail "app install --window" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; MAC_SETUP_IN_WINDOW=1 "$ROOT/bin/app" install mpv
grep -qx 'cask "mpv"' "$HOME/.mac-setup/Brewfile" && grep -q "brew install --cask mpv" "$STUB_LOG" \
  && t_ok "app install in a window runs there, not in the background" || t_fail "app install in a window"

# --- toggle states: flag files and the current theme
# shellcheck source=lib/toggle-state.sh
source "$ROOT/lib/toggle-state.sh"
flag docker on; is_on docker && t_ok "a toggle flag reads as on" || t_fail "flag on"
flag docker off; ! is_on docker && t_ok "a cleared toggle flag reads as off" || t_fail "flag off"
echo "{ sec = 1" > "$TOGGLE_FLAGS/docker"; ! is_on docker && t_ok "a Docker flag from before the last restart reads as off" || t_fail "stale Docker flag read as on"
flag docker off
! is_on no-such-toggle && t_ok "an unknown toggle reads as off" || t_fail "unknown toggle"
echo forest > "$HOME/.local/state/mac-setup/theme"
theme_is forest && ! theme_is nord && t_ok "theme_is matches only the current theme" || t_fail "theme_is"

# --- personal details: read from personal.env, never asked without a keyboard
# shellcheck source=lib/personal.sh
source "$ROOT/lib/personal.sh"
source "$ROOT/lib/trash.sh"
PERSONAL_FILE="$HOME/.config/mac-setup/personal.env"; rm -f "$PERSONAL_FILE"
personal_ask </dev/null
[[ ! -f "$PERSONAL_FILE" ]] && t_ok "personal details are not asked for without a keyboard" || t_fail "personal_ask wrote a file with no keyboard"
mkdir -p "${PERSONAL_FILE%/*}"
printf '%s\n' '# comment' 'NAME=Ada Lovelace' 'SIGNOFF="Ada"' 'SIGNATURE=Ada Lovelace\nAnalytical Engines' 'LOCATION=51.5 -0.13 London' > "$PERSONAL_FILE"
[[ "$(personal_get NAME)" == "Ada Lovelace" && "$(personal_get SIGNOFF)" == Ada && -z "$(personal_get EMAIL)" ]] \
  && t_ok "personal details are read, quotes removed, missing ones empty" || t_fail "personal_get" "$(personal_get NAME)|$(personal_get SIGNOFF)"
esp="$tmp/personal.yml"; personal_espanso "$esp"
grep -q 'replace: "Best regards,\\nAda"' "$esp" && grep -q 'replace: "Ada Lovelace\\nAnalytical Engines"' "$esp" \
  && t_ok "your sign-off and signature become Espanso shortcuts" || t_fail "personal Espanso file" "$(cat "$esp")"
read -r lat lon place <<<"$(personal_get LOCATION)"
[[ "$lat $lon $place" == "51.5 -0.13 London" ]] && t_ok "the weather reads your town from personal details" || t_fail "LOCATION"
printf 'NAME=x\n' > "$PERSONAL_FILE"; personal_espanso "$esp"
[[ ! -f "$esp" ]] && t_ok "the Espanso file goes to the Trash when there is no signature" || t_fail "stale personal.yml kept"
rm -f "$PERSONAL_FILE"

exit $FAIL
