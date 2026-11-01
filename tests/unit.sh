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
export GRAND_LINE_TEST_PATH="$ROOT/tests/stubs"
export STUB_LOG="$tmp/stub.log"
export CHOOSE_ANSWERS="$tmp/answers"
export CHOOSE_SEEN="$tmp/seen"
mkdir -p "$HOME/.grand-line/bin"
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
MENU_FILE="$ROOT/config/grand-line/menu.tsv" "$ROOT/bin/menu"
if grep -qx "System ›" "$CHOOSE_SEEN" && grep -qx "Capture ›" "$CHOOSE_SEEN"; then t_ok "real menu.tsv shows its groups"; else t_fail "real menu.tsv failed"; fi

# --- shortcut list
cat > "$HOME/.grand-line/bin/menu" <<EOF
#!/bin/bash
echo "menu \$*" > "$tmp/ran"
EOF
chmod +x "$HOME/.grand-line/bin/menu"
rm -f "$tmp/ran"; answers "Caps + Escape   ·   System menu (lock, sleep, restart, shut down)"
KEYBINDINGS_FILE="$ROOT/config/grand-line/keybindings.tsv" "$ROOT/bin/keybindings"
[[ "$(cat "$tmp/ran" 2>/dev/null)" == "menu System" ]] && t_ok "shortcut list runs the chosen shortcut" || t_fail "shortcut list did not run it" "$(cat "$tmp/ran" 2>/dev/null)"

lines="$(KEYBINDINGS_FILE="$ROOT/config/grand-line/keybindings.tsv" "$ROOT/bin/keybindings" --print | wc -l | tr -d ' ')"
[[ "$lines" -ge 90 ]] && t_ok "shortcut list prints all $lines shortcuts" || t_fail "shortcut list printed $lines lines"

# --- themes
cur="$HOME/.local/state/grand-line/current/theme"
mkdir -p "$HOME/.claude"
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1
if grep -q "background = 2e3440" "$HOME/.config/ghostty/theme.conf" 2>/dev/null; then t_ok "theme writes terminal colours"; else t_fail "theme did not write terminal colours"; fi
grep -q "palette = 15=#eceff4" "$HOME/.config/ghostty/theme.conf" && t_ok "theme writes all 16 terminal colours" || t_fail "theme palette missing"
[[ "$(head -1 "$cur/nvim-theme" 2>/dev/null)" == nord ]] && t_ok "theme picks the matching Neovim scheme" || t_fail "theme did not set the Neovim scheme"
grep -q -- "-f SFProText-Regular" "$cur/menu-flags" && t_ok "theme gives the menus the system font and theme colours" || t_fail "menu style not written"
grep -q 'pane-active-border-style "fg=#88c0d0"' "$cur/tmux.conf" && t_ok "theme renders tmux colours" || t_fail "tmux colours not rendered"
grep -q 'theme\[hi_fg\]="#88c0d0"' "$HOME/.config/btop/themes/grand-line.theme" 2>/dev/null && t_ok "theme installs a btop theme" || t_fail "btop theme missing"
grep -qx 'color_theme = "grand-line"' "$HOME/.config/btop/btop.conf" && t_ok "theme chooses it in btop when you had not" || t_fail "btop setting not written"
[[ -L "$HOME/Library/Application Support/lazygit/config.yml" ]] && t_ok "theme links lazygit's colours when it had no settings" || t_fail "lazygit not linked"
jq -e '.base == "dark" and .overrides.claude == "#88c0d0"' "$HOME/.claude/themes/grand-line.json" >/dev/null 2>&1 \
  && t_ok "theme writes a Claude Code custom theme" || t_fail "Claude Code theme missing or invalid"
printf 'color_theme = "Default"\n' > "$HOME/.config/btop/btop.conf"
"$ROOT/bin/theme" set daylight --no-wallpaper >/dev/null 2>&1
grep -qx 'color_theme = "grand-line"' "$HOME/.config/btop/btop.conf" && t_ok "theme takes over btop's own Default setting" || t_fail "btop Default not replaced"
printf 'color_theme = "nord"\n' > "$HOME/.config/btop/btop.conf"
rm "$HOME/Library/Application Support/lazygit/config.yml"; echo "mine: true" > "$HOME/Library/Application Support/lazygit/config.yml"
mkdir -p "$HOME/.config/grand-line/themed"; echo "mine {{ LABEL }} {{ COLOR1 }} {{ NOPE }}" > "$HOME/.config/grand-line/themed/menu-flags.tpl"
"$ROOT/bin/theme" set daylight --no-wallpaper >/dev/null 2>&1
grep -qx 'color_theme = "nord"' "$HOME/.config/btop/btop.conf" && t_ok "theme leaves a btop theme you chose" || t_fail "btop setting overwritten"
grep -qx "mine: true" "$HOME/Library/Application Support/lazygit/config.yml" && t_ok "theme leaves your own lazygit settings" || t_fail "lazygit settings replaced"
[[ "$(cat "$cur/menu-flags")" == "mine Daylight #d70015 {{ NOPE }}" ]] && t_ok "your own template overrides the package's, unknown keys stay as written" \
  || t_fail "user template not used" "$(cat "$cur/menu-flags")"
[[ "$(sed -n 2p "$cur/nvim-theme")" == light && ! -d "$HOME/.local/state/grand-line/current/next-theme" ]] \
  && t_ok "theme swaps the rendered folder in whole" || t_fail "rendered folder not swapped"
rm -rf "$HOME/.config/grand-line/themed"
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
[[ "$(cat "$HOME/.local/state/grand-line/theme" 2>/dev/null)" == nord ]] && t_ok "theme remembers the current theme" || t_fail "theme state not saved"
grep -q "defaults write -g AppleAccentColor -int 4" "$STUB_LOG" && t_ok "theme sets the accent colour" || t_fail "accent colour not set"
if ! "$ROOT/bin/theme" set nonexistent >/dev/null 2>&1; then t_ok "unknown theme fails cleanly"; else t_fail "unknown theme did not fail"; fi
# A family name picks the variant for the current appearance (the defaults stub says light).
"$ROOT/bin/theme" set harbour --no-wallpaper >/dev/null 2>&1
[[ "$(cat "$HOME/.local/state/grand-line/theme" 2>/dev/null)" == harbour-light ]] && t_ok "theme set FAMILY picks the variant for the appearance" || t_fail "family not resolved" "$(cat "$HOME/.local/state/grand-line/theme")"
"$ROOT/bin/theme" mode toggle >/dev/null 2>&1
[[ "$(cat "$HOME/.local/state/grand-line/theme" 2>/dev/null)" == harbour-dark ]] && t_ok "theme mode toggle switches to the other variant" || t_fail "theme mode toggle"
"$ROOT/bin/theme" set graphite --no-wallpaper >/dev/null 2>&1; "$ROOT/bin/theme" mode light >/dev/null 2>&1
[[ "$(cat "$HOME/.local/state/grand-line/theme" 2>/dev/null)" == daylight ]] && t_ok "Graphite and Daylight pair up as dark and light" || t_fail "graphite to daylight"
(source "$ROOT/lib/toggle-state.sh"; echo signal-dark > "$HOME/.local/state/grand-line/theme"; theme_is signal && ! theme_is sig) \
  && t_ok "theme_is matches a family by its variants" || t_fail "theme_is family"
names="$("$ROOT/bin/theme" list)"
[[ "$(printf '%s\n' "$names" | sed -n 1p)" == atlas ]] && grep -qx paper <<< "$names" && grep -qx paper-light <<< "$names" \
  && t_ok "theme list names families and every variant" || t_fail "theme list"
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1

# --- theme format 1: EXTENDS, the checker, colour forms, live switching, apply, base16
tt="$tmp/themes"; mkdir -p "$tt"
# Every value the shipped themes had before EXTENDS still resolves the same.
bad=""
while read -r n kv; do
  [[ "$n" == "#" || -z "$n" ]] && continue
  got="$(theme_get "$ROOT/config/themes/$n.theme" "${kv%%=*}")"
  [[ "$got" == "${kv#*=}" ]] || bad="$bad $n:${kv%%=*}=$got"
done < "$ROOT/tests/fixtures/theme-values-before-extends.txt"
[[ -z "$bad" ]] && t_ok "EXTENDS: every shipped theme resolves to the values it had before" || t_fail "EXTENDS changed values" "$bad"
short=1
for fam in harbour lantern signal ledger atlas paper; do
  grep -qx "EXTENDS=$fam-dark" "$ROOT/config/themes/$fam-light.theme" || short=0
  [[ $(wc -l < "$ROOT/config/themes/$fam-light.theme") -lt $(wc -l < "$ROOT/config/themes/$fam-dark.theme") ]] || short=0
