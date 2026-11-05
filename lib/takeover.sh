# shellcheck shell=bash
# Sight in place of Spotlight on Command + Space. On by default once the app
# is installed, and it switches back with one toggle (toggle search). The
# choice is remembered in ~/.local/state/grand-line/takeover-search and kept
# across updates. Folders always open in Finder.
# The switch first reads what macOS has now and changes nothing when it is
# already so, so an update run that changes nothing restarts nothing.

SIGHT_ID=com.grandline.sight
SIGHT_APP="${GRAND_LINE_APPS_DEST:-/Applications}/Sight.app"

takeover_mode() { cat "$GRAND_LINE_STATE/takeover-$1" 2>/dev/null || echo on; }

# search_now: on when Sight already holds Command + Space, off when
# Spotlight does, nothing when it is something else.
search_now() {
  local enabled takes
  enabled="$(defaults export com.apple.symbolichotkeys - 2>/dev/null | plutil -extract AppleSymbolicHotKeys.64.enabled raw -o - - 2>/dev/null)"
  takes="$(defaults read "$SIGHT_ID" TakesCommandSpace 2>/dev/null)"
  if [[ "$enabled" == false && "$takes" == 1 ]]; then echo on
  elif [[ "$enabled" == true && ( -z "$takes" || "$takes" == 0 ) ]]; then echo off
  fi
}

# takeover_search on|off: Command + Space (and so Caps + Space) opens
# Sight, or Spotlight again. Spotlight's own shortcut is switched off
# while Sight holds it, since only one app can.
takeover_search() {
  [[ -d "$SIGHT_APP" ]] || return 1
  # Already so: Sight keeps running and the shortcuts are not rewritten.
  if [[ "$(search_now)" == "$1" ]]; then
    mkdir -p "$GRAND_LINE_STATE" && printf '%s\n' "$1" > "$GRAND_LINE_STATE/takeover-search"
    return 0
  fi
  local enabled=true takes=false
  [[ "$1" == on ]] && { enabled=false; takes=true; }
  # 64 is "Show Spotlight search": Space (49) with Command (1048576).
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
    "<dict><key>enabled</key><$enabled/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"
  local activate=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
  [[ -x "$activate" ]] && "$activate" -u >/dev/null 2>&1
  defaults write "$SIGHT_ID" TakesCommandSpace -bool "$takes"
  # Sight reads the setting when it starts, so restart it.
  pkill -x Sight 2>/dev/null
  launch_quietly "$SIGHT_ID"
  mkdir -p "$GRAND_LINE_STATE" && printf '%s\n' "$1" > "$GRAND_LINE_STATE/takeover-search"
}

# launch_quietly ID: start an app in the background without waiting for it.
# `open` waits until the app has finished launching, so an app showing a
# dialog at launch would otherwise hold up setup for good.
launch_quietly() {
  open -g -b "$1" </dev/null >/dev/null 2>&1 &
}

# app_runs ID PROCESS: start the app in the background and check it is still
# running a few seconds later, so Command + Space is never handed to an app
# that cannot answer it.
app_runs() {
  pgrep -x "$2" >/dev/null 2>&1 && return 0
  launch_quietly "$1"
  local _
  for _ in 1 2 3 4 5; do sleep 1; pgrep -x "$2" >/dev/null 2>&1 && return 0; done
  return 1
}

# apply_takeovers: put back the remembered choice for Sight, once installed.
apply_takeovers() {
  if [[ -d "$SIGHT_APP" && "$(takeover_mode search)" == on && "$DRY_RUN" != 1 ]] && ! app_runs "$SIGHT_ID" Sight; then
    warn "Sight did not start, so Command + Space stays with Spotlight. Setup tries again next run."
  elif [[ -d "$SIGHT_APP" ]]; then
    run takeover_search "$(takeover_mode search)" && ok "Command + Space opens $( [[ "$(takeover_mode search)" == on ]] && echo Sight || echo Spotlight)"
  fi
  return 0
}
