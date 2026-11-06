# shellcheck shell=bash
# grandline:unattended
# Windows and desktops now use what macOS has built in (its tiling keys and
# Mission Control's desktops, both on the Caps Lock layer), so AeroSpace
# goes. On a Mac set up earlier this:
#   shows every window AeroSpace had parked off screen, then quits it
#   uninstalls it with Homebrew (its own settings and data are kept)
#   removes its login item, if it has one
#   moves the package's ~/.aerospace.toml link to the Trash
#   untaps nikitabobko/tap, unless something else still comes from it
# Nothing is deleted outright and no other setting is changed. Safe to run
# again: each part does nothing once AeroSpace is gone.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

status=0
notes=()

# --- Every window back on screen, then AeroSpace quits. AeroSpace keeps the
# windows of other workspaces in a screen corner; turning it off shows them.
if pgrep -x AeroSpace >/dev/null 2>&1; then
  aero="$(command -v aerospace 2>/dev/null || echo /opt/homebrew/bin/aerospace)"
  [[ -x "$aero" ]] && "$aero" enable off >/dev/null 2>&1
  pkill -x AeroSpace 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x AeroSpace >/dev/null 2>&1 || break
    sleep 0.5
  done
  pgrep -x AeroSpace >/dev/null 2>&1 || echo "AeroSpace has quit"
fi

# --- Uninstalled, keeping its data (no --zap)
brew="$(command -v brew 2>/dev/null || echo /opt/homebrew/bin/brew)"
if [[ -x "$brew" ]]; then
  if "$brew" list --cask 2>/dev/null | grep -qx aerospace; then
    if "$brew" uninstall --cask aerospace; then echo "Uninstalled AeroSpace"
    else echo "Could not uninstall AeroSpace. The next update tries again." >&2; status=1; fi
  fi
fi

# --- Its login item, when it was added as one
osascript - <<'EOF' >/dev/null 2>&1
tell application "System Events"
  if exists login item "AeroSpace" then delete login item "AeroSpace"
end tell
EOF

# --- The package's link to its settings. A file of your own is left.
cfg="$HOME/.aerospace.toml"
if [[ -L "$cfg" ]]; then
  if move_to_trash "$cfg"; then echo "Moved ~/.aerospace.toml to the Trash"
  else echo "Could not move $cfg to the Trash." >&2; status=1; fi
elif [[ -e "$cfg" ]]; then
  notes+=("The .aerospace.toml in your home folder is your own file, not the package's link, so it was left. Nothing reads it any more.")
fi

# --- The tap, when nothing else uses it (Homebrew refuses otherwise).
if [[ -x "$brew" ]] && "$brew" tap 2>/dev/null | grep -qx nikitabobko/tap; then
  "$brew" untap nikitabobko/tap >/dev/null 2>&1 && echo "Untapped nikitabobko/tap"
fi

notes+=("Caps + arrows now tile with macOS's own keys and Caps + 1 to 9 switch desktops. Add desktops in Mission Control (three-finger swipe up, +).")
for n in "${notes[@]}"; do echo "$n"; done
exit "$status"
