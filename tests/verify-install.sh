#!/usr/bin/env bash
# Checks a Mac after setup has run: apps, tools, links, default apps and the
# helper commands. Prints a PASS or FAIL line for each check.
#   bash tests/verify-install.sh            all checks
#   bash tests/verify-install.sh --ci       skip checks that need a signed-in desktop

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI=0; [[ "${1:-}" == "--ci" ]] && CI=1
source "$ROOT/lib/paths.sh"
export PATH="$BREW_PREFIX/bin:$MAC_SETUP_BIN:$MAC_SETUP_BUILD:$PATH"

PASS=0; FAIL=0; WARN=0
GH="${GITHUB_ACTIONS:-}"
pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); [[ -n "$GH" ]] && echo "::error title=verify::$1"; }
note() { printf '  WARN  %s\n' "$1"; WARN=$((WARN + 1)); [[ -n "$GH" ]] && echo "::warning title=verify::$1"; }

echo "Homebrew"
command -v brew >/dev/null && pass "brew is on the PATH" || fail "brew is missing"

echo "Command line tools"
while read -r name; do
  brew list --formula "$name" >/dev/null 2>&1 && pass "$name" || fail "$name is not installed"
done < <(sed -nE 's/^brew "([^"]+)".*/\1/p' "$ROOT/Brewfile")

echo "Apps"
installed=" $(brew list --cask -1 2>/dev/null | tr '\n' ' ') "
casks=()
while IFS= read -r c; do casks+=("$c"); done < <(sed -nE 's/^cask "([^"]+)".*/\1/p' "$ROOT/Brewfile")
while IFS=$'\t' read -r token app; do
  if [[ "$installed" == *" ${token##*/} "* ]]; then
    pass "$token"
  elif [[ -n "$app" && -d "/Applications/$(basename "$app")" ]]; then
    pass "$token (installed outside Homebrew)"
  else
    fail "$token is not installed"
  fi
done < <(brew info --cask --json=v2 "${casks[@]}" 2>/dev/null | jq -r '
  .casks[] | .full_token as $t
  | [$t, ([.artifacts[]? | select(type == "object" and has("app")) | .app[] | select(type == "string")][0] // "")] | @tsv')

echo "ArtCraft apps"
while IFS=$'\t' read -r app repo _; do
  [[ -z "$app" || "$app" == \#* ]] && continue
  path="$(cat "$MAC_SETUP_STATE/artcraft/$app.path" 2>/dev/null)"
  if [[ -n "$path" && -d "$path" ]]; then pass "$app"
  else note "$app is not installed (check whether $repo has a macOS release yet)"; fi
done < "$ROOT/config/mac-setup/artcraft.tsv"

echo "Settings and commands"
for target in "$MAC_SETUP_LINK" "$HOME/.aerospace.toml" "$HOME/.config/ghostty"; do
  if [[ -L "$target" && -e "$target" ]]; then pass "$target"; else fail "$target is not linked"; fi
done
cmp -s "$ROOT/config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json" \
  && pass "Karabiner has the current shortcuts" || fail "Karabiner settings differ from the package"
grep -q "$MAC_SETUP_BIN" "$HOME/.zprofile" && pass "package commands are on the PATH for new shells" || fail ".zprofile does not add the package commands"
launchctl print "gui/$(id -u)/mac-setup.downloads" >/dev/null 2>&1 \
  && pass "Downloads sorting is loaded" || fail "Downloads sorting is not loaded"
[[ -L "$HOME/Library/Application Support/espanso/match/mac-setup.yml" ]] \
  && pass "Espanso has the text shortcuts" || fail "Espanso shortcuts are not linked"
for cmd_path in "$ROOT"/bin/*; do
  name="$(basename "$cmd_path")"
  command -v "$name" >/dev/null && pass "command: $name" || fail "command $name is not on the PATH"
done
for src in "$ROOT"/tools/*.swift; do
  name="$(basename "$src" .swift)"
  if [[ -x "$MAC_SETUP_BUILD/$name" ]]; then
    "$MAC_SETUP_BUILD/$name" >/dev/null 2>&1; [[ $? -eq 1 ]] && pass "helper $name runs" || fail "helper $name does not run"
  else
    fail "helper $name was not built"
  fi
done

echo "Default apps"
while IFS=$'\t' read -r app exts _; do
  [[ -z "$app" || "$app" == \#* ]] && continue
  ext="${exts%% *}"; ext="${ext#.}"
  handler="$(duti -x "$ext" 2>/dev/null | head -1)"
  if [[ "$handler" == "$app.app" ]]; then pass ".$ext opens in $app"
  elif [[ -d "/Applications/$app.app" ]]; then fail ".$ext opens in ${handler:-nothing}, but $app is installed and should open it"
  elif [[ -n "$handler" ]]; then note ".$ext opens in $handler because $app is not installed"
  else fail ".$ext has no default app"; fi
done < "$ROOT/config/mac-setup/default-apps.tsv"

echo "Preinstalled apps the package replaces"
# shellcheck source=steps/05-declutter.sh
source "$ROOT/steps/05-declutter.sh"
for app in "${DECLUTTER_APPS[@]}"; do
  [[ -d "/Applications/$app.app" ]] && fail "$app is still installed" || pass "$app removed"
done
[[ -L "$HOME/.config/nvim" ]] && pass "Neovim uses the package's LazyVim setup" || fail "Neovim config is not linked"
git config --global --get-all include.path | grep -q "config/git/config" && pass "git defaults included" || fail "git defaults not included"

command -v jq >/dev/null && pass "jq (built into macOS)" || fail "jq is missing (needs macOS 15 or later)"
tar --version 2>/dev/null | grep -q libarchive && pass "tar opens .7z and .rar (libarchive)" || fail "tar is not libarchive"

echo "Security"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q enabled && pass "firewall on" || fail "firewall off"
[[ "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null)" == 1 ]] \
  && pass "security updates install automatically" || fail "automatic security updates are off"
csrutil status 2>/dev/null | grep -q enabled && pass "System Integrity Protection on" || note "System Integrity Protection is off"
spctl --status 2>/dev/null | grep -q enabled && pass "Gatekeeper on" || fail "Gatekeeper is off"

echo "System settings"
[[ "$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null)" == 2 ]] && pass "fast key repeat" || fail "key repeat not set"
[[ "$(defaults read com.apple.screencapture location 2>/dev/null)" == "$SCREENSHOTS_DIR" ]] \
  && pass "screenshots go to Pictures/Screenshots" || fail "screenshot folder not set"
[[ -d "$BACKGROUNDS_DIR" ]] && pass "backgrounds folder" || fail "backgrounds folder missing"

if [[ "$CI" == 0 ]]; then
  echo "Desktop"
  [[ -f "$HOME/Documents/Finish setup.txt" ]] && pass "finishing checklist in Documents" || fail "checklist missing"
  pgrep -qx AeroSpace && pass "AeroSpace is running" || note "AeroSpace is not running yet (open it and allow Accessibility)"
fi

echo
echo "$PASS passed, $FAIL failed, $WARN warnings"
[[ -n "$GH" ]] && echo "::notice title=verify::$PASS passed, $FAIL failed, $WARN warnings"
[[ "$FAIL" == 0 ]]
