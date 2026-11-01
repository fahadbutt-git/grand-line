# shellcheck shell=bash
# The daily unattended update (bin/update --unattended) and the lock that
# keeps setup and updates from running at the same time.
# Sourced by setup.sh (through steps/15-auto-update.sh) and bin/update.

# shellcheck source=lib/lock.sh
source "$(dirname "${BASH_SOURCE[0]}")/lock.sh"

UPDATE_AGENT_LABEL="com.grandline.update"
UPDATE_AGENT_PLIST="$HOME/Library/LaunchAgents/$UPDATE_AGENT_LABEL.plist"
# shellcheck disable=SC2034  # read by setup.sh, the step and bin/update
UPDATE_AGENT_OFF="$GRAND_LINE_STATE/auto-update-off"
UPDATE_LOCK="${GRAND_LINE_UPDATE_LOCK:-$GRAND_LINE_STATE/update.lock}"
# A quiet hour. A Mac asleep then runs it when it wakes.
UPDATE_AGENT_HOUR=3
UPDATE_AGENT_MINUTE=47

# The agent runs at login too, three minutes later so login stays quick, and
# at low priority: background CPU and disk, niced.
update_agent_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$UPDATE_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$GRAND_LINE_BIN/update</string><string>--unattended</string><string>--delay</string><string>180</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$UPDATE_AGENT_HOUR</integer><key>Minute</key><integer>$UPDATE_AGENT_MINUTE</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>15</integer>
  <key>StandardOutPath</key><string>$GRAND_LINE_LOGS/update.log</string>
  <key>StandardErrorPath</key><string>$GRAND_LINE_LOGS/update.log</string>
</dict>
</plist>
PLIST
}

update_agent_loaded() {
  launchctl print "gui/$(id -u)/$UPDATE_AGENT_LABEL" >/dev/null 2>&1
}

# update_agent_load: write the plist and load it, unless it is already
# loaded as it is. Returns 1 when macOS would not load it.
update_agent_load() {
  local domain new _
  domain="gui/$(id -u)"
  new="$(update_agent_plist)"
  if [[ -f "$UPDATE_AGENT_PLIST" && "$(cat "$UPDATE_AGENT_PLIST")" == "$new" ]] && update_agent_loaded; then
    return 0
  fi
  mkdir -p "$(dirname "$UPDATE_AGENT_PLIST")" "$GRAND_LINE_LOGS"
  printf '%s\n' "$new" > "$UPDATE_AGENT_PLIST"
  launchctl bootout "$domain/$UPDATE_AGENT_LABEL" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    update_agent_loaded || break
    sleep 0.5
  done
  for _ in 1 2 3; do
    launchctl bootstrap "$domain" "$UPDATE_AGENT_PLIST" 2>/dev/null && break
    sleep 1
  done
  update_agent_loaded
}

# update_agent_unload: stop it and put its file in the Trash.
update_agent_unload() {
  launchctl bootout "gui/$(id -u)/$UPDATE_AGENT_LABEL" 2>/dev/null
  [[ -e "$UPDATE_AGENT_PLIST" ]] && move_to_trash "$UPDATE_AGENT_PLIST"
  return 0
}

# update_lock_take: one setup or update at a time (lib/lock.sh). A lock left
# by a run that no longer exists is taken over. Fails when another run holds
# it, naming its process in UPDATE_LOCK_HOLDER.
update_lock_take() {
  if ! lock_take "$UPDATE_LOCK"; then
    # shellcheck disable=SC2034  # the caller names it in its message
    UPDATE_LOCK_HOLDER="$LOCK_HOLDER"
    return 1
  fi
  export GRAND_LINE_LOCK_HELD=1
}

update_lock_release() {
  lock_release "$UPDATE_LOCK"
}