done
[[ "$short" == 1 ]] && t_ok "EXTENDS: each light variant extends its dark sibling and is shorter" || t_fail "light variants do not extend"
fresh="$(for t in "$ROOT"/config/themes/*.theme; do n="${t##*/}"; n="${n%.theme}"; theme_resolve "$t" 2>/dev/null | sed "s/^/$n /"; done)"
[[ "$fresh" == "$(grep -v '^#' "$ROOT/tests/fixtures/theme-resolved.txt")" ]] \
  && t_ok "tests/fixtures/theme-resolved.txt (read by the Swift tests) is current" || t_fail "theme-resolved.txt is stale; regenerate it (see its header)"
cmp -s "$ROOT/apps/finder/Sources/ThemeKit/ThemeSpec.swift" "$ROOT/apps/iceberg/Sources/IcebergKit/Theme/ThemeSpec.swift" \
  && t_ok "ThemeKit and IcebergKit share one ThemeSpec.swift" || t_fail "the two ThemeSpec.swift copies differ"

printf 'FORMAT=1\nEXTENDS=b\nLABEL=A\n' > "$tt/a.theme"
printf 'FORMAT=1\nEXTENDS=a\nLABEL=B\n' > "$tt/b.theme"
out="$("$ROOT/bin/theme" check "$tt/a.theme" 2>&1)"; rc=$?
[[ $rc != 0 && "$out" == *"b.theme:2: error: EXTENDS=a leads back to a (a loop)"* ]] && t_ok "EXTENDS: a loop is an error, not a hang" || t_fail "EXTENDS loop" "$out"
printf 'FORMAT=1\nEXTENDS=gone\n' > "$tt/c.theme"
out="$("$ROOT/bin/theme" check "$tt/c.theme" 2>&1)"
[[ "$out" == *"c.theme:2: error: EXTENDS=gone names no theme"* ]] && t_ok "EXTENDS: a missing parent names the line" || t_fail "missing parent" "$out"
cat > "$tt/base.theme" <<'EOF'
FORMAT=1
LABEL="Base"
MODE=dark
TERM_BG=1a1b1e
TERM_FG=e8e9eb
PALETTE="24262a f2665a 3cc57f e3c24a 6e8bff a281f5 57b4f0 e8e9eb 6d7076 f5857b 63d199 e9ce6e 8ba2ff b59af7 79c3f3 ffffff"
KIND_STYLE=dot
EOF
cat > "$tt/kid.theme" <<'EOF'
FORMAT=1
EXTENDS=base
LABEL="Kid"
TERM_FG=#FFFFFF
EOF
r="$(theme_resolve "$tt/kid.theme")"
grep -qx 'LABEL=Kid' <<< "$r" && grep -qx 'TERM_FG=ffffff' <<< "$r" && grep -qx 'TERM_BG=1a1b1e' <<< "$r" \
  && grep -qx 'KIND_STYLE=dot' <<< "$r" && ! grep -q '^EXTENDS=' <<< "$r" \
  && t_ok "EXTENDS: the child's keys win, the rest come from the parent" || t_fail "inheritance" "$r"
r="$(theme_resolve "$tt/base.theme")"
grep -qx 'ACCENT_HEX=6e8bff' <<< "$r" && grep -qx 'HIGHLIGHT=6e8bff' <<< "$r" && grep -qx 'MUTED=8b8c8f' <<< "$r" \
  && grep -qx 'KIND_PDF=f2665a' <<< "$r" && grep -qx 'UI_MOTION=full' <<< "$r" && grep -qx 'RADIUS_WINDOW=10' <<< "$r" \
  && grep -qx 'BACKGROUND=graphite.jpg' <<< "$r" && ! grep -q '^UI_DENSITY=' <<< "$r" \
  && t_ok "checker fills the defaults (colours from the theme's own, density left to each app)" || t_fail "defaults" "$r"
cat > "$tt/bad.theme" <<'EOF'
FORMAT=2
LABEL="Bad"
MODE=dusk
TERM_BG=12345g
TERM_FG=eeeeee
PALETTE="000000 111111"
UI_MOTION=wild
RADIUS_CHIP=99
EOF
out="$("$ROOT/bin/theme" check "$tt/bad.theme" 2>&1)"; rc=$?
n=0
for want in "bad.theme:1: error: FORMAT=2 is newer" "bad.theme:3: error: MODE=dusk" "bad.theme:4: error: TERM_BG=12345g is not a six-digit hex colour" \
            "bad.theme:6: error: PALETTE has 2 colours" "bad.theme:7: error: UI_MOTION=wild" "bad.theme:8: error: RADIUS_CHIP=99"; do
  [[ "$out" == *"$want"* ]] && n=$((n + 1))
done
[[ $rc != 0 && $n == 6 ]] && t_ok "checker rejects bad values with FILE:LINE messages" || t_fail "checker messages" "$out"
printf 'FORMAT=1\nLABEL=Dim\nMODE=dark\nTERM_BG=202020\nTERM_FG=444444\nMUTED=303030\nPALETTE="%s"\n' \
  "$(printf '%s ' 000000 111111 222222 333333 444444 555555 666666 777777 888888 999999 aaaaaa bbbbbb cccccc dddddd eeeeee | sed 's/ $//') ffffff" > "$tt/dim.theme"
out="$("$ROOT/bin/theme" check "$tt/dim.theme" 2>&1)"; rc=$?
[[ $rc == 0 && "$out" == *"dim.theme:5: warning: TERM_FG #444444 is"*"text needs 4.5:1"* && "$out" == *"dim.theme:6: warning: MUTED #303030"*"needs 3.0:1"* ]] \
  && t_ok "checker warns when text falls under 4.5:1 or secondary text under 3:1" || t_fail "contrast warnings" "$out"
"$ROOT/bin/theme" check --strict "$tt/dim.theme" >/dev/null 2>&1 && t_fail "--strict passed a warning" || t_ok "theme check --strict fails on warnings"

# Colour forms, and templates written for bare values still render one #.
mkdir -p "$tmp/forms"
printf '%s\n' '{{ ACCENT_HEX }}|{{ ACCENT_HEX.hex }}|{{ ACCENT_HEX.rgb }}|{{ ACCENT_HEX.dec }}|#{{ COLOR1 }}|{{ COLOR1.rgb }}|{{ LABEL }}|{{ LABEL.hex }}|{{ MODE.dec }}' > "$tmp/forms/f.tpl"
render_templates "$ROOT/config/themes/harbour-dark.theme" harbour-dark "$tmp/forms-out" "$tmp/forms" 2>/dev/null
[[ "$(cat "$tmp/forms-out/f")" == '#57b4f0|57b4f0|87,180,240|0.341 0.706 0.941|#f2665a|242,102,90|Harbour Dark|{{ LABEL.hex }}|{{ MODE.dec }}' ]] \
  && t_ok "templates: every colour as #rrggbb, .hex, .rgb and .dec" || t_fail "colour forms" "$(cat "$tmp/forms-out/f" 2>/dev/null)"
render_templates "$tt/bad.theme" bad "$tmp/forms-bad" "$tmp/forms" 2>/dev/null && t_fail "a theme with errors rendered" \
  || { [[ ! -f "$tmp/forms-bad/f" ]] && t_ok "templates: a theme with errors renders nothing"; }

# A copy of the package, so test themes never land in the real themes folder.
pkg="$tmp/pkg"; mkdir -p "$pkg/config"
cp -R "$ROOT/bin" "$ROOT/lib" "$pkg/"; cp -R "$ROOT/config/themes" "$ROOT/config/themed" "$pkg/config/"

# theme set: a broken theme changes nothing; a good one tells the apps at once.
cp "$tt/bad.theme" "$pkg/config/themes/bad.theme"
"$pkg/bin/theme" set bad --no-wallpaper >/dev/null 2>&1; rc=$?
[[ $rc != 0 && "$(cat "$HOME/.local/state/grand-line/theme")" == nord ]] && t_ok "theme set refuses a theme with errors" || t_fail "broken theme applied"
: > "$STUB_LOG"
"$ROOT/bin/theme" set harbour-light --no-wallpaper >/dev/null 2>&1
grep -q "osascript -l JavaScript .*postNotificationNameObjectUserInfoDeliverImmediately.*com.grandline.theme.changed.* harbour-light$" "$STUB_LOG" \
  && t_ok "theme set posts com.grandline.theme.changed for the apps" || t_fail "no theme notification" "$(grep JavaScript "$STUB_LOG")"

# theme apply: renders again and reloads each running tool that can reload.
mkdir -p "$tmp/tools"
printf '#!/bin/bash\necho "Ghostty 1.2.3"\n' > "$tmp/tools/ghostty"
printf '#!/bin/bash\necho "btop version: 1.4.0"\n' > "$tmp/tools/btop"
chmod +x "$tmp/tools/ghostty" "$tmp/tools/btop"
printf 'ghostty\nbtop\n' > "$tmp/running"
rm -f "$HOME/.config/ghostty/theme.conf"; : > "$STUB_LOG"
PATH="$PATH:$tmp/tools" STUB_RUNNING="$tmp/running" "$ROOT/bin/theme" apply >/dev/null 2>&1
grep -q "background = ffffff" "$HOME/.config/ghostty/theme.conf" 2>/dev/null && grep -qx "pkill -USR2 -x ghostty" "$STUB_LOG" \
  && grep -qx "pkill -USR2 -x btop" "$STUB_LOG" && grep -q "com.grandline.theme.changed" "$STUB_LOG" \
  && t_ok "theme apply renders again, reloads Ghostty and btop, and tells the apps" || t_fail "theme apply" "$(cat "$STUB_LOG")"
printf '#!/bin/bash\necho "Ghostty 1.1.3"\n' > "$tmp/tools/ghostty"
printf 'ghostty\nbtop\n' > "$tmp/running"; : > "$STUB_LOG"
PATH="$PATH:$tmp/tools" STUB_RUNNING="$tmp/running" "$ROOT/bin/theme" apply >/dev/null 2>&1
! grep -q "USR2 -x ghostty" "$STUB_LOG" && grep -q "USR2 -x btop" "$STUB_LOG" \
  && t_ok "theme apply leaves a Ghostty too old to reload (it would quit)" || t_fail "old Ghostty signalled"
printf '#!/bin/bash\necho "Ghostty 1.2.3"\n' > "$tmp/tools/ghostty"; : > "$STUB_LOG"
PATH="$PATH:$tmp/tools" STUB_RUNNING="$tmp/running" "$ROOT/bin/theme" refresh >/dev/null 2>&1
! grep -qE "USR2|theme.changed" "$STUB_LOG" && t_ok "theme refresh reloads nothing when the rendered theme did not change" || t_fail "refresh reloaded" "$(cat "$STUB_LOG")"

# base16 import (into the copy of the package).
if "$pkg/bin/theme" import-base16 "$ROOT/tests/fixtures/base16-flat.yaml" tide >/dev/null 2>&1; then
  r="$(theme_resolve "$pkg/config/themes/tide.theme" 2>/dev/null)"
  grep -qx 'MODE=dark' <<< "$r" && grep -qx 'TERM_BG=1b2027' <<< "$r" && grep -qx 'TERM_FG=dde3ea' <<< "$r" \
    && grep -qx 'ACCENT_HEX=5a9cf0' <<< "$r" && grep -qx 'ACCENT=4' <<< "$r" && grep -qx 'KIND_ARCHIVE=c29468' <<< "$r" \
    && grep -q '^PALETTE="1b2027 f2665a 3cc57f e3c24a 5a9cf0 a281f5 57c4d0 dde3ea 5c6672 ' <<< "$r" \
    && "$pkg/bin/theme" check tide >/dev/null 2>&1 \
    && t_ok "import-base16 maps base00 to base0F onto a dark theme that passes the checker" || t_fail "base16 mapping" "$r"
else t_fail "import-base16 failed"; fi
"$pkg/bin/theme" import-base16 "$ROOT/tests/fixtures/base16-tinted.yaml" shore >/dev/null 2>&1 \
  && [[ "$(theme_get "$pkg/config/themes/shore.theme" MODE)" == light && "$(theme_get "$pkg/config/themes/shore.theme" TERM_BG)" == fbfaf7 ]] \
  && t_ok "import-base16 reads the newer palette: layout, and a light variant stays light" || t_fail "tinted base16"
"$pkg/bin/theme" import-base16 "$ROOT/tests/fixtures/base16-flat.yaml" tide >/dev/null 2>&1 \
  && t_fail "import-base16 replaced a theme without --force" || t_ok "import-base16 keeps an existing theme unless --force"
grep -v base0F "$ROOT/tests/fixtures/base16-flat.yaml" > "$tmp/short.yaml"
out="$("$pkg/bin/theme" import-base16 "$tmp/short.yaml" short 2>&1)"
[[ "$out" == *"lacks base0F"* && ! -e "$pkg/config/themes/short.theme" ]] && t_ok "import-base16 refuses a scheme with a colour missing" || t_fail "short scheme" "$out"
"$ROOT/bin/theme" set nord --no-wallpaper >/dev/null 2>&1

mkdir -p "$HOME/Pictures/Backgrounds"
touch "$HOME/Pictures/Backgrounds/a.jpg" "$HOME/Pictures/Backgrounds/b.jpg" "$HOME/Pictures/Backgrounds/c.png"
echo "$HOME/Pictures/Backgrounds/c.png" > "$HOME/.local/state/grand-line/background"
"$ROOT/bin/theme" next-background
[[ "$(cat "$HOME/.local/state/grand-line/background")" == "$HOME/Pictures/Backgrounds/a.jpg" ]] \
  && t_ok "next background wraps around to the first image" || t_fail "next background did not wrap"
"$ROOT/bin/theme" next-background
[[ "$(cat "$HOME/.local/state/grand-line/background")" == "$HOME/Pictures/Backgrounds/b.jpg" ]] \
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

# --- ArtCraft: a release the signature checks refuse is a warning, remembered, and not fetched again
if command -v jq >/dev/null 2>&1; then
  (
    art="$tmp/artcraft"; mkdir -p "$art/config/grand-line"
    export REPO_DIR="$art" DRY_RUN=0 GRAND_LINE_STATE="$art/state" STUB_LOG="$art/log"
    source "$ROOT/lib/common.sh"; source "$ROOT/steps/03-artcraft.sh"
    state="$GRAND_LINE_STATE/artcraft"; : > "$art/api"
    # GitHub, the download and the zip, as functions. The app in the zip is
    # unsigned, so the codesign stub refuses it like an unnotarized release.
    echo v1 > "$art/tag"
    artcraft_latest_tag() { cat "$art/tag"; }
    artcraft_release_json() {
      echo "$1" >> "$art/api"
      [[ -f "$art/offline-${1#*/}" ]] && return 1
      printf '{"tag_name":"%s","assets":[{"name":"%s-mac-arm64.zip","browser_download_url":"https://example.com/a.zip"}]}\n' \
        "$(cat "$art/tag")" "${1#*/}"
    }
    curl() { local out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done; [[ -n "$out" ]] && echo zip > "$out"; }
    ditto() {
      [[ "$1" == -x ]] || return 1
      local app; app="$(basename "$3" -mac-arm64.zip)"
      mkdir -p "$4/$(tr 'a-z' 'A-Z' <<<"${app:0:1}")${app:1}.app/Contents"
    }
    out="$(artcraft_install_one Gridcraft storytold/gridcraft - 2>&1)"; rc=$?
    [[ $rc == 3 ]] || { echo "$out"; exit 1; }
    grep -q "unsigned or its signature is broken" <<<"$out" || exit 2
    [[ "$(cat "$state/Gridcraft.refused")" == "v1|" && ! -e "$state/Gridcraft.path" ]] || exit 3
    # The next run asks GitHub's API nothing about the same release.
    : > "$art/api"; out="$(artcraft_install_one Gridcraft storytold/gridcraft - 2>&1)"; rc=$?
    [[ $rc == 3 && ! -s "$art/api" ]] || { echo "$out"; exit 4; }
    grep -q "not downloaded again" <<<"$out" || exit 5
    # A newer release, or a different pin, is tried.
    echo v2 > "$art/tag"; out="$(artcraft_install_one Gridcraft storytold/gridcraft - 2>&1)"
    [[ -s "$art/api" && "$(cat "$state/Gridcraft.refused")" == "v2|" ]] || exit 6
    : > "$art/api"; artcraft_install_one Gridcraft storytold/gridcraft ABCDE12345 >/dev/null 2>&1
    [[ -s "$art/api" ]] || exit 7
    # The step: refusals alone are warnings and it succeeds; a real error fails it.
    printf 'Gridcraft\tstorytold/gridcraft\tSheets\t-\nDeckcraft\tstorytold/deckcraft\tSlides\t-\n' > "$art/config/grand-line/artcraft.tsv"
    WARNINGS=(); step_artcraft >/dev/null 2>&1 || exit 8
    [[ "${#WARNINGS[@]}" == 2 && "${WARNINGS[*]}" == *"Deckcraft was not installed: its release did not pass the signature checks"* ]] || exit 9
    WARNINGS=(); step_artcraft >/dev/null 2>&1 || exit 10      # again, from what was remembered
    printf 'Filmcraft\tstorytold/filmcraft\tVideo\t-\n' >> "$art/config/grand-line/artcraft.tsv"; : > "$art/offline-filmcraft"
    WARNINGS=(); step_artcraft >/dev/null 2>&1 && exit 11
    [[ "${WARNINGS[*]}" == *"Filmcraft did not install"* ]] || exit 12
    exit 0
  ) && t_ok "ArtCraft: a refused release is a warning, not a failed step, and is not fetched again until a newer one" \
    || t_fail "ArtCraft refusals (step $?)"
fi

# --- tidy-downloads: rules, sources, age, clashes, never deleting
# A file's age is when it arrived in Downloads (the mdls stub answers from
# $MDLS_DATES/<name>; with no answer, the inode change time), never its
# modification time. The clock is set two minutes ahead, so every file made
# here has settled.
dl="$tmp/dl"; src="$tmp/sources"; mdates="$tmp/mdls"; mkdir -p "$dl/Documents" "$dl/My folder" "$src" "$mdates"
export GRAND_LINE_NO_RESCAN=1 XATTR_SOURCES="$src" GRAND_LINE_DOWNLOADS="$dl" GRAND_LINE_DOWNLOAD_RULES="$ROOT/config/grand-line/downloads-rules.tsv"
export MDLS_DATES="$mdates" GRAND_LINE_NOW="$(( $(date +%s) + 120 ))" GRAND_LINE_DOWNLOADS_LOCK="$tmp/downloads.lock"
age() { perl -e '$t = time - shift; utime $t, $t, @ARGV' "$1" "${@:2}"; }   # age SECONDS FILES (modification time)
added() { perl -MPOSIX -e 'print strftime("%Y-%m-%d %H:%M:%S +0000", gmtime(time - shift))' "$2" > "$mdates/$1"; }   # added NAME SECONDS-AGO
mk() { printf 'x' > "$dl/$1"; [[ -n "${2:-}" ]] && printf '%s' "$2" > "$src/$1"; return 0; }
tidy() { "$ROOT/bin/tidy-downloads" "$@"; }
mk report.pdf "https://claude.ai/api/files/x"
mk paper.pdf "https://pmc.ncbi.nlm.nih.gov/articles/x.pdf"
mk guide.docx "https://jamanetwork.com/author-guide"
mk data.csv
mk Notes.TXT; : > "$dl/Documents/Notes.TXT"
mk odd.xyz
mk old.xyz; added old.xyz $((40 * 86400))
mk new.dmg
mk setup.dmg; added setup.dmg $((10 * 86400))
# Unpacked from a zip, sent by AirDrop or fetched with curl -R: an old
# modification time, but it arrived just now.
mk Foo.dmg; age $((500 * 86400)) "$dl/Foo.dmg"
mk unpacked.xyz; age $((400 * 86400)) "$dl/unpacked.xyz"
mk part.pdf.crdownload; mk .hidden.pdf
# Firefox and Zen: an empty file with the final name beside NAME.part.
: > "$dl/big.pdf"; mk big.pdf.part
before="$(cd "$dl" && find . | sort)"
plan="$(tidy --dry-run)"
[[ "$(cd "$dl" && find . | sort)" == "$before" ]] && t_ok "Downloads: dry run moves nothing" || t_fail "Downloads: dry run moved files"
grep -qx "report.pdf -> AI/Claude/report.pdf" <<<"$plan" && t_ok "Downloads: dry run shows the plan" || t_fail "Downloads: plan was" "$plan"
tidy
check_at() { [[ -f "$dl/$1" ]] && t_ok "Downloads: $2" || t_fail "Downloads: $2" "$(cd "$dl" && find . -type f | sort | tr '\n' ' ')"; }
check_at "AI/Claude/report.pdf" "a file from Claude goes to AI/Claude"
check_at "Papers/paper.pdf" "a PDF from PubMed Central goes to Papers"
check_at "Documents/guide.docx" "the Papers rule only takes PDFs"
check_at "Data/data.csv" "a file with no source is sorted by type"
check_at "Documents/Notes 2.TXT" "a name clash keeps both files"
check_at "odd.xyz" "an unknown new file stays put"
check_at "old.xyz" "a file the sorter sees for the first time is never archived, however old"
check_at "Installers/new.dmg" "a new installer goes to Installers"
check_at "Installers/setup.dmg" "an installer seen for the first time is never sent to the Trash"
check_at "Installers/Foo.dmg" "an installer with an old modification time is sorted, not trashed"
check_at "unpacked.xyz" "a file with an old modification time is not archived"
check_at "part.pdf.crdownload" "an unfinished download is left alone"
check_at "big.pdf" "a Firefox placeholder beside its .part is left alone"
check_at "big.pdf.part" "the .part it belongs to is left alone"
check_at ".hidden.pdf" "hidden files are left alone"
[[ -d "$dl/My folder" ]] && t_ok "Downloads: folders are left alone" || t_fail "Downloads: a folder moved"
grep -q "report.pdf" "$HOME/Library/Logs/grand-line/downloads.log" 2>/dev/null && t_ok "Downloads: every move is logged" || t_fail "Downloads: no log"
# Later runs: what was seen before may now be moved by age, by when it arrived.
tidy; tidy
[[ -n "$(find "$dl/Archive" -name old.xyz 2>/dev/null)" ]] && t_ok "Downloads: an old loose file is archived by the month it arrived" || t_fail "Downloads: old file not archived"
[[ -f "$HOME/.Trash/setup.dmg" ]] && t_ok "Downloads: an installer that arrived over a week ago goes to the Trash" || t_fail "Downloads: old installer not trashed"
check_at "Installers/Foo.dmg" "an installer that arrived just now stays, whatever its modification time"
check_at "unpacked.xyz" "a file that arrived just now is never archived, whatever its modification time"
[[ ! -e "$HOME/.Trash/Foo.dmg" ]] && t_ok "Downloads: the new installer is not in the Trash" || t_fail "Downloads: a new installer was trashed"
# An empty file that just appeared (it may be a placeholder) waits.
: > "$dl/empty.pdf"; tidy; check_at "empty.pdf" "a new empty file waits"
# A name taken by another run between the check and the move: nothing is
# replaced, the file takes the next free name (mv -n, then checked).
mkdir -p "$tmp/racebin"
printf '%s\n' '#!/bin/bash' \
  '# Another run takes the free name just before this move.' \
  'if [[ "$1" == -n && ! -e "$RACE_DONE" ]]; then : > "$RACE_DONE"; printf theirs > "$3"; fi' \
  'exec /bin/mv "$@"' > "$tmp/racebin/mv"
chmod +x "$tmp/racebin/mv"
printf 'mine' > "$dl/clash.csv"
GRAND_LINE_TEST_PATH="$tmp/racebin:$GRAND_LINE_TEST_PATH" RACE_DONE="$tmp/race-done" tidy
[[ "$(cat "$dl/Data/clash.csv" 2>/dev/null)" == theirs && "$(cat "$dl/Data/clash 2.csv" 2>/dev/null)" == mine ]] \
  && t_ok "Downloads: a name taken during the move is never overwritten" || t_fail "Downloads: race" "$(cd "$dl/Data" && ls)"
# One run at a time: a lock held by a running sorter is kept however long it
# has run; one left by a run that ended is taken over.
lockd="$GRAND_LINE_DOWNLOADS_LOCK"
sleep 300 & holder=$!
mkdir "$lockd"; printf '%s %s\n' "$holder" "$(LC_ALL=C ps -o lstart= -p "$holder" | sed 's/^ *//; s/ *$//')" > "$lockd/owner"
perl -e '$t = time - 3600; utime $t, $t, @ARGV' "$lockd"
mk late.csv; tidy; check_at "late.csv" "a second copy waits while one is running, even an hour on"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
tidy; check_at "Data/late.csv" "a lock left by a run that ended is taken over"
[[ ! -e "$lockd" ]] && t_ok "Downloads: the lock is given back" || t_fail "Downloads: lock left behind"
mkdir "$lockd"; mk later.csv; tidy; check_at "later.csv" "a lock just being taken (no owner yet) is respected"
rmdir "$lockd"
unset XATTR_SOURCES GRAND_LINE_DOWNLOADS GRAND_LINE_DOWNLOAD_RULES MDLS_DATES GRAND_LINE_NOW GRAND_LINE_DOWNLOADS_LOCK

# --- locks: held while the holder runs, taken over once it is gone, one winner
(
  source "$ROOT/lib/lock.sh"
  L="$tmp/locks/a.lock"; mkdir -p "$tmp/locks"
  lock_take "$L" || exit 1
  [[ "$(cut -d' ' -f1 "$L/owner")" == "$$" && "$(cat "$L/owner")" == "$(lock_proc_id $$)" ]] || exit 2   # ID and start time
  ( lock_take "$L" ) && exit 3                       # held by a running process
  lock_release "$L"; [[ ! -e "$L" ]] || exit 4
  # (a) No owner written yet: held for a minute, then stale.
  mkdir "$L"; lock_take "$L" && exit 5
  perl -e '$t = time - 120; utime $t, $t, @ARGV' "$L"
  lock_take "$L" || exit 6
  lock_release "$L"
  # A process that has ended.
  bash -c 'exit 0' & dead=$!; wait "$dead"
  mkdir "$L"; printf '%s Thu Jan  1 00:00:00 1970\n' "$dead" > "$L/owner"
  lock_take "$L" || exit 7
  lock_release "$L"
  # (b) The ID now belongs to another process (a reused PID): stale.
  sleep 30 & other=$!
  mkdir "$L"; printf '%s Thu Jan  1 00:00:00 1970\n' "$other" > "$L/owner"
  lock_take "$L" || exit 8
  lock_release "$L"
  # ...but that same process, with its own start time, holds it, however old.
  mkdir "$L"; lock_proc_id "$other" > "$L/owner"; perl -e '$t = time - 7200; utime $t, $t, @ARGV' "$L"
  lock_take "$L" && exit 9
  [[ "$LOCK_HOLDER" == "$other" ]] || exit 10
  # The older format (a pid file with just the ID) still counts.
  rm -f "$L/owner"; echo "$other" > "$L/pid"; lock_take "$L" && exit 11
  kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
  lock_take "$L" || exit 12
  lock_release "$L"
  # (c) Many takers at once on a stale lock: exactly one wins, every time.
  for round in 1 2 3 4; do
    mkdir "$L"; printf '%s x\n' "$dead" > "$L/owner"; : > "$tmp/locks/won"
    for _ in 1 2 3 4 5 6; do
      bash -c 'source "$1"; lock_take "$2" && echo won >> "$3"; sleep 2' _ "$ROOT/lib/lock.sh" "$L" "$tmp/locks/won" &
    done
    wait
    [[ "$(grep -c won "$tmp/locks/won")" == 1 ]] || exit $((20 + round))
    rm -rf "$L" "$L.break"
  done
  exit 0
) && t_ok "locks: a running holder keeps it, a dead or reused PID or an unwritten owner frees it, and one taker wins" \
  || t_fail "locks (step $?)"

# --- the first-open check comes back on the apps this run installed
(
  export REPO_DIR="$ROOT" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/gk-apps" MDLS_DATES="$tmp/gk-dates"
  mkdir -p "$GRAND_LINE_APPS_DEST" "$MDLS_DATES"
  source "$ROOT/lib/common.sh"; source "$ROOT/steps/02-apps.sh"
  for a in Old Replaced; do mkdir -p "$GRAND_LINE_APPS_DEST/$a.app/Contents"; done
  echo "2020-01-01 00:00:00 +0000" > "$MDLS_DATES/Old.app"
  before="$tmp/gk-before"; apps_now > "$before"; start="$(date +%s)"
  # The installs: Homebrew and pkg payloads keep the app's own (old) times.
  for a in New Approved Flagged; do mkdir -p "$GRAND_LINE_APPS_DEST/$a.app/Contents"; done
  perl -e '$t = time - 400 * 86400; utime $t, $t, @ARGV' "$GRAND_LINE_APPS_DEST"/*.app
  perl -MPOSIX -e 'print strftime("%Y-%m-%d %H:%M:%S +0000", gmtime(time + 5))' > "$MDLS_DATES/Replaced.app"
  : > "$STUB_LOG"
  SPCTL_APPROVED="Approved.app" XATTR_QUARANTINED="Flagged.app" restore_gatekeeper "$before" "$start" >/dev/null
  flagged="$(sed -n 's#^xattr -w com.apple.quarantine [^ ]* .*/\([^/]*\)\.app$#\1#p' "$STUB_LOG" | sort | tr '\n' ' ')"
  [[ "$flagged" == "New Replaced " ]] || { echo "$flagged"; exit 1; }
  exit 0
) && t_ok "the first-open check comes back on apps new to /Applications or added during the run, whatever their modification time" \
  || t_fail "restore_gatekeeper (step $?)" "$(grep xattr "$STUB_LOG")"

# --- app install and remove keep the Brewfile in step
mkdir -p "$HOME/.grand-line/config/grand-line"
printf 'cask "zoom"\ncask "nikitabobko/tap/aerospace"\n' > "$HOME/.grand-line/Brewfile"
printf 'WordCraft\tstorytold/wordcraft\tWord processor\nGridCraft\tstorytold/gridcraft\tSpreadsheets\n' > "$HOME/.grand-line/config/grand-line/artcraft.tsv"
export GRAND_LINE_DETACHED=1 BREW_CASKS="iina zoom" BREW_INSTALLED="zoom aerospace"
answers "iina"; "$ROOT/bin/app" install
grep -qx 'cask "iina"' "$HOME/.grand-line/Brewfile" && t_ok "app install adds the app to the Brewfile" || t_fail "app install did not add to the Brewfile"
"$ROOT/bin/app" install iina; [[ "$(grep -c 'cask "iina"' "$HOME/.grand-line/Brewfile")" == 1 ]] && t_ok "app install never adds a line twice" || t_fail "app install added a duplicate line"
"$ROOT/bin/app" remove aerospace
grep -q aerospace "$HOME/.grand-line/Brewfile" && t_fail "app remove left a tap cask in the Brewfile" || t_ok "app remove takes a tap cask off the Brewfile"
grep -q 'cask "zoom"' "$HOME/.grand-line/Brewfile" && t_ok "app remove leaves other apps alone" || t_fail "app remove touched other lines"
"$ROOT/bin/app" remove "GridCraft (ArtCraft)"
grep -q '^GridCraft' "$HOME/.grand-line/config/grand-line/artcraft.tsv" && t_fail "ArtCraft removal kept its row" || t_ok "app remove takes an ArtCraft app off its list"
grep -q '^WordCraft' "$HOME/.grand-line/config/grand-line/artcraft.tsv" && t_ok "ArtCraft removal leaves other rows" || t_fail "ArtCraft removal touched other rows"
grep -q "brew uninstall --cask aerospace" "$STUB_LOG" && ! grep -q -- "--zap" "$STUB_LOG" && t_ok "app remove keeps the app's data (no --zap)" || t_fail "app remove deleted data"
unset GRAND_LINE_DETACHED BREW_CASKS BREW_INSTALLED

# --- grandline: history, undo, save, restore and experiments, on a scratch repository
r="$tmp/repo"; mkdir -p "$r"; git -C "$r" init -q -b main; git -C "$r" config user.email t@t; git -C "$r" config user.name t
echo one > "$r/a.txt"; git -C "$r" add -A; git -C "$r" commit -q -m "First"
export GRAND_LINE_REPO="$r" GRAND_LINE_NO_APPLY=1
"$ROOT/bin/grandline" save "known good" >/dev/null
echo two > "$r/a.txt"; echo new > "$r/b.txt"; git -C "$r" add -A; git -C "$r" commit -q -m "Second"
hist="$("$ROOT/bin/grandline" history)"; grep -q "Second" <<<"$hist" && t_ok "grandline history lists changes" || t_fail "grandline history"
"$ROOT/bin/grandline" undo >/dev/null; [[ "$(cat "$r/a.txt")" == one && ! -e "$r/b.txt" ]] && t_ok "grandline undo reverses the last change" || t_fail "grandline undo"
"$ROOT/bin/grandline" undo >/dev/null; [[ "$(cat "$r/a.txt")" == two ]] && t_ok "grandline undo can undo an undo" || t_fail "grandline undo of undo"
tag="$(git -C "$r" tag -l 'good-*' | head -1)"
"$ROOT/bin/grandline" restore "$tag" >/dev/null; [[ "$(cat "$r/a.txt")" == one && ! -e "$r/b.txt" ]] && t_ok "grandline restore returns to a saved version, removing later files" || t_fail "grandline restore"
"$ROOT/bin/grandline" try start idea >/dev/null; echo idea > "$r/a.txt"; "$ROOT/bin/grandline" try drop >/dev/null
[[ "$(cat "$r/a.txt")" == one && "$(git -C "$r" branch --show-current)" == main ]] && t_ok "grandline try drop throws an experiment away" || t_fail "grandline try drop"
"$ROOT/bin/grandline" try start better >/dev/null; echo better > "$r/a.txt"; "$ROOT/bin/grandline" try keep >/dev/null
[[ "$(cat "$r/a.txt")" == better && "$(git -C "$r" branch --show-current)" == main ]] && t_ok "grandline try keep keeps an experiment" || t_fail "grandline try keep"
git -C "$r" switch -q -c fixes; "$ROOT/bin/grandline" try start side >/dev/null; echo side > "$r/a.txt"; "$ROOT/bin/grandline" try keep >/dev/null
[[ "$(git -C "$r" branch --show-current)" == fixes && "$(git -C "$r" show main:a.txt)" == better && "$(cat "$r/a.txt")" == side ]] \
  && t_ok "grandline try keep goes back to the branch the experiment came from" || t_fail "grandline try keep on another branch"
git -C "$r" switch -q main
cmds="$("$ROOT/bin/grandline" commands)"
if grep -q "^migrate  *Run the package" <<<"$cmds" && [[ "$(grep -c . <<<"$cmds")" == "$(find "$ROOT/bin" -type f | wc -l | tr -d ' ')" ]] && ! grep -qE '^[^ ]+ *$' <<<"$cmds"; then
  t_ok "grandline commands lists each command with its summary"; else t_fail "grandline commands" "$cmds"; fi
unset GRAND_LINE_REPO GRAND_LINE_NO_APPLY

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
list="$(KEYBINDINGS_FILE="$ROOT/config/grand-line/keybindings.tsv" KEYBINDINGS_LOCAL="$tmp/bindings.local.tsv" "$ROOT/bin/keybindings" --print)"
grep -q "^Caps + Shift + Z .*Zotero" <<<"$list" && ! grep -q "^Caps + X " <<<"$list" && grep -q "My browser" <<<"$list" \
  && t_ok "the shortcut list shows your shortcuts too" || t_fail "shortcut list ignores bindings.local.tsv"

# --- migrations: run once each, in order, stop at a failure
mr="$tmp/mrepo"; mkdir -p "$mr/migrations"
cp -R "$ROOT/lib" "$mr/lib"
printf 'echo first >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000000-first.sh"
printf 'echo second >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000100-second.sh"
export GRAND_LINE_REPO="$mr"
[[ "$("$ROOT/bin/migrate" --pending | tr '\n' ' ')" == "1700000000-first.sh 1700000100-second.sh " ]] && t_ok "migrate --pending lists them in order" || t_fail "pending list"
"$ROOT/bin/migrate" >/dev/null; "$ROOT/bin/migrate" >/dev/null
[[ "$(tr '\n' ' ' < "$tmp/order")" == "first second " ]] && t_ok "migrations run once each, oldest first" || t_fail "migration order" "$(cat "$tmp/order")"
[[ -f "$HOME/.local/state/grand-line/migrations/1700000100-second.sh" ]] && t_ok "migrations leave a marker" || t_fail "no marker"
! "$ROOT/bin/migrate" --pending >/dev/null && t_ok "migrate --pending fails when none are left" || t_fail "pending with none left"
printf 'exit 3\n' > "$mr/migrations/1700000200-broken.sh"; printf 'echo after >> "%s/order"\n' "$tmp" > "$mr/migrations/1700000300-after.sh"
if ! "$ROOT/bin/migrate" >/dev/null 2>&1 && ! grep -q after "$tmp/order" && [[ ! -f "$HOME/.local/state/grand-line/migrations/1700000200-broken.sh" ]]; then
  t_ok "a failed migration stops the run and runs again next time"; else t_fail "failed migration handling"; fi
"$ROOT/bin/migrate" --mark-all
[[ "$("$ROOT/bin/migrate")" == "No one-time changes waiting." ]] && t_ok "migrate says when nothing is waiting" || t_fail "migrate with none waiting"
! "$ROOT/bin/migrate" --pending >/dev/null && ! grep -q after "$tmp/order" && t_ok "migrate --mark-all records all without running them" || t_fail "mark-all"
unset GRAND_LINE_REPO
# The real first migration moves the old Desktop checklist to the Trash.
mkdir -p "$HOME/Desktop"; echo old > "$HOME/Desktop/Finish setup.txt"
GRAND_LINE_REPO="$ROOT" bash "$ROOT/migrations/1793404800-desktop-checklist-to-trash.sh"
[[ ! -e "$HOME/Desktop/Finish setup.txt" && -f "$HOME/.Trash/Finish setup.txt" ]] && t_ok "migration: the old Desktop checklist goes to the Trash" || t_fail "Desktop checklist migration"
GRAND_LINE_REPO="$ROOT" bash "$ROOT/migrations/1793404800-desktop-checklist-to-trash.sh" && t_ok "migration: running it again is harmless" || t_fail "Desktop migration not repeatable"
# The template migration re-applies the current theme, and moves Paper to Daylight.
echo paper > "$HOME/.local/state/grand-line/theme"; rm -rf "$HOME/.local/state/grand-line/current"
GRAND_LINE_REPO="$ROOT" bash "$ROOT/migrations/1793404860-render-theme-templates.sh" >/dev/null 2>&1
[[ "$(cat "$HOME/.local/state/grand-line/theme")" == daylight && -f "$HOME/.local/state/grand-line/current/theme/tmux.conf" ]] \
  && t_ok "migration: the old Paper theme becomes Daylight, rendered from the templates" || t_fail "theme template migration"
rm -f "$HOME/.local/state/grand-line/theme"
GRAND_LINE_REPO="$ROOT" bash "$ROOT/migrations/1793404860-render-theme-templates.sh" && t_ok "migration: with no theme yet it does nothing" || t_fail "theme migration with no theme"
# A fresh install marks every migration done; a Mac with a theme does not.
fh="$tmp/fresh"; mkdir -p "$fh"
plan="$(HOME="$fh" bash "$ROOT/setup.sh" --dry-run --only folders 2>&1)"
grep -q "bin/migrate --mark-all" <<<"$plan" && t_ok "a fresh install marks the migrations done" || t_fail "fresh install marking not planned"
mkdir -p "$fh/.local/state/grand-line"; echo nord > "$fh/.local/state/grand-line/theme"
plan="$(HOME="$fh" bash "$ROOT/setup.sh" --dry-run --only folders 2>&1)"
grep -q "mark-all" <<<"$plan" && t_fail "an existing Mac had its migrations marked" || t_ok "an existing Mac keeps its migrations to run"

# --- hooks: the named file and NAME.d/ in order, never .sample or non-executable
hd="$HOME/.config/grand-line/hooks"; mkdir -p "$hd/theme-set.d"
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
export AEROSPACE_WINDOWS=$'7|Ghostty|~\n9|Zen|Inbox (3) - Gmail'
: > "$STUB_LOG"; "$ROOT/bin/focus-or-open" Ghostty
grep -q "aerospace focus --window-id 7" "$STUB_LOG" && ! grep -q "open -a" "$STUB_LOG" && t_ok "an app key focuses its open window" || t_fail "focus-or-open did not focus" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; "$ROOT/bin/focus-or-open" Notion
grep -q "open -a Notion" "$STUB_LOG" && t_ok "an app key opens an app with no window" || t_fail "focus-or-open did not open"
: > "$STUB_LOG"; "$ROOT/bin/webapp" "https://mail.google.com" "Gmail"
grep -q "aerospace focus --window-id 9" "$STUB_LOG" && ! grep -q "open " "$STUB_LOG" && t_ok "a web app key focuses its open window" || t_fail "webapp did not focus"
: > "$STUB_LOG"; "$ROOT/bin/webapp" "https://www.youtube.com" "YouTube"
grep -q "open " "$STUB_LOG" && t_ok "a web app key opens a window when none matches" || t_fail "webapp did not open"
unset AEROSPACE_WINDOWS
locktmp="$(mktemp -d)"; lock="$locktmp/update.lock"
mkdir "$lock"; echo "$$" > "$lock/pid"
out="$(GRAND_LINE_UPDATE_LOCK="$lock" "$ROOT/bin/update" 2>&1)"
grep -q "Another update is running" <<<"$out" && t_ok "a second update waits for the first" || t_fail "update lock" "$out"
out="$(GRAND_LINE_HOME="$ROOT" GRAND_LINE_UPDATE_LOCK="$lock" bash "$ROOT/setup.sh" --only folders 2>&1)"; code=$?
[[ "$code" == 1 ]] && grep -q "An update or another setup is running" <<<"$out" && t_ok "setup waits while an update runs" || t_fail "setup lock" "$out"
rm -rf "$locktmp"
: > "$STUB_LOG"; "$ROOT/bin/update" --window
grep -q "open -na Ghostty --args -e .*/bin/in-window --run .*/bin/update" "$STUB_LOG" && t_ok "update --window opens its own Ghostty window" || t_fail "update --window" "$(cat "$STUB_LOG")"
code="$("$ROOT/bin/in-window" --run false </dev/null 2>/dev/null; echo "$?")"
[[ "$code" == *"Failed (1)"*1 ]] && t_ok "the window reports a failure with its code" || t_fail "in-window failure" "$code"
[[ "$("$ROOT/bin/in-window" --run bash -c 'echo "$GRAND_LINE_IN_WINDOW"' </dev/null 2>/dev/null | head -1)" == 1 ]] \
  && t_ok "the window tells the command it is in sight" || t_fail "in-window did not set GRAND_LINE_IN_WINDOW"
: > "$STUB_LOG"; "$ROOT/bin/app" install --window zoom
grep -q "open -na Ghostty --args -e .*/bin/in-window --run .*/bin/app install zoom" "$STUB_LOG" \
  && t_ok "app install from the menu works in its own window" || t_fail "app install --window" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; GRAND_LINE_IN_WINDOW=1 "$ROOT/bin/app" install mpv
grep -qx 'cask "mpv"' "$HOME/.grand-line/Brewfile" && grep -q "brew install --cask mpv" "$STUB_LOG" \
  && t_ok "app install in a window runs there, not in the background" || t_fail "app install in a window"

# --- toggle states: flag files and the current theme
# shellcheck source=lib/toggle-state.sh
source "$ROOT/lib/toggle-state.sh"
flag docker on; is_on docker && t_ok "a toggle flag reads as on" || t_fail "flag on"
flag docker off; ! is_on docker && t_ok "a cleared toggle flag reads as off" || t_fail "flag off"
echo "{ sec = 1" > "$TOGGLE_FLAGS/docker"; ! is_on docker && t_ok "a Docker flag from before the last restart reads as off" || t_fail "stale Docker flag read as on"
flag docker off
! is_on no-such-toggle && t_ok "an unknown toggle reads as off" || t_fail "unknown toggle"
echo forest > "$HOME/.local/state/grand-line/theme"
theme_is forest && ! theme_is nord && t_ok "theme_is matches only the current theme" || t_fail "theme_is"

# --- toggle: explicit on and off, new settings, and the status Sight reads
T="$ROOT/bin/toggle"
: > "$STUB_LOG"; WIFI_POWER=On "$T" wifi off
grep -q "networksetup -setairportpower en0 off" "$STUB_LOG" && t_ok "toggle wifi off turns Wi-Fi off on the cached device" || t_fail "toggle wifi off" "$(cat "$STUB_LOG")"
[[ "$(cat "$TOGGLE_FLAGS/.wifi-device" 2>/dev/null)" == en0 ]] && t_ok "the Wi-Fi device is looked up once and cached" || t_fail "wifi device cache"
: > "$STUB_LOG"; WIFI_POWER=On "$T" wifi on
! grep -q "setairportpower" "$STUB_LOG" && t_ok "toggle wifi on leaves Wi-Fi alone when it is already on" || t_fail "wifi on when on" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; WIFI_POWER=Off "$T" wifi
grep -q "networksetup -setairportpower en0 on" "$STUB_LOG" && t_ok "toggle wifi with no state flips it" || t_fail "wifi flip"
: > "$STUB_LOG"; BLUEUTIL_POWER=1 "$T" bluetooth off
grep -q "blueutil -p 0" "$STUB_LOG" && t_ok "toggle bluetooth off" || t_fail "bluetooth off" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; BLUEUTIL_POWER=0 "$T" bluetooth off
! grep -q "blueutil -p 0" "$STUB_LOG" && t_ok "toggle bluetooth off does nothing when already off" || t_fail "bluetooth off when off"
: > "$STUB_LOG"; "$T" volume 30
grep -q "osascript -e set volume output volume 30 without output muted" "$STUB_LOG" && t_ok "toggle volume 30 sets the level and unmutes" || t_fail "volume 30" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; OSASCRIPT_REPLY=95 "$T" volume up
grep -q "output volume 100 without" "$STUB_LOG" && t_ok "toggle volume up steps by 10 and stops at 100" || t_fail "volume up" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; OSASCRIPT_REPLY=40 "$T" volume down
grep -q "output volume 30 without" "$STUB_LOG" && t_ok "toggle volume down steps by 10" || t_fail "volume down"
"$T" volume 'x; rm -rf /' >/dev/null 2>&1; [[ $? == 2 ]] && t_ok "toggle volume refuses anything but a number" || t_fail "volume accepted junk"
"$T" wifi sideways >/dev/null 2>&1; [[ $? == 2 ]] && t_ok "toggle refuses a state other than on or off" || t_fail "bad state accepted"
: > "$STUB_LOG"; OSASCRIPT_REPLY=false "$T" mute
grep -q "osascript -e set volume with output muted" "$STUB_LOG" && t_ok "toggle mute mutes the sound" || t_fail "mute" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; OSASCRIPT_REPLY=true "$T" mute off
grep -q "set volume without output muted" "$STUB_LOG" && t_ok "toggle mute off unmutes" || t_fail "unmute"
: > "$STUB_LOG"; printf 'Finder\n' > "$tmp/running-finder"; STUB_RUNNING="$tmp/running-finder" "$T" hidden on
grep -q "defaults write com.apple.finder AppleShowAllFiles -bool true" "$STUB_LOG" && grep -q "killall Finder" "$STUB_LOG" \
  && t_ok "toggle hidden on shows hidden files and restarts Finder" || t_fail "hidden on" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; STUB_RUNNING=/dev/null "$T" hidden on
grep -q "defaults write com.apple.finder AppleShowAllFiles -bool true" "$STUB_LOG" && ! grep -q "killall Finder" "$STUB_LOG" \
  && t_ok "toggle hidden on with Finder closed writes the setting and restarts nothing" || t_fail "hidden on, Finder closed" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; "$T" dock off
grep -q "defaults write com.apple.dock autohide -bool true" "$STUB_LOG" && t_ok "toggle dock off hides the Dock automatically" || t_fail "dock off"
# Dark mode is macOS's appearance (System Events), read back from AppleInterfaceStyle.
export STUB_APPEARANCE="$tmp/appearance"; : > "$STUB_APPEARANCE"
echo harbour-light > "$HOME/.local/state/grand-line/theme"; rm -f "$HOME/.local/state/grand-line/theme-follows-macos"
: > "$STUB_LOG"; GRAND_LINE_QUIET=1 "$T" dark on >/dev/null; code=$?
[[ $code == 0 && "$(cat "$STUB_APPEARANCE")" == Dark ]] && grep -q "set dark mode to true" "$STUB_LOG" \
  && [[ "$(cat "$HOME/.local/state/grand-line/theme")" == harbour-light ]] \
  && t_ok "toggle dark on sets the macOS appearance and leaves a theme that does not follow macOS" || t_fail "dark on" "$code $(cat "$STUB_LOG")"
"$T" status dark | grep -qx "dark on" && t_ok "toggle status reads dark mode from AppleInterfaceStyle" || t_fail "status dark after dark on"
: > "$STUB_LOG"; GRAND_LINE_QUIET=1 "$T" dark on >/dev/null
! grep -q "set dark mode" "$STUB_LOG" && t_ok "toggle dark on leaves the appearance alone when it is already dark" || t_fail "dark on when dark" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; GRAND_LINE_QUIET=1 "$T" dark >/dev/null; code=$?
[[ $code == 0 && ! -s "$STUB_APPEARANCE" ]] && grep -q "set dark mode to false" "$STUB_LOG" \
  && t_ok "toggle dark with no state switches back to light" || t_fail "dark flip" "$code $(cat "$STUB_LOG")"
# While the theme follows macOS, its variant switches with the appearance.
touch "$HOME/.local/state/grand-line/theme-follows-macos"
: > "$STUB_LOG"; GRAND_LINE_QUIET=1 GRAND_LINE_TEST_PATH="$GRAND_LINE_TEST_PATH:$ROOT/bin" "$T" dark on >/dev/null; code=$?
[[ $code == 0 && "$(cat "$STUB_APPEARANCE")" == Dark && "$(cat "$HOME/.local/state/grand-line/theme")" == harbour-dark ]] \
  && t_ok "toggle dark on switches a theme that follows macOS to its dark variant" || t_fail "dark on following macOS" "$code $(cat "$HOME/.local/state/grand-line/theme")"
: > "$STUB_LOG"; GRAND_LINE_QUIET=1 GRAND_LINE_TEST_PATH="$GRAND_LINE_TEST_PATH:$ROOT/bin" "$T" dark off >/dev/null; code=$?
[[ $code == 0 && ! -s "$STUB_APPEARANCE" && "$(cat "$HOME/.local/state/grand-line/theme")" == harbour-light ]] \
  && t_ok "toggle dark off switches it back to its light variant" || t_fail "dark off following macOS" "$code $(cat "$HOME/.local/state/grand-line/theme")"
rm -f "$HOME/.local/state/grand-line/theme-follows-macos"
# System Events answered but macOS kept its appearance: a failure, never a success.
out="$(STUB_APPEARANCE_STUCK=1 GRAND_LINE_QUIET=1 "$T" dark on)"; code=$?
[[ $code == 1 && "$out" == *"kept the light appearance"* ]] && t_ok "toggle dark fails when the appearance did not change" || t_fail "dark readback" "$code $out"
out="$(OSASCRIPT_FAIL="execution error: Not authorized to send Apple events to System Events. (-1743)" GRAND_LINE_QUIET=1 "$T" dark on)"; code=$?
[[ $code == 3 && "$out" == *Automation* && ! -s "$STUB_APPEARANCE" ]] && t_ok "a missing Automation permission exits 3 and says so" || t_fail "automation failure" "$code $out"
unset STUB_APPEARANCE
out="$(GRAND_LINE_QUIET=1 SHORTCUTS_LIST="" "$T" dnd on)"; code=$?
[[ $code == 4 && "$out" == *"Do Not Disturb On"* ]] && t_ok "Do Not Disturb without its shortcut exits 4 and names it" || t_fail "dnd missing shortcut" "$code $out"
: > "$STUB_LOG"; SHORTCUTS_LIST=$'Do Not Disturb On\nDo Not Disturb Off' "$T" dnd on
grep -q "shortcuts run Do Not Disturb On" "$STUB_LOG" && is_on dnd && t_ok "toggle dnd on runs its shortcut and remembers the state" || t_fail "dnd on" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"; SHORTCUTS_LIST=$'Do Not Disturb On\nDo Not Disturb Off' "$T" dnd
grep -q "shortcuts run Do Not Disturb Off" "$STUB_LOG" && ! is_on dnd && t_ok "toggle dnd flips it back off" || t_fail "dnd flip off"
status="$(WIFI_POWER=On BLUEUTIL_POWER=0 OSASCRIPT_REPLY=40 "$T" status)"
grep -qx "wifi on" <<<"$status" && grep -qx "bluetooth off" <<<"$status" && grep -qx "volume 40" <<<"$status" \
  && grep -qx "dark off" <<<"$status" && grep -qx "hidden off" <<<"$status" \
  && t_ok "toggle status prints every setting's state and the volume" || t_fail "toggle status" "$status"
[[ "$(WIFI_POWER=Off "$T" status wifi)" == "wifi off" ]] && t_ok "toggle status NAME reads only that setting" || t_fail "status wifi"
: > "$STUB_LOG"; "$ROOT/bin/power" display-sleep && grep -q "pmset displaysleepnow" "$STUB_LOG" && t_ok "power display-sleep" || t_fail "power display-sleep"
"$ROOT/bin/power" reboot-now >/dev/null 2>&1; [[ $? == 2 ]] && t_ok "power refuses an unknown action" || t_fail "power unknown"

# --- personal details: read from personal.env, never asked without a keyboard
# shellcheck source=lib/personal.sh
source "$ROOT/lib/personal.sh"
source "$ROOT/lib/trash.sh"
PERSONAL_FILE="$HOME/.config/grand-line/personal.env"; rm -f "$PERSONAL_FILE"
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

# --- gl is grandline
out="$("$ROOT/bin/gl" commands 2>&1)"
grep -q "^grandline " <<<"$out" && ! grep -q "^gl " <<<"$out" && t_ok "gl runs grandline, and the command list shows it once" || t_fail "gl" "$out"

# --- the package's own apps: built, wrapped in a bundle, old copy to the Trash
apps_root="$tmp/apps-repo"; mkdir -p "$apps_root/apps/demo/Sources" "$apps_root/apps/demo/Info" "$apps_root/apps/demo/Resources/Demo" "$tmp/bin-apps" "$tmp/Applications"
printf 'Demo\tDemo App\tcom.example.demo\tyes\n# comment\n' > "$apps_root/apps/demo/apps.tsv"
echo '// app' > "$apps_root/apps/demo/Sources/main.swift"
printf '<key>NSAppleEventsUsageDescription</key><string>Opens folders.</string>\n' > "$apps_root/apps/demo/Info/Demo.plist"
echo icon > "$apps_root/apps/demo/Resources/Demo/AppIcon.icns"
cat > "$tmp/bin-apps/swift" <<'EOF'
#!/bin/bash
echo "swift $*" >> "$STUB_LOG"
args="$*"; pp="${args#*--package-path }"; dir="${pp%% *}"; mkdir -p "$dir/.build/release"
printf '#!/bin/sh\necho built\n' > "$dir/.build/release/Demo"; chmod +x "$dir/.build/release/Demo"
[[ "$args" == *"--product DemoLib"* ]] && echo lib > "$dir/.build/release/libDemoLib.dylib"
exit 0
EOF
chmod +x "$tmp/bin-apps/"*
(
  export PATH="$tmp/bin-apps:$PATH" REPO_DIR="$apps_root" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/Applications"
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  build_native_apps >/dev/null 2>&1 || exit 1
  app="$tmp/Applications/Demo App.app"
  [[ -x "$app/Contents/MacOS/Demo" && -f "$app/Contents/Resources/AppIcon.icns" ]] || exit 2
  grep -q '<key>CFBundleIdentifier</key><string>com.example.demo</string>' "$app/Contents/Info.plist" || exit 3
  grep -q 'LSUIElement' "$app/Contents/Info.plist" && grep -q NSAppleEventsUsageDescription "$app/Contents/Info.plist" || exit 4
  : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1
  grep -q "^swift " "$STUB_LOG" && exit 5          # nothing changed, so no rebuild
  touch "$apps_root/apps/demo/Sources/main.swift"; : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1
  grep -q "^swift " "$STUB_LOG" && exit 11         # touched, not changed: no rebuild
  echo '// v2' >> "$apps_root/apps/demo/Sources/main.swift"; build_native_apps >/dev/null 2>&1
  compgen -G "$HOME/.Trash/Demo App*" >/dev/null || exit 6  # the old copy went to the Trash
  [[ -x "$app/Contents/MacOS/Demo" ]] || exit 7
  sleep 1; printf 'DemoLib\tDemoKit\n' > "$apps_root/apps/demo/frameworks.tsv"; : > "$STUB_LOG"
  build_native_apps >/dev/null 2>&1 || exit 8
  grep -q -- "--product DemoLib" "$STUB_LOG" || exit 9
  fw="$app/Contents/Frameworks/DemoKit.framework"
  [[ -f "$fw/Versions/A/DemoKit" && -L "$fw/DemoKit" ]] && grep -q "com.example.demo.DemoKit" "$fw/Versions/A/Resources/Info.plist" || exit 10
  # A deleted source file is a change too.
  echo '// extra' > "$apps_root/apps/demo/Sources/extra.swift"; build_native_apps >/dev/null 2>&1
  rm "$apps_root/apps/demo/Sources/extra.swift"; : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1
  grep -q "^swift " "$STUB_LOG" || exit 12
  # When the old copy cannot go to the Trash, it stays as it was and nothing
  # is put inside it; the run fails, so the next one tries again.
  echo old > "$app/Contents/marker"
  move_to_trash() { return 1; }
  echo '// v3' >> "$apps_root/apps/demo/Sources/main.swift"
  build_native_apps >/dev/null 2>&1 && exit 13
  [[ "$(cat "$app/Contents/marker")" == old && -z "$(find "$app" -name '*.app*' -mindepth 1)" ]] || exit 14
  [[ ! -e "$tmp/Applications/.Demo App.app.new" ]] || exit 15
  : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1; grep -q "^swift " "$STUB_LOG" || exit 16   # tried again
  # The same for a copy left waiting.
  mkdir -p "$tmp/Applications/.Demo App.app.staged/Contents"; echo staged > "$tmp/Applications/.Demo App.app.staged/Contents/marker"
  pgrep() { return 1; }
  apply_staged_apps >/dev/null 2>&1
  [[ "$(cat "$app/Contents/marker")" == old && -d "$tmp/Applications/.Demo App.app.staged" && -z "$(find "$app" -name '*.app*' -mindepth 1)" ]] || exit 17
  unset -f move_to_trash pgrep; source "$ROOT/lib/trash.sh"
  apply_staged_apps >/dev/null 2>&1
  [[ "$(cat "$app/Contents/marker")" == staged && ! -e "$tmp/Applications/.Demo App.app.staged" ]] || exit 18
  build_native_apps >/dev/null 2>&1 && [[ -x "$app/Contents/MacOS/Demo" ]] || exit 19
) && t_ok "own apps are built, bundled, signed, rebuilt on any change (a deletion too), old copy trashed or kept whole" || t_fail "native apps (step $?)"

# --- Nexus and Sight take over Finder and Spotlight, and switch back
(
  export GRAND_LINE_APPS_DEST="$tmp/Applications" GRAND_LINE_STATE="$HOME/.local/state/grand-line"
  mkdir -p "$tmp/Applications/Nexus.app" "$tmp/Applications/Sight.app"
  source "$ROOT/lib/default-apps.sh"; source "$ROOT/lib/takeover.sh"; source "$ROOT/lib/toggle-state.sh"
  [[ "$(takeover_mode files)" == on && "$(takeover_mode search)" == on ]] || exit 1   # on by default
  : > "$STUB_LOG"; takeover_files on
  grep -q "defaults write -g NSFileViewer -string com.grandline.nexus" "$STUB_LOG" && grep -q "public.folder.*com.grandline.nexus" "$STUB_LOG" || exit 2
  : > "$STUB_LOG"; takeover_files off
  grep -q "defaults delete -g NSFileViewer" "$STUB_LOG" && grep -q "public.folder.*com.apple.finder" "$STUB_LOG" || exit 3
  ! is_on files || exit 4
  : > "$STUB_LOG"; takeover_search on
  grep -q "AppleSymbolicHotKeys -dict-add 64 <dict><key>enabled</key><false/>" "$STUB_LOG" && grep -q "com.grandline.sight TakesCommandSpace -bool true" "$STUB_LOG" || exit 5
  : > "$STUB_LOG"; takeover_search off
  grep -q "<key>enabled</key><true/>" "$STUB_LOG" && grep -q "TakesCommandSpace -bool false" "$STUB_LOG" || exit 6
  rmdir "$tmp/Applications/Nexus.app"; ! takeover_files on || exit 7   # nothing to switch to
) && t_ok "Nexus and Sight take over Finder and Spotlight by default, and switch back" || t_fail "takeover (step $?)"

# --- the selection comes from Nexus when it is in front
mkdir -p "$HOME/.local/state/grand-line"; printf '/Users/me/a.pdf\n/Users/me/b c.pdf\n' > "$HOME/.local/state/grand-line/nexus-selection"
got="$(FRONT_APP=com.grandline.nexus bash -c 'source "$1/lib/bin-common.sh"; finder_selection' _ "$ROOT")"
[[ "$got" == $'/Users/me/a.pdf\n/Users/me/b c.pdf' ]] && t_ok "the selection comes from Nexus when it is in front" || t_fail "Nexus selection" "$got"

# --- the rename: Log Pose, Byakugan and Den Den become Nexus, Sight and Iceberg
rn="$tmp/rename"
rename_env() {
  export HOME="$rn/$1" GRAND_LINE_APPS_DEST="$rn/$1/Applications" STUB_DEFAULTS="$rn/$1/defaults" STUB_RUNNING="$rn/$1/running"
  mkdir -p "$HOME" "$GRAND_LINE_APPS_DEST"
}
rename_run() { GRAND_LINE_REPO="$ROOT" bash "$ROOT/migrations/1793472900-rename-apps.sh" > "$rn/out" 2>&1; }
# logged CMD: the stub log has CMD, allowing a moment for background launches.
logged() { local _; for _ in 1 2 3 4 5 6 7 8 9 10; do grep -qF -- "$1" "$STUB_LOG" && return 0; sleep 0.2; done; return 1; }
(
  rename_env fresh
  mkdir -p "$GRAND_LINE_APPS_DEST/Nexus.app" "$GRAND_LINE_APPS_DEST/Sight.app" "$GRAND_LINE_APPS_DEST/Iceberg.app"
  : > "$STUB_LOG"; rename_run || exit 1
  [[ -z "$(find "$HOME" -mindepth 1 -not -path "$HOME/Applications*" -not -path "$HOME/.local*" -print)" ]] || exit 2
  [[ -z "$(find "$HOME/.local" -type f 2>/dev/null)" && ! -d "$STUB_DEFAULTS" ]] || exit 3
  grep -qE '^(defaults (write|import|delete)|pkill|open) ' "$STUB_LOG" && exit 4
  [[ ! -s "$rn/out" ]] || exit 5
  exit 0
) && t_ok "rename migration: a fresh install has nothing to move and nothing changes" || t_fail "rename migration on a fresh install (step $?)" "$(cat "$rn/out" 2>/dev/null)"
(
  rename_env old
  A="$GRAND_LINE_APPS_DEST"; sup="$HOME/Library/Application Support"; cfg="$HOME/.config/grand-line"; st="$HOME/.local/state/grand-line"
  for app in Nexus Sight Iceberg "Log Pose" Byakugan "Den Den"; do mkdir -p "$A/$app.app/Contents"; done
  printf 'LogPose\nByakugan\nDenDen\n' > "$STUB_RUNNING"
  mkdir -p "$sup/Log Pose/Workspaces" "$sup/Byakugan" "$sup/Den Den" "$cfg/logpose" "$cfg/byakugan" "$cfg/denden/widgets" "$st" "$HOME/Library/Logs/grand-line" "$STUB_DEFAULTS"
  echo index > "$sup/Log Pose/name-index.snapshot"; echo names > "$sup/Byakugan/names.index"; echo usage > "$sup/Byakugan/usage.json"
  echo '{"places":["~/Drive"]}' > "$cfg/logpose/settings.json"; printf 'g\tgoogle\n' > "$cfg/byakugan/aliases.tsv"
  printf '# mine\nopen_on = "click"\n' > "$cfg/denden/denden.toml"
  printf 'command = "echo $GRAND_LINE_DENDEN_THEME"\n' > "$cfg/denden/widgets/theme.toml"
  printf '/Users/me/a.pdf\n' > "$st/logpose-selection"; echo off > "$st/takeover-files"
  echo log > "$HOME/Library/Logs/grand-line/denden.log"
  printf '<dict>\n<key>CloseAfterSettingChange</key><true/>\n<key>TakesCommandSpace</key><true/>\n</dict>\n' > "$STUB_DEFAULTS/com.grandline.byakugan.plist"
  printf '<dict>\n<key>NSWindow Frame LogPoseBrowser</key><string>0 0 800 600</string>\n</dict>\n' > "$STUB_DEFAULTS/com.grandline.logpose.plist"
  # setup already gave Sight its takeover setting, which must not stop the copy
  printf '<dict>\n<key>TakesCommandSpace</key><true/>\n</dict>\n' > "$STUB_DEFAULTS/com.grandline.sight.plist"
  : > "$STUB_LOG"; rename_run || exit 1
  for app in "Log Pose" Byakugan "Den Den"; do [[ ! -e "$A/$app.app" && -d "$HOME/.Trash/$app.app" ]] || exit 2; done
  [[ -d "$A/Nexus.app" && -d "$A/Sight.app" && -d "$A/Iceberg.app" ]] || exit 3
  [[ "$(cat "$sup/Nexus/name-index.snapshot")" == index && -d "$sup/Nexus/Workspaces" && ! -e "$sup/Log Pose" ]] || exit 4
  [[ "$(cat "$sup/Sight/names.index")" == names && -f "$sup/Sight/usage.json" && ! -e "$sup/Byakugan" && -d "$sup/Iceberg" ]] || exit 5
  [[ -f "$cfg/nexus/settings.json" && -f "$cfg/sight/aliases.tsv" && ! -e "$cfg/logpose" && ! -e "$cfg/byakugan" ]] || exit 6
  [[ "$(head -1 "$cfg/iceberg/iceberg.toml")" == "# mine" && ! -e "$cfg/iceberg/denden.toml" && -f "$cfg/iceberg/widgets/theme.toml" && ! -e "$cfg/denden" ]] || exit 7
  [[ -f "$st/nexus-selection" && ! -e "$st/logpose-selection" && -f "$HOME/Library/Logs/grand-line/iceberg.log" ]] || exit 8
  grep -q CloseAfterSettingChange "$STUB_DEFAULTS/com.grandline.sight.plist" || exit 9
  grep -q 'NSWindow Frame NexusBrowser' "$STUB_DEFAULTS/com.grandline.nexus.plist" && ! grep -q LogPoseBrowser "$STUB_DEFAULTS/com.grandline.nexus.plist" || exit 10
  grep -qF "defaults write com.grandline.byakugan TakesCommandSpace -bool false" "$STUB_LOG" || exit 11
  [[ ! -s "$STUB_RUNNING" ]] && grep -qF "pkill -x DenDen" "$STUB_LOG" || exit 12     # the old apps were stopped first
  # files stay with Finder as chosen; Command + Space goes to Sight
  # (takeover changes nothing when folders already open in Finder, as on a
  # macOS runner, so either the switch back is logged or nothing names Nexus)
  [[ "$(cat "$st/takeover-files")" == off ]] || exit 13
  if ! { grep -qF "defaults delete -g NSFileViewer" "$STUB_LOG" && grep -q "public.folder.*com.apple.finder" "$STUB_LOG"; }; then
    grep -q "NSFileViewer.*com.grandline.nexus\|public.folder.*com.grandline.nexus" "$STUB_LOG" && exit 13
  fi
  grep -qF "defaults write com.grandline.sight TakesCommandSpace -bool true" "$STUB_LOG" || exit 14
  grep -q "zen" "$STUB_LOG" && exit 15                                                  # the default browser is left alone
  logged "open -g -b com.grandline.iceberg" && logged "open -g -b com.grandline.nexus" && logged "open -g -b com.grandline.sight" || exit 16
  grep -q "widgets/theme.toml" "$rn/out" && grep -q "Login Items still lists Log Pose, Byakugan, Den Den" "$rn/out" || exit 17
  # Again: nothing left to do, so nothing changes
  : > "$STUB_LOG"; trash="$(ls "$HOME/.Trash" | wc -l)"; rename_run || exit 18
  grep -qE '^(defaults (write|import|delete)|pkill|open|mv) ' "$STUB_LOG" && exit 19
  [[ "$(ls "$HOME/.Trash" | wc -l)" == "$trash" && "$(cat "$sup/Sight/names.index")" == names && ! -s "$rn/out" ]] || exit 20
  exit 0
) && t_ok "rename migration: settings, index and state move to the new apps, old apps go to the Trash, takeovers follow, and a second run changes nothing" \
  || t_fail "rename migration on an existing Mac (step $?)" "$(cat "$rn/out" 2>/dev/null)"
(
  rename_env waiting
  A="$GRAND_LINE_APPS_DEST"; sup="$HOME/Library/Application Support"; cfg="$HOME/.config/grand-line"
  mkdir -p "$A/Log Pose.app" "$A/Den Den.app" "$A/Iceberg.app" "$sup/Log Pose" "$cfg/denden" "$cfg/iceberg"
  echo keep > "$cfg/denden/denden.toml"
  : > "$STUB_LOG"; rename_run || exit 1
  [[ -d "$A/Log Pose.app" && -d "$sup/Log Pose" && ! -e "$sup/Nexus" ]] || exit 2       # no Nexus yet: Log Pose stays
  grep -q "Nexus is not installed yet" "$rn/out" || exit 3
  grep -qF "NSFileViewer" "$STUB_LOG" && exit 4
  [[ -f "$cfg/denden/denden.toml" && ! -e "$cfg/iceberg/iceberg.toml" ]] || exit 5      # an existing new folder is never overwritten
  grep -q "Kept both" "$rn/out" || exit 6
  exit 0
) && t_ok "rename migration: an old app stays until its replacement is installed, and new folders are never overwritten" \
  || t_fail "rename migration with a missing new app (step $?)" "$(cat "$rn/out" 2>/dev/null)"

# --- the default browser: links, https and web pages, written for LaunchServices
(
  source "$ROOT/lib/default-apps.sh"
  : > "$STUB_LOG"; set_default_browser app.zen-browser.zen
  for k in "LSHandlerURLScheme=\"http\"" "LSHandlerURLScheme=\"https\"" "LSHandlerContentType=\"public.html\"" "LSHandlerContentType=\"public.xhtml\""; do
    grep -qF "$k;LSHandlerRoleAll=\"app.zen-browser.zen\"" "$STUB_LOG" || { echo "missing $k"; exit 1; }
  done
) && t_ok "the default browser takes links and web pages" || t_fail "default browser" "$(cat "$STUB_LOG")"

# --- signing: a stable identity, hardened runtime, permissions kept across rebuilds
(
  export PATH="$tmp/bin-apps:$PATH" REPO_DIR="$apps_root" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/Applications"
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  app="$tmp/Applications/Demo App.app"
  # No identity: ad hoc, but always with hardened runtime.
  : > "$STUB_LOG"; touch "$apps_root/apps/demo/Sources/main.swift"; rm -f "$GRAND_LINE_STATE/built-demo"
  build_native_apps >/dev/null 2>&1 || exit 1
  grep -q "^codesign --force --options runtime --sign - .*\.Demo App\.app\.new$" "$STUB_LOG" || exit 2
  grep -q "^codesign --force --options runtime --sign - .*DemoKit.framework/Versions/A$" "$STUB_LOG" || exit 3
  signing_check "$app" >/dev/null || exit 4
  # The identity, made once: passwords only ever on security's standard input.
  export STUB_SECURITY="$tmp/sec" GRAND_LINE_SIGN_KEYCHAIN="$tmp/kc/grand-line-signing.keychain-db"
  SIGN_KEYCHAIN="$GRAND_LINE_SIGN_KEYCHAIN"
  : > "$STUB_LOG"; signing_ensure >/dev/null 2>&1 || exit 5
  [[ -f "$GRAND_LINE_SIGN_KEYCHAIN" && -f "$STUB_SECURITY/imported" && -f "$STUB_SECURITY/partition" ]] || exit 6
  pw="$(cat "$STUB_SECURITY/password")"; [[ ${#pw} -ge 32 ]] || exit 7
  grep -v "^security -i: " "$STUB_LOG" | grep -qF "$pw" && exit 8
  grep -q "^security -i: import" "$STUB_LOG" && grep -q "^security set-keychain-settings -l -u -t 300" "$STUB_LOG" || exit 9
  : > "$STUB_LOG"; signing_ensure >/dev/null 2>&1 || exit 10
  grep -q "security -i: create-keychain" "$STUB_LOG" && exit 11   # never made twice
  # Signed with it: the requirement pins the certificate, the entitlements go in.
  mkdir -p "$apps_root/apps/demo/Entitlements"; printf '<plist><dict/></plist>\n' > "$apps_root/apps/demo/Entitlements/Demo.entitlements"
  : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1 || exit 12
  grep -q -- "--entitlements $apps_root/apps/demo/Entitlements/Demo.entitlements" "$STUB_LOG" || exit 13
  grep -qF -- '--sign 0123456789ABCDEF0123456789ABCDEF01234567 -r =designated => identifier "com.example.demo" and certificate leaf = H"0123456789abcdef0123456789abcdef01234567"' "$STUB_LOG" || exit 14
  grep -q "^security lock-keychain" "$STUB_LOG" || exit 15
  [[ "$(signing_check "$app")" == "" ]] || exit 16
  codesign -d -r- "$app" 2>&1 | grep -q 'certificate leaf = H"0123456789abcdef' || exit 17
  # A bundle signed some other way is refused, and the installed copy kept.
  codesign --force --sign - "$app" 2>/dev/null
  signing_check "$app" >/dev/null && exit 18
  exit 0
) && t_ok "apps are signed with hardened runtime by one identity made once, passwords never on a command line" \
  || t_fail "signing (step $?)" "$(tail -5 "$STUB_LOG")"

# An identity macOS will not sign with (its certificate is not trusted for code
# signing, as on a test machine): never tried, one warning for the run, the
# apps signed ad hoc on every run, an installed copy signed with it kept.
(
  export PATH="$tmp/bin-apps:$PATH" REPO_DIR="$apps_root" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/UntrustedApps"
  export STUB_SECURITY="$tmp/sec-untrusted" GRAND_LINE_SIGN_KEYCHAIN="$tmp/kc-untrusted/grand-line-signing.keychain-db"
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  SIGN_KEYCHAIN="$GRAND_LINE_SIGN_KEYCHAIN"; mkdir -p "$GRAND_LINE_APPS_DEST"
  signing_ensure >/dev/null 2>&1 && signing_identity >/dev/null || exit 1
  : > "$STUB_SECURITY/untrusted"
  app="$GRAND_LINE_APPS_DEST/Demo App.app"; stamp="$GRAND_LINE_STATE/built-demo"
  # Two runs' worth of builds in one shell: the first installs, the second
  # replaces that ad hoc copy (it once failed: an installed copy existed).
  : > "$STUB_LOG"; rm -f "$stamp"
  out="$(build_native_apps 2>&1 || echo FAILED1; rm -f "$stamp"; echo '// again' >> "$apps_root/apps/demo/Sources/main.swift"
         build_native_apps 2>&1 || echo FAILED2)"
  grep -q FAILED <<<"$out" && { echo "$out"; exit 2; }
  [[ "$(grep -c "is not trusted for code signing" <<<"$out")" == 1 ]] || { echo "$out"; exit 3; }   # once, not per app
  grep -q -- "--sign 0123456789ABCDEF" "$STUB_LOG" && exit 4                                       # never tried
  [[ "$(grep -c "^codesign --force --options runtime .*--sign - .*\.Demo App\.app\.new$" "$STUB_LOG")" == 2 ]] || exit 5
  grep -q "Could not sign" <<<"$out" && exit 6
  code_is_adhoc "$app" && signing_check "$app" >/dev/null || exit 7
  # A copy signed with the identity (by a macOS that signed with it untrusted)
  # is not replaced by an ad hoc one: the identity is tried for it, and when
  # it cannot sign, that copy is kept and the next run tries again.
  STUB_SIGNS_UNTRUSTED=1 codesign --force --options runtime --sign 0123456789ABCDEF0123456789ABCDEF01234567 "$app" 2>/dev/null
  rm -f "$stamp"; echo '// v3' >> "$apps_root/apps/demo/Sources/main.swift"; : > "$STUB_LOG"
  out="$(build_native_apps 2>&1)" || { echo "$out"; exit 8; }
  grep -q "Kept the installed Demo App" <<<"$out" || exit 9
  code_is_adhoc "$app" && exit 10
  [[ -f "$stamp" ]] && exit 11
  grep -q "^codesign --force .*--sign - " "$STUB_LOG" && exit 12
  compgen -G "$GRAND_LINE_APPS_DEST/.Demo App.app.*" >/dev/null && exit 15
  # Where macOS still signs with it untrusted, that copy is replaced as usual.
  : > "$STUB_LOG"; out="$(STUB_SIGNS_UNTRUSTED=1 build_native_apps 2>&1)" || { echo "$out"; exit 16; }
  grep -q "Kept the installed" <<<"$out" && exit 17
  codesign -d -r- "$app" 2>&1 | grep -q 'certificate leaf = H"0123456789abcdef' && [[ -f "$stamp" ]] || exit 18
  rm -f "$stamp"
  # Trusted again: signed with the identity.
  rm -f "$STUB_SECURITY/untrusted"; SIGN_USABLE_FOR=""
  : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1 || exit 13
  grep -qF -- '--sign 0123456789ABCDEF0123456789ABCDEF01234567 -r =designated' "$STUB_LOG" && [[ -f "$stamp" ]] || exit 14
  exit 0
) && t_ok "an identity that cannot sign is not tried: one warning, the apps signed ad hoc on every run, a copy signed with it kept" \
  || t_fail "untrusted signing identity (step $?)" "$(tail -5 "$STUB_LOG")"

# The helpers in step 09 the same way: not signed with it, the step not failed.
(
  trepo="$tmp/tools-repo"; mkdir -p "$trepo/tools" "$tmp/bin-tools" "$tmp/ToolsApps"
  echo '// hello' > "$trepo/tools/hello.swift"; ln -sfn "$ROOT/migrations" "$trepo/migrations"; ln -sfn "$ROOT/lib" "$trepo/lib"
  printf '%s\n' '#!/bin/bash' 'echo "swiftc $*" >> "$STUB_LOG"' 'out="${!#}"; printf "#!/bin/sh\n" > "$out"; chmod +x "$out"' > "$tmp/bin-tools/swiftc"
  chmod +x "$tmp/bin-tools/swiftc"
  export PATH="$tmp/bin-tools:$PATH" REPO_DIR="$trepo" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/ToolsApps"
  export STUB_SECURITY="$tmp/sec-untrusted" GRAND_LINE_SIGN_KEYCHAIN="$tmp/kc-untrusted/grand-line-signing.keychain-db"
  source "$ROOT/lib/common.sh"; source "$ROOT/steps/09-native-tools.sh"
  : > "$STUB_SECURITY/untrusted"; : > "$STUB_LOG"
  out="$(step_native_tools 2>&1)" || { echo "$out"; exit 1; }
  [[ -x "$trepo/.build/hello" ]] || exit 2
  grep -q "^codesign" "$STUB_LOG" && exit 3
  [[ "$(grep -c "is not trusted for code signing" <<<"$out")" == 1 ]] || { echo "$out"; exit 4; }
  grep -q "Could not sign" <<<"$out" && exit 5
  # Unattended, nothing is rebuilt ad hoc, and that is not a failure either.
  out="$(GRAND_LINE_UNATTENDED=1 step_native_tools 2>&1)" || { echo "$out"; exit 6; }
  grep -q "not rebuilt unattended while their signing identity cannot sign" <<<"$out" || exit 7
  # Trusted: the helper is signed with it under its fixed name.
  rm -f "$STUB_SECURITY/untrusted"; : > "$STUB_LOG"
  out="$(step_native_tools 2>&1)" || { echo "$out"; exit 8; }
  grep -qF -- "--identifier com.grandline.tool.hello --timestamp=none" "$STUB_LOG" && grep -qF -- "--sign 0123456789ABCDEF" "$STUB_LOG" || exit 9
  exit 0
) && t_ok "step 09: helpers are not signed with an identity that cannot sign, warned once, the step not failed" \
  || t_fail "step 09 with an untrusted identity (step $?)" "$(tail -5 "$STUB_LOG")"

(
  export PATH="$tmp/bin-apps:$PATH" REPO_DIR="$apps_root" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/Applications"
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  git -C "$apps_root" init -q -b main && git -C "$apps_root" add -A && git -C "$apps_root" -c user.email=t@t -c user.name=t commit -q -m apps
  echo '// planted' > "$apps_root/apps/demo/Sources/extra.swift"; sleep 1; touch "$apps_root/apps/demo/Sources/main.swift"
  : > "$STUB_LOG"
  GRAND_LINE_UNATTENDED=1 build_native_apps >/dev/null 2>&1 && exit 1
  grep -q "^swift " "$STUB_LOG" && exit 2          # nothing built from a tree with changes
  rm "$apps_root/apps/demo/Sources/extra.swift"
  # Unattended, from a clean tree, while the app is in use: the new copy
  # waits beside the installed one, and nothing is stopped.
  echo Demo > "$tmp/running"; report="$tmp/apps-report"; : > "$report"
  swap_probe() { echo "stage:the Mac is in use"; }
  : > "$STUB_LOG"; STUB_RUNNING="$tmp/running" GRAND_LINE_APPS_REPORT="$report" GRAND_LINE_UNATTENDED=1 build_native_apps >/dev/null 2>&1 || exit 6
  grep -q "^pkill -TERM -x Demo" "$STUB_LOG" && exit 7
  [[ -d "$tmp/Applications/.Demo App.app.staged" && -d "$tmp/Applications/Demo App.app" ]] || exit 8
  [[ "$(cat "$report")" == "Demo App (waiting)" ]] || exit 9
  # When the Mac is idle: built, a running copy is restarted from the new one
  # in the background, and the waiting copy is gone.
  swap_probe() { echo swap; }
  : > "$report"; rm -f "$GRAND_LINE_STATE/built-demo"; touch "$apps_root/apps/demo/Sources/main.swift"
  : > "$STUB_LOG"; STUB_RUNNING="$tmp/running" GRAND_LINE_APPS_REPORT="$report" GRAND_LINE_UNATTENDED=1 build_native_apps >/dev/null 2>&1 || exit 3
  grep -q "^pkill -TERM -x Demo" "$STUB_LOG" && grep -q "^open -g .*Demo App.app" "$STUB_LOG" || exit 4
  [[ "$(cat "$report")" == "Demo App" ]] || exit 5
  [[ -e "$tmp/Applications/.Demo App.app.staged" ]] && exit 10
  exit 0
) && t_ok "the unattended update never builds uncommitted app code, and swaps a running app only when the Mac is idle" \
  || t_fail "unattended app build (step $?)" "$(cat "$STUB_LOG")"

(
  export REPO_DIR="$apps_root" DRY_RUN=0
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  sup="$HOME/Library/Application Support"; mkdir -p "$sup/Nexus" "$sup/Sight" "$HOME/Library/Caches/com.grandline.sight"
  mkdir -p "$sup/Grand Line Index"; : > "$sup/Grand Line Index/names.index"
  : > "$sup/Nexus/name-index.snapshot"; : > "$sup/Sight/names.index"; : > "$sup/Sight/usage.json"; : > "$sup/Nexus/view-settings.json"
  : > "$STUB_LOG"; exclude_indexes_from_backup
  for f in "$sup/Nexus/name-index.snapshot" "$sup/Sight/names.index" "$sup/Sight/usage.json" "$sup/Grand Line Index/names.index" "$HOME/Library/Caches/com.grandline.sight"; do
    grep -qxF "tmutil addexclusion $f" "$STUB_LOG" || exit 1
  done
  grep -q "view-settings" "$STUB_LOG" && exit 2   # settings stay in the backup
  exit 0
) && t_ok "file indexes, search history and caches are kept out of Time Machine, settings are not" || t_fail "backup exclusions (step $?)" "$(cat "$STUB_LOG")"

# --- a background service: its launch agent sealed in the bundle, registered as you
(
  srv="$tmp/svc-repo"; mkdir -p "$srv/apps/svc/Sources" "$srv/apps/svc/Bundle/Svc/Library/LaunchAgents" "$tmp/svc-bin" "$tmp/SvcApps"
  printf 'Svc\tSvc Index\tcom.example.svc\tno\n' > "$srv/apps/svc/apps.tsv"
  echo '// svc' > "$srv/apps/svc/Sources/main.swift"
  printf '<plist><dict><key>Label</key><string>com.example.svc</string></dict></plist>\n' > "$srv/apps/svc/Bundle/Svc/Library/LaunchAgents/com.example.svc.plist"
  cat > "$tmp/svc-bin/swift" <<'EOF'
#!/bin/bash
args="$*"; pp="${args#*--package-path }"; dir="${pp%% *}"; mkdir -p "$dir/.build/release"
printf '#!/bin/bash\necho "svc $*" >> "$STUB_LOG"\n[[ "$1" == --register ]] && { echo "requires approval"; exit 1; }\nexit 0\n' > "$dir/.build/release/Svc"
chmod +x "$dir/.build/release/Svc"
EOF
  chmod +x "$tmp/svc-bin/swift"
  export PATH="$tmp/svc-bin:$PATH" REPO_DIR="$srv" DRY_RUN=0 GRAND_LINE_APPS_DEST="$tmp/SvcApps"
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  app="$tmp/SvcApps/Svc Index.app"
  : > "$STUB_LOG"; out="$(build_native_apps 2>&1)"
  [[ -f "$app/Contents/Library/LaunchAgents/com.example.svc.plist" ]] || exit 1
  # Copied in before signing, so the signature seals it.
  [[ "$(grep -n "codesign --force --options runtime --sign - .*\.Svc Index\.app\.new$" "$STUB_LOG" | head -1 | cut -d: -f1)" -gt 0 ]] || exit 2
  grep -q "^svc --register$" "$STUB_LOG" || exit 3
  grep -q "Allow in the Background, Svc Index" <<<"$out" || exit 4
  grep -q "sudo" "$STUB_LOG" && exit 5
  grep -q "launchctl kickstart" "$STUB_LOG" && exit 6       # first install: nothing to restart
  echo '// svc v2' > "$srv/apps/svc/Sources/main.swift"
  : > "$STUB_LOG"; build_native_apps >/dev/null 2>&1
  grep -q "^launchctl kickstart -k gui/501/com.example.svc$" "$STUB_LOG" || exit 7
  grep -q "^open -g" "$STUB_LOG" && exit 8                   # launchd restarts it, not open
  DRY_RUN=1 install_app_bundle "$srv/apps/svc" Svc "Svc Index" com.example.svc no | grep -q "\[dry-run\] .*Svc --register" || exit 9
  exit 0
) && t_ok "a background service's launch agent is sealed in its bundle, registered as you, restarted by launchd" \
  || t_fail "background service (step $?)" "$(cat "$STUB_LOG")"

# --- theme-matched Finder icons: the apps get the theme's icon and keep their signature
(
  irepo="$tmp/icons-repo"; mkdir -p "$irepo/apps/demo" "$irepo/tools" "$tmp/IconApps/Demo App.app/Contents/Resources"
  printf 'Demo\tDemo App\tcom.example.demo\tyes\n' > "$irepo/apps/demo/apps.tsv"
  cat > "$irepo/tools/make-icons.py" <<'EOF'
import sys, os
args = sys.argv[1:]
out = args[args.index("--out") + 1]; theme = args[args.index("--theme") + 1]
os.makedirs(os.path.join(out, "Demo"), exist_ok=True)
open(os.path.join(out, "Demo", "AppIcon.icns"), "w").write("icon " + theme)
EOF
  app="$tmp/IconApps/Demo App.app"; echo old > "$app/Contents/Resources/AppIcon.icns"
  export GRAND_LINE_APPS_DEST="$tmp/IconApps"
  source "$ROOT/lib/signing.sh"; source "$ROOT/lib/app-icons.sh"
  # Without the identity nothing changes: an ad-hoc signature would cost permissions.
  SIGN_KEYCHAIN="$tmp/none.keychain-db"
  refresh_app_icons nord "$irepo" >/dev/null; [[ "$(cat "$app/Contents/Resources/AppIcon.icns")" == old ]] || exit 1
  export STUB_SECURITY="$tmp/sec"; SIGN_KEYCHAIN="$tmp/kc/grand-line-signing.keychain-db"
  : > "$STUB_LOG"; refresh_app_icons nord "$irepo" >/dev/null || exit 2
  [[ "$(cat "$app/Contents/Resources/AppIcon.icns")" == "icon nord" ]] || exit 3
  grep -qF 'certificate leaf = H"0123456789abcdef' "$app/.stub-signature" || exit 4
  compgen -G "$tmp/IconApps/.*.app*" >/dev/null && exit 5   # no copies left behind
  : > "$STUB_LOG"; refresh_app_icons nord "$irepo" >/dev/null
  grep -q "^codesign" "$STUB_LOG" && exit 6   # already matching: left alone
  exit 0
) && t_ok "theme icons: the installed apps get the theme's icon, re-signed with the identity, skipped without it" \
  || t_fail "theme icons (step $?)" "$(cat "$STUB_LOG")"
python3 "$ROOT/tools/make-icons.py" --theme nord --only Iceberg --out "$tmp/icons-out" >/dev/null 2>&1
[[ -s "$tmp/icons-out/Iceberg/AppIcon.icns" ]] && git -C "$ROOT" diff --quiet -- apps/iceberg/Resources/Iceberg/AppIcon.icns \
  && t_ok "make-icons --out writes the icons elsewhere, leaving the package's own" || t_fail "make-icons --out"
# A light variant takes ICON_STYLE and its app colours through EXTENDS, as the apps read it.
mkdir -p "$tmp/icon-themes"
printf 'FORMAT=1\nLABEL="Base"\nMODE=dark\nICON_STYLE=mono   # inherited\nICON_FILES=#123456\nFAMILY=base\n' > "$tmp/icon-themes/base-dark.theme"
printf 'FORMAT=1\nEXTENDS=base-dark\nLABEL="Base Light"\nMODE=light\n' > "$tmp/icon-themes/base-light.theme"
printf 'EXTENDS=loop-b\n' > "$tmp/icon-themes/loop-a.theme"; printf 'EXTENDS=loop-a\n' > "$tmp/icon-themes/loop-b.theme"
if python3 -I -B - "$ROOT/tools/make-icons.py" "$tmp/icon-themes" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("make_icons", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
v = m.read_theme("base-light", folder=sys.argv[2])
assert v["ICON_STYLE"] == "mono" and v["ICON_FILES"] == "#123456" and v["MODE"] == "light", v
assert v["LABEL"] == "Base Light" and v["FAMILY"] == "base" and "EXTENDS" not in v, v
assert m.palette(v, "ICON_FILES")["ink"] == m.hex_color("123456")   # mono: the app colour is the ink
try:
    m.read_theme("loop-a", folder=sys.argv[2]); sys.exit("a loop was not caught")
except SystemExit as e:
    assert "loop" in str(e), e
EOF
then t_ok "make-icons reads a theme with what it inherits through EXTENDS (and stops at a loop)"; else t_fail "make-icons EXTENDS"; fi

# --- updates: only signed commits apply by themselves
if command -v ssh-keygen >/dev/null 2>&1; then
(
  source "$ROOT/lib/update-trust.sh"
  us="$tmp/upstate"; UPSTREAM_APPLIED="$us/upstream-applied"; UPDATE_TOLD="$us/update-told"
  ssh-keygen -q -t ed25519 -N "" -C test -f "$tmp/signkey" && ssh-keygen -q -t ed25519 -N "" -C other -f "$tmp/otherkey" || exit 1
  export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
  git config --global user.name t; git config --global user.email t@example.com
  git config --global gpg.format ssh; git config --global user.signingkey "$tmp/signkey.pub"
  export GRAND_LINE_ALLOWED_SIGNERS="$tmp/trust/allowed_signers"; ALLOWED_SIGNERS="$GRAND_LINE_ALLOWED_SIGNERS"
  trust_init >/dev/null || exit 2
  grep -qF "t@example.com namespaces=\"git\" $(cut -d' ' -f1,2 "$tmp/signkey.pub")" "$ALLOWED_SIGNERS" || exit 3
  [[ "$(stat -c %a "$ALLOWED_SIGNERS" 2>/dev/null || stat -f %Lp "$ALLOWED_SIGNERS")" == 600 ]] || exit 4
  # GitHub's copy, and this Mac's clone of it.
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/up" 2>/dev/null; echo 1 > "$tmp/up/f"; git -C "$tmp/up" add f
  git -C "$tmp/up" commit -q -S -m one && git -C "$tmp/up" push -q origin main 2>/dev/null || exit 5
  git clone -q "$tmp/origin.git" "$tmp/mac" 2>/dev/null
  STRICT=1
  # A signed commit applies by itself.
  echo 2 > "$tmp/up/f"; git -C "$tmp/up" commit -q -S -am two; git -C "$tmp/up" push -q 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null || exit 6
  [[ "$(cat "$tmp/mac/f")" == 2 && ${#changed[@]} == 1 ]] || exit 7
  # An unsigned one, or one signed by another key, waits for you.
  echo 3 > "$tmp/up/f"; git -C "$tmp/up" commit -q --no-gpg-sign -am three; git -C "$tmp/up" push -q 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; rc=$?
  [[ "$rc" == 2 && "$(cat "$tmp/mac/f")" == 2 && ${#needs[@]} == 1 ]] || exit 8
  STRICT=0; package_update "$tmp/mac" </dev/null >/dev/null; [[ "$(cat "$tmp/mac/f")" == 2 ]] || exit 9   # no keyboard, no yes
  STRICT=1
  git -C "$tmp/up" reset -q --hard HEAD~1
  echo 3 > "$tmp/up/f"; git -C "$tmp/up" -c user.signingkey="$tmp/otherkey.pub" commit -q -S -am three-other
  git -C "$tmp/up" push -q -f 2>/dev/null
  # (the unsigned commit was only fetched, never applied, so dropping it is not a rewrite of what this Mac has)
  git -C "$tmp/mac" fetch -q 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && "$(cat "$tmp/mac/f")" == 2 ]] || exit 10
  commit_trusted "$tmp/mac" "$(git -C "$tmp/mac" rev-parse origin/main)" && exit 11
  # A rewritten (force-pushed) history is never applied, even when signed:
  # here "two", which this Mac applied, is dropped.
  git -C "$tmp/up" reset -q --hard HEAD~2; echo 4 > "$tmp/up/g"; git -C "$tmp/up" add g; git -C "$tmp/up" commit -q -S -m four
  git -C "$tmp/up" push -q -f 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && ! -e "$tmp/mac/g" ]] || exit 12
  grep -q rewritten <<<"${needs[*]}" || exit 13
  # The unattended run says so once, not every day.
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && ${#needs[@]} == 0 && ! -e "$tmp/mac/g" ]] || exit 20
  # A fetch made by something else first (lazygit, grandline publish) does not hide it.
  git -C "$tmp/mac" fetch -q 2>/dev/null; rm -f "$UPDATE_TOLD"
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && ! -e "$tmp/mac/g" ]] || exit 21
  grep -q rewritten <<<"${needs[*]}" || exit 22
  # Without the record (a Mac updated before it existed), the remote ref's history still tells.
  rm -rf "$us"
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && ! -e "$tmp/mac/g" ]] || exit 23
  # Once you have moved this clone onto GitHub's copy yourself, updates carry on.
  git -C "$tmp/mac" reset -q --keep origin/main
  echo 5 > "$tmp/up/f"; git -C "$tmp/up" commit -q -S -am five; git -C "$tmp/up" push -q 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null || exit 24
  [[ "$(cat "$tmp/mac/f")" == 5 && -e "$tmp/mac/g" ]] || exit 25
  # Your own commits not yet on GitHub: unattended, nothing is rebased or
  # signed again; it stops and says so once.
  git config --global commit.gpgsign true
  echo mine > "$tmp/mac/local"; git -C "$tmp/mac" add local; git -C "$tmp/mac" commit -q -m mine
  mine="$(git -C "$tmp/mac" rev-parse HEAD)"
  echo 6 > "$tmp/up/f"; git -C "$tmp/up" commit -q -S -am six; git -C "$tmp/up" push -q 2>/dev/null
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; rc=$?
  [[ $rc == 2 && "$(git -C "$tmp/mac" rev-parse HEAD)" == "$mine" && "$(cat "$tmp/mac/f")" == 5 ]] || exit 26
  grep -q "commits of its own" <<<"${needs[*]}" || exit 27
  changed=(); needs=(); package_update "$tmp/mac" >/dev/null; [[ $? == 2 && ${#needs[@]} == 0 ]] || exit 28
  git config --global --unset commit.gpgsign
  # Run by you, they are kept on top of GitHub's.
  STRICT=0; changed=(); needs=(); package_update "$tmp/mac" </dev/null >/dev/null || exit 14
  [[ "$(cat "$tmp/mac/f")" == 6 && -f "$tmp/mac/local" && "$(git -C "$tmp/mac" log -1 --format=%s)" == mine ]] || exit 15
  STRICT=1
  # GPG-style signatures are not accepted (only keys in the allowed list count).
  git -C "$tmp/mac" cat-file commit HEAD~1 | grep -q "BEGIN SSH SIGNATURE" || exit 16
  exit 0
) && t_ok "update applies commits signed by a trusted key, keeps your own, refuses unsigned, foreign and rewritten ones" \
  || t_fail "signed updates (step $?)"
elif [[ -n "${CI:-}" ]]; then t_fail "ssh-keygen is missing, so the signed update test could not run"
else echo "    skip  ssh-keygen is not installed"; fi

# --- the unattended update: launch agent, no sudo steps, marked migrations only
(
  export STUB_LAUNCHD="$tmp/launchd"; : > "$STUB_LAUNCHD"
  plist="$HOME/Library/LaunchAgents/com.grandline.update.plist"
  "$ROOT/bin/update" auto on >/dev/null || exit 1
  grep -q "<string>--unattended</string>" "$plist" && grep -q "<key>StartCalendarInterval</key>" "$plist" \
    && grep -q "<key>LowPriorityIO</key><true/>" "$plist" && grep -q "<key>RunAtLoad</key><true/>" "$plist" \
    && grep -q "Library/Logs/grand-line/update.log" "$plist" || exit 2
  grep -qx com.grandline.update "$STUB_LAUNCHD" || exit 3
  [[ "$("$ROOT/bin/update" auto status)" == on* ]] || exit 4
  "$ROOT/bin/update" auto off >/dev/null; "$ROOT/bin/update" auto status >/dev/null && exit 5
  [[ ! -e "$plist" ]] && compgen -G "$HOME/.Trash/com.grandline.update*" >/dev/null || exit 6
  # Off means off: the agent's run stops at once.
  GRAND_LINE_UPDATE_LOCK="$tmp/u.lock" "$ROOT/bin/update" --unattended >/dev/null 2>&1 || exit 7
  [[ ! -e "$tmp/u.lock" ]] || exit 8
  "$ROOT/bin/update" auto toggle >/dev/null; [[ "$("$ROOT/bin/update" auto status)" == on* ]] || exit 9
  "$ROOT/bin/update" auto off >/dev/null
  exit 0
) && t_ok "update auto on, off and status manage the daily low-priority launch agent" || t_fail "update auto (step $?)" "$(tail -5 "$STUB_LOG")"
out="$(GRAND_LINE_HOME="$ROOT" bash "$ROOT/setup.sh" --unattended --only security 2>&1)"; code=$?
[[ "$code" == 2 ]] && grep -q "does not run unattended" <<<"$out" && t_ok "setup --unattended refuses steps that may ask for a password" || t_fail "setup --unattended" "$out"
grep -q '^UNATTENDED_STEPS="folders,dotfiles,native-tools,downloads"$' "$ROOT/setup.sh" \
  && ! grep -nE '\bsudo\b' "$ROOT/steps/07-folders.sh" "$ROOT/steps/08-dotfiles.sh" "$ROOT/steps/09-native-tools.sh" "$ROOT/steps/13-downloads.sh" \
  && t_ok "the unattended steps never use sudo" || t_fail "an unattended step uses sudo"
(
  mrepo="$tmp/mig"; mkdir -p "$mrepo/migrations"
  printf '# grandline:unattended\necho a >> "%s"\n' "$tmp/mig.out" > "$mrepo/migrations/1800000000-quiet.sh"
  printf 'echo b >> "%s"\n' "$tmp/mig.out" > "$mrepo/migrations/1800000001-asks.sh"
  # A later quiet one may rely on the one that asks, so it waits for it.
  printf '# grandline:unattended\necho c >> "%s"\n' "$tmp/mig.out" > "$mrepo/migrations/1800000002-quiet-later.sh"
  rm -rf "$HOME/.local/state/grand-line/migrations"
  out="$(GRAND_LINE_REPO="$mrepo" "$ROOT/bin/migrate" --unattended)"; rc=$?
  [[ "$rc" == 3 && "$(cat "$tmp/mig.out")" == a ]] || exit 1
  grep -q "^2 one-time change(s) wait" <<<"$out" || exit 4
  GRAND_LINE_REPO="$mrepo" "$ROOT/bin/migrate" >/dev/null || exit 2
  [[ "$(tr -d '\n' < "$tmp/mig.out")" == abc ]] || exit 3
  rm -rf "$HOME/.local/state/grand-line/migrations"
) && t_ok "unattended migrations run strictly oldest first, stopping at the first not marked # grandline:unattended" || t_fail "migrate --unattended (step $?)"

# --- nothing is sent to GitHub by itself
! grep -nE 'git[^|;&]* push|git_ push|push_\b' "$ROOT/bin/update" "$ROOT/bin/app" "$ROOT/lib/"*.sh "$ROOT/setup.sh" "$ROOT/steps/"*.sh \
  && [[ "$(grep -c 'git_ push' "$ROOT/bin/grandline")" == 1 ]] && grep -q 'ask "Send these' "$ROOT/bin/grandline" \
  && t_ok "only grandline publish sends to GitHub, and only after asking" || t_fail "automatic push left somewhere"
! grep -nE 'git[^|;&]* commit' "$ROOT/bin/update" "$ROOT/bin/app" && t_ok "update and app install never commit by themselves" || t_fail "automatic commit left"
(
  r2="$tmp/repo2"; mkdir -p "$r2"; git -C "$r2" init -q -b main; git -C "$r2" config user.email t@t; git -C "$r2" config user.name t
  echo one > "$r2/a.txt"; git -C "$r2" add -A; git -C "$r2" commit -q -m First
  echo two > "$r2/a.txt"; echo note > "$r2/clinic-note.txt"
  GRAND_LINE_REPO="$r2" GRAND_LINE_NO_APPLY=1 "$ROOT/bin/grandline" save "x" >/dev/null
  [[ -z "$(git -C "$r2" status --porcelain --untracked-files=no)" ]] || exit 1   # tracked edit saved
  git -C "$r2" ls-files --error-unmatch clinic-note.txt >/dev/null 2>&1 && exit 2   # new file never added
  out="$(GRAND_LINE_REPO="$r2" "$ROOT/bin/grandline" publish </dev/null 2>&1)" && exit 3
  grep -q "in a terminal" <<<"$out" || exit 4
  exit 0
) && t_ok "grandline saves edits to tracked files only, and publish needs someone at the keyboard" || t_fail "grandline save and publish (step $?)"

# --- the Trash: root never moves anything into a folder you can write
(
  source "$ROOT/lib/trash.sh"
  victim="$tmp/victim"; mkdir -p "$victim" "$HOME/.Trash"
  echo data > "$tmp/Report.txt"
  ln -sfn "$victim" "$HOME/.Trash/Report.txt"          # a planted link with the same name
  move_to_trash "$tmp/Report.txt" || exit 1
  [[ ! -e "$tmp/Report.txt" && -z "$(ls -A "$victim")" ]] || exit 2
  compgen -G "$HOME/.Trash/Report *.txt" >/dev/null || exit 3
  # The sudo path: staged in a folder only root can write, links never followed.
  stub="$tmp/sudo-bin"; mkdir -p "$stub" "$tmp/stage-root"
  printf '#!/bin/bash\necho "sudo $*" >> "$STUB_LOG"\n[[ "$1" == -n ]] && shift\nexec "$@"\n' > "$stub/sudo"; chmod +x "$stub/sudo"
  echo app > "$tmp/Old.app"; ln -sfn "$victim" "$HOME/.Trash/Old.app"
  calls="$tmp/mv-calls"; : > "$calls"
  mv() { echo x >> "$calls"; (( $(wc -l < "$calls") == 1 )) && return 1; command mv "$@"; }
  : > "$STUB_LOG"
  PATH="$stub:$PATH" GRAND_LINE_TRASH_STAGE="$tmp/stage-root" move_to_trash "$tmp/Old.app" || exit 4
  unset -f mv
  [[ ! -e "$tmp/Old.app" && -z "$(ls -A "$victim")" ]] || exit 5
  # Root moved the item itself (mv -n) into a new folder in the stage root.
  # Paths are compared with their links resolved (macOS: /var is /private/var,
  # and either side may be written either way).
  resolved_dir() { (cd -P "$1" 2>/dev/null && pwd -P); }
  moved="$(grep '^sudo mv -n ' "$STUB_LOG")"
  [[ "$(grep -c . <<<"$moved")" == 1 ]] || exit 6
  rest="${moved#sudo mv -n }"; from="${rest%%/Old.app *}/Old.app"; to="${rest#*/Old.app }"
  [[ "$from $to" == "$rest" && "$to" == */Old.app ]] || exit 6
  [[ -n "$(resolved_dir "$tmp")" && "$(resolved_dir "$(dirname "$from")")" == "$(resolved_dir "$tmp")" ]] || exit 6
  stagedir="$(dirname "$to")"
  [[ "$(basename "$stagedir")" == grand-line-trash.?????? ]] || exit 6
  [[ "$(resolved_dir "$(dirname "$stagedir")")" == "$(resolved_dir "$tmp/stage-root")" ]] || exit 6
  grep -q "^sudo chown -R -h " "$STUB_LOG" || exit 7
  compgen -G "$HOME/.Trash/Old *.app" >/dev/null || exit 8
  [[ -z "$(ls -A "$tmp/stage-root")" ]] || exit 9
  : > "$STUB_LOG"; echo x > "$tmp/Q.txt"; : > "$calls"
  mv() { echo x >> "$calls"; (( $(wc -l < "$calls") == 1 )) && return 1; command mv "$@"; }
  PATH="$stub:$PATH" GRAND_LINE_UNATTENDED=1 GRAND_LINE_TRASH_STAGE="$tmp/stage-root" move_to_trash "$tmp/Q.txt"
  unset -f mv
  grep -q "^sudo -n mktemp" "$STUB_LOG" || exit 10   # unattended never waits for a password
  rm -f "$HOME/.Trash/Report.txt" "$HOME/.Trash/Old.app"
  exit 0
) && t_ok "move_to_trash never follows a link planted in the Trash, and root works only in its own folder" || t_fail "trash (step $?)" "$(cat "$STUB_LOG")"

# --- clipboard and notifications around the clinical apps
(
  stub="$tmp/ocr-bin"; mkdir -p "$stub"
  printf '#!/bin/bash\nprintf "Patient Example 0012345"\n' > "$stub/ocr"
  printf '#!/bin/bash\necho "screencapture $*" >> "$STUB_LOG"\necho png > "${!#}"\n' > "$stub/screencapture"
  printf '#!/bin/bash\ncat > /dev/null\n' > "$stub/pbcopy"; chmod +x "$stub/"*
  : > "$STUB_LOG"
  PATH="$stub:$PATH" GRAND_LINE_TEST_PATH="$stub:$ROOT/tests/stubs" "$ROOT/bin/capture" text
  sleep 0.3
  grep -q "osascript - Text copied Copied 23 characters" "$STUB_LOG" || exit 1
  grep -q "Patient" "$STUB_LOG" && exit 2
  exit 0
) && t_ok "capture text says how much it copied, never what" || t_fail "capture text notification (step $?)" "$(cat "$STUB_LOG")"
(
  export REPO_DIR="$ROOT" DRY_RUN=0
  source "$ROOT/lib/common.sh"; source "$ROOT/steps/10-macos-defaults.sh"
  mkdir -p "$GRAND_LINE_STATE"; touch "$GRAND_LINE_STATE/done-macos-defaults"
  : > "$STUB_LOG"; step_macos_defaults >/dev/null
  grep -q "defaults write org.p0deje.Maccy ignoredApps -array com.citrix.receiver.icaviewer.mac com.citrix.receiver.nomas com.vmware.horizon com.omnissa.horizon.client.mac" "$STUB_LOG" || exit 1
  grep -q "ignoredPasteboardTypes -array Pasteboard generator type com.agilebits.onepassword .* org.nspasteboard.ConcealedType org.nspasteboard.TransientType" "$STUB_LOG" || exit 2
  grep -q "historySize" "$STUB_LOG" && exit 3      # your other settings are still set only once
  rm -f "$GRAND_LINE_STATE/done-macos-defaults"
  exit 0
) && t_ok "Maccy's ignore list is checked on every run, keeping its own defaults" || t_fail "Maccy ignore list (step $?)" "$(cat "$STUB_LOG")"

# --- the unattended update never swaps an app in use
(
  export REPO_DIR="$ROOT" DRY_RUN=0
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/native-apps.sh"
  id=com.grandline.sight
  [[ "$(swap_decision 900 com.apple.TextEdit "$id" 0 0 0)" == swap ]] || exit 1
  [[ "$(swap_decision 30 com.apple.TextEdit "$id" 0 0 0)" == stage:* ]] || exit 2      # in use
  [[ "$(swap_decision 900 "$id" "$id" 0 0 0)" == "stage:it is the app in front" ]] || exit 3
  [[ "$(swap_decision 900 com.apple.TextEdit "$id" 1 0 0)" == "stage:it is in the middle of something" ]] || exit 4
  [[ "$(swap_decision 900 "" "$id" 0 1 0)" == "stage:the screen is being shared" ]] || exit 5
  [[ "$(swap_decision 900 "" "$id" 0 0 1)" == stage:* ]] || exit 6                     # presenting
  [[ "$(swap_decision "" "" "$id" 0 0 0)" == stage:* ]] || exit 7                      # no reading: wait
  [[ "$(swap_decision 599 "" "$id" 0 0 0)" == stage:* && "$(swap_decision 600 "" "$id" 0 0 0)" == swap ]] || exit 8
  # A staged copy goes in at once for an app that is not running.
  dest="$tmp/staged-apps"; mkdir -p "$dest/.Sight.app.staged/Contents" "$dest/Sight.app"
  echo new > "$dest/.Sight.app.staged/Contents/marker"
  pgrep() { return 1; }
  GRAND_LINE_APPS_DEST="$dest" APPS_DEST="$dest" apply_staged_apps >/dev/null 2>&1
  [[ "$(cat "$dest/Sight.app/Contents/marker" 2>/dev/null)" == new && ! -e "$dest/.Sight.app.staged" ]] || exit 9
  exit 0
) && t_ok "the unattended update swaps an app only when the Mac is idle and the app is not in use" \
  || t_fail "update swap decision (step $?)"

exit $FAIL
