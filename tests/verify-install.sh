#!/usr/bin/env bash
# Checks a Mac after setup has run: apps, tools, links, default apps and the
# helper commands. Prints a PASS or FAIL line for each check.
#   bash tests/verify-install.sh            all checks
#   bash tests/verify-install.sh --ci       skip checks that need a signed-in desktop

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI=0; [[ "${1:-}" == "--ci" ]] && CI=1
source "$ROOT/lib/paths.sh"
export PATH="$BREW_PREFIX/bin:$GRAND_LINE_BIN:$GRAND_LINE_BUILD:$PATH"

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
  path="$(cat "$GRAND_LINE_STATE/artcraft/$app.path" 2>/dev/null)"
  if [[ -n "$path" && -d "$path" ]]; then pass "$app"
  else note "$app is not installed (check whether $repo has a macOS release yet)"; fi
done < "$ROOT/config/grand-line/artcraft.tsv"

echo "Settings and commands"
for target in "$GRAND_LINE_LINK" "$HOME/.aerospace.toml" "$HOME/.config/ghostty"; do
  if [[ -L "$target" && -e "$target" ]]; then pass "$target"; else fail "$target is not linked"; fi
done
cmp -s "$ROOT/config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json" \
  && pass "Karabiner has the current shortcuts" || fail "Karabiner settings differ from the package"
grep -q "$GRAND_LINE_BIN" "$HOME/.zprofile" && pass "package commands are on the PATH for new shells" || fail ".zprofile does not add the package commands"
launchctl print "gui/$(id -u)/grand-line.downloads" >/dev/null 2>&1 \
  && pass "Downloads sorting is loaded" || fail "Downloads sorting is not loaded"
[[ -L "$HOME/Library/Application Support/espanso/match/grand-line.yml" ]] \
  && pass "Espanso has the text shortcuts" || fail "Espanso shortcuts are not linked"
for cmd_path in "$ROOT"/bin/*; do
  name="$(basename "$cmd_path")"
  command -v "$name" >/dev/null && pass "command: $name" || fail "command $name is not on the PATH"
done
for src in "$ROOT"/tools/*.swift; do
  name="$(basename "$src" .swift)"
  if [[ -x "$GRAND_LINE_BUILD/$name" ]]; then
    "$GRAND_LINE_BUILD/$name" >/dev/null 2>&1; [[ $? -eq 1 ]] && pass "helper $name runs" || fail "helper $name does not run"
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
done < "$ROOT/config/grand-line/default-apps.tsv"

browser="$(defaults export com.apple.LaunchServices/com.apple.launchservices.secure - 2>/dev/null | plutil -convert json -o - - 2>/dev/null \
  | jq -r '[.LSHandlers[]? | select(.LSHandlerURLScheme == "https") | .LSHandlerRoleAll][-1] // empty' 2>/dev/null)"
if [[ -d /Applications/Zen.app ]]; then
  [[ "$browser" == app.zen-browser.zen ]] && pass "links open in Zen" || note "links open in ${browser:-Safari}, not Zen (fine if you chose it)"
fi

echo "The package's own apps"
for list in "$ROOT"/apps/*/apps.tsv; do
  [[ -f "$list" ]] || continue
  while IFS=$'\t' read -r _ name id _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    app="/Applications/$name.app"
    if [[ -d "$app" ]] && [[ "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" == "$id" ]]; then
      pass "$name is installed"
      codesign --verify "$app" 2>/dev/null && pass "$name is signed" || fail "$name is not signed"
    else
      fail "$name was not built and installed"
    fi
  done < "$list"
done
state="$HOME/.local/state/grand-line"
if [[ -d "/Applications/Nexus.app" ]]; then
  viewer="$(defaults read -g NSFileViewer 2>/dev/null)"
  if [[ "$(cat "$state/takeover-files" 2>/dev/null || echo on)" == on ]]; then
    [[ "$viewer" == com.grandline.nexus ]] && pass "Show in Finder opens Nexus" || fail "Show in Finder opens ${viewer:-Finder}, not Nexus"
  else
    [[ -z "$viewer" ]] && pass "Show in Finder opens Finder (switched back)" || fail "Show in Finder still opens $viewer"
  fi
fi
if [[ -d "/Applications/Sight.app" ]]; then
  spotlight="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | awk '/^ *64 = /,/};/' | sed -nE 's/^ *enabled = ([01]);/\1/p' | head -1)"
  if [[ "$(cat "$state/takeover-search" 2>/dev/null || echo on)" == on ]]; then
    [[ "$spotlight" == 0 ]] && pass "Command + Space belongs to Sight" || fail "Spotlight still has Command + Space"
  else
    [[ "$spotlight" != 0 ]] && pass "Command + Space opens Spotlight (switched back)" || fail "Spotlight's Command + Space is still off"
  fi
fi
index_app="/Applications/Grand Line Index.app"
if [[ -d "$index_app" ]]; then
  status="$("$index_app/Contents/MacOS/GrandLineIndex" --status 2>&1)"
  if [[ "$status" == enabled* ]]; then pass "Grand Line Index is registered to run in the background"
  elif [[ "$CI" == 1 && "$status" == *"requires approval"* ]]; then note "Grand Line Index waits for approval in Login Items (expected on a test machine)"
  else fail "Grand Line Index is not running in the background: ${status:-no answer}"; fi
  launchctl print "gui/$(id -u)/com.grandline.index" >/dev/null 2>&1 \
    && pass "the index agent is loaded" || { if [[ "$CI" == 1 ]]; then note "the index agent is not loaded"; else fail "the index agent is not loaded"; fi; }
fi
# The apps are signed with hardened runtime (and, off test machines, by the package's own identity).
for app in /Applications/Nexus.app /Applications/Sight.app /Applications/Iceberg.app "$index_app"; do
  [[ -d "$app" ]] || continue
  if codesign -d --verbose "$app" 2>&1 | grep -qE 'flags=0x[0-9a-f]+\([^)]*runtime'; then pass "$(basename "$app" .app) has hardened runtime"
  else fail "$(basename "$app" .app) is not signed with hardened runtime"; fi
  if [[ "$CI" == 0 ]]; then
    codesign -d -r- "$app" 2>&1 | grep -q 'certificate leaf = H"' \
      && pass "$(basename "$app" .app) keeps its permissions across updates (signed by the local identity)" \
      || note "$(basename "$app" .app) is signed ad hoc, so it asks for its permissions after each update"
  fi
done

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
