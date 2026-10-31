# shellcheck shell=bash
# Log Pose in place of Finder, and Byakugan in place of Spotlight.
# Both are on by default once the app is installed, and each switches back
# with one toggle (toggle files, toggle search). The choice is remembered in
# ~/.local/state/grand-line/takeover-<files|search> and kept across updates.
# Needs lib/default-apps.sh (set_ls_handler).

LOGPOSE_ID=com.grandline.logpose
BYAKUGAN_ID=com.grandline.byakugan
LOGPOSE_APP="${GRAND_LINE_APPS_DEST:-/Applications}/Log Pose.app"
BYAKUGAN_APP="${GRAND_LINE_APPS_DEST:-/Applications}/Byakugan.app"

takeover_mode() { cat "$GRAND_LINE_STATE/takeover-$1" 2>/dev/null || echo on; }

# takeover_files on|off: folders, "Show in Finder" and "Reveal" open in Log
# Pose, or in Finder again.
takeover_files() {
  [[ -d "$LOGPOSE_APP" ]] || return 1
  if [[ "$1" == on ]]; then
    defaults write -g NSFileViewer -string "$LOGPOSE_ID"
    set_ls_handler public.folder "$LOGPOSE_ID"
  else
    defaults delete -g NSFileViewer 2>/dev/null
    set_ls_handler public.folder com.apple.finder
  fi
  killall lsd 2>/dev/null
  mkdir -p "$GRAND_LINE_STATE" && printf '%s\n' "$1" > "$GRAND_LINE_STATE/takeover-files"
}

# takeover_search on|off: Command + Space (and so Caps + Space) opens
# Byakugan, or Spotlight again. Spotlight's own shortcut is switched off
# while Byakugan holds it, since only one app can.
takeover_search() {
  [[ -d "$BYAKUGAN_APP" ]] || return 1
  local enabled=true takes=false
  [[ "$1" == on ]] && { enabled=false; takes=true; }
  # 64 is "Show Spotlight search": Space (49) with Command (1048576).
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
    "<dict><key>enabled</key><$enabled/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"
  local activate=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
  [[ -x "$activate" ]] && "$activate" -u >/dev/null 2>&1
  defaults write "$BYAKUGAN_ID" TakesCommandSpace -bool "$takes"
  # Byakugan reads the setting when it starts, so restart it.
  pkill -x Byakugan 2>/dev/null
  open -g -b "$BYAKUGAN_ID" 2>/dev/null
  mkdir -p "$GRAND_LINE_STATE" && printf '%s\n' "$1" > "$GRAND_LINE_STATE/takeover-search"
}

# app_runs ID PROCESS: start the app in the background and check it is still
# running a few seconds later, so folders are never handed to an app that
# cannot open them.
app_runs() {
  pgrep -x "$2" >/dev/null 2>&1 && return 0
  open -g -b "$1" 2>/dev/null || return 1
  local _
  for _ in 1 2 3 4 5; do sleep 1; pgrep -x "$2" >/dev/null 2>&1 && return 0; done
  return 1
}

# apply_takeovers: put back the remembered choice for each installed app.
apply_takeovers() {
  if [[ -d "$LOGPOSE_APP" && "$(takeover_mode files)" == on && "$DRY_RUN" != 1 ]] && ! app_runs "$LOGPOSE_ID" LogPose; then
    warn "Log Pose did not start, so folders stay with Finder. Setup tries again next run."
  elif [[ -d "$LOGPOSE_APP" ]]; then
    run takeover_files "$(takeover_mode files)" && ok "Folders open in $( [[ "$(takeover_mode files)" == on ]] && echo "Log Pose" || echo Finder)"
  fi
  if [[ -d "$BYAKUGAN_APP" && "$(takeover_mode search)" == on && "$DRY_RUN" != 1 ]] && ! app_runs "$BYAKUGAN_ID" Byakugan; then
    warn "Byakugan did not start, so Command + Space stays with Spotlight. Setup tries again next run."
  elif [[ -d "$BYAKUGAN_APP" ]]; then
    run takeover_search "$(takeover_mode search)" && ok "Command + Space opens $( [[ "$(takeover_mode search)" == on ]] && echo Byakugan || echo Spotlight)"
  fi
  return 0
}
