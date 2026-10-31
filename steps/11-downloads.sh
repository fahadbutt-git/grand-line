# shellcheck shell=bash
# Keeps Downloads sorted. macOS starts tidy-downloads whenever the folder
# changes (and hourly, for the age rules) at low priority. No process stays
# running between sorts.

DOWNLOADS_LABEL="mac-setup.downloads"

downloads_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DOWNLOADS_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$MAC_SETUP_BIN/tidy-downloads</string></array>
  <key>WatchPaths</key><array><string>$HOME/Downloads</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>ThrottleInterval</key><integer>20</integer>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST
}

step_downloads() {
  local plist="$HOME/Library/LaunchAgents/$DOWNLOADS_LABEL.plist" new
  new="$(downloads_plist)"
  if [[ -f "$plist" && "$(cat "$plist")" == "$new" ]]; then
    ok "Downloads sorting already on"
    return 0
  fi
  run mkdir -p "$HOME/Library/LaunchAgents"
  if [[ "$DRY_RUN" == 1 ]]; then
    run "write $plist and load it"
  else
    printf '%s\n' "$new" > "$plist"
    launchctl bootout "gui/$(id -u)/$DOWNLOADS_LABEL" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null \
      || { warn "Downloads sorting could not start. Run: launchctl bootstrap gui/\$(id -u) $plist"; return 1; }
  fi
  ok "Downloads sorting on (rules: config/mac-setup/downloads-rules.tsv)"
}
