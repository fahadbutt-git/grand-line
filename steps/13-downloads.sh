# shellcheck shell=bash
# Keeps Downloads sorted. macOS starts tidy-downloads whenever the folder
# changes (and hourly, for the age rules) at low priority. No process stays
# running between sorts.

DOWNLOADS_LABEL="mac-setup.downloads"

# The launcher built from tools/downloads-agent.swift, or bash if it is missing.
downloads_program() {
  if [[ -x "$MAC_SETUP_BUILD/downloads-agent" ]]; then
    echo "<string>$MAC_SETUP_BUILD/downloads-agent</string><string>run</string>"
  else
    echo "<string>/bin/bash</string><string>$MAC_SETUP_BIN/tidy-downloads</string>"
  fi
}

downloads_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$DOWNLOADS_LABEL</string>
  <key>ProgramArguments</key>
  <array>$(downloads_program)</array>
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
  local plist="$HOME/Library/LaunchAgents/$DOWNLOADS_LABEL.plist" new domain
  domain="gui/$(id -u)"
  new="$(downloads_plist)"
  if [[ "$DRY_RUN" == 1 ]]; then
    run "write $plist and load it"
    return 0
  fi
  if [[ -f "$plist" && "$(cat "$plist")" == "$new" ]] && launchctl print "$domain/$DOWNLOADS_LABEL" >/dev/null 2>&1; then
    ok "Downloads sorting already on"
    return 0
  fi
  mkdir -p "$HOME/Library/LaunchAgents"
  printf '%s\n' "$new" > "$plist"
  # Unload any old copy and wait until macOS has finished, then load.
  launchctl bootout "$domain/$DOWNLOADS_LABEL" 2>/dev/null
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "$domain/$DOWNLOADS_LABEL" >/dev/null 2>&1 || break
    sleep 0.5
  done
  for _ in 1 2 3; do
    launchctl bootstrap "$domain" "$plist" 2>/dev/null && break
    sleep 1
  done
  if ! launchctl print "$domain/$DOWNLOADS_LABEL" >/dev/null 2>&1; then
    warn "Downloads sorting could not start. Run: bash ~/mac-setup/setup.sh --only downloads"
    return 1
  fi
  ok "Downloads sorting on (rules: config/mac-setup/downloads-rules.tsv)"
}
