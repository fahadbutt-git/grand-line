# shellcheck shell=bash
# The launch agents of the package's background services (Grand Line Index).
# Each is a plain plist in ~/Library/LaunchAgents, written from the app
# folder's template apps/<folder>/LaunchAgents/<product>.plist with @PROGRAM@
# replaced by the installed program, and loaded with launchctl bootstrap, as
# you, never with sudo. That is how the Downloads agent starts too: macOS
# says once that a background item was added, and not again at each login.
# It is written and loaded again only when its text changed or it is not
# loaded, so a normal update never registers it anew.
# Needs only launchctl and id; the steps, the migrations and the tests use it.

# service_agent_template DIR PRODUCT: the template of a product that is a
# background service, or nothing.
service_agent_template() {
  local tpl="$1/LaunchAgents/$2.plist"
  [[ -f "$tpl" ]] && echo "$tpl"
  return 0
}

# service_agent_label TEMPLATE: its launchd label.
service_agent_label() {
  sed -n 's#.*<key>Label</key><string>\([^<]*\)</string>.*#\1#p' "$1" | head -1
}

# service_agent_plist TEMPLATE PROGRAM: the plist as it goes in ~/Library/LaunchAgents.
service_agent_plist() {
  local text
  text="$(cat "$1")"
  printf '%s\n' "${text//@PROGRAM@/"$2"}"
}

# service_agent_path LABEL: where its plist goes.
service_agent_path() {
  echo "$HOME/Library/LaunchAgents/$1.plist"
}

# service_agent_loaded LABEL: launchd has the job.
service_agent_loaded() {
  launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1
}

# service_agent_ensure TEMPLATE PROGRAM: the agent's plist is written and
# loaded. Nothing changes when the plist already says the same and the job is
# loaded. SERVICE_AGENT_STARTED is 1 when this call loaded it. Fails when the
# job is not loaded afterwards.
service_agent_ensure() {
  local tpl="$1" program="$2" label plist new domain _
  # shellcheck disable=SC2034 # read by the callers
  SERVICE_AGENT_STARTED=0
  label="$(service_agent_label "$tpl")"
  [[ -n "$label" ]] || return 1
  plist="$(service_agent_path "$label")"
  domain="gui/$(id -u)"
  new="$(service_agent_plist "$tpl" "$program")"
  if [[ -f "$plist" && "$(cat "$plist")" == "$new" ]] && service_agent_loaded "$label"; then
    return 0
  fi
  mkdir -p "$HOME/Library/LaunchAgents" || return 1
  printf '%s\n' "$new" > "$plist" || return 1
  # Unload any old copy and wait until macOS has finished, then load.
  launchctl bootout "$domain/$label" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    service_agent_loaded "$label" || break
    sleep 0.5
  done
  for _ in 1 2 3; do
    launchctl bootstrap "$domain" "$plist" 2>/dev/null && break
    sleep 1
  done
  service_agent_loaded "$label" || return 1
  # shellcheck disable=SC2034
  SERVICE_AGENT_STARTED=1
}

# service_agent_unregister_legacy APP PRODUCT LABEL: an app built before
# the agent moved to ~/Library/LaunchAgents carried it in its bundle and
# registered it with SMAppService, which macOS kept announcing at every
# login. Its own --unregister removes that registration (and stops that job)
# while the bundle still holds the plist. Does nothing for a newer bundle.
service_agent_unregister_legacy() {
  local app="$1" product="$2" label="$3"
  [[ -f "$app/Contents/Library/LaunchAgents/$label.plist" && -x "$app/Contents/MacOS/$product" ]] || return 0
  "$app/Contents/MacOS/$product" --unregister >/dev/null 2>&1
  return 0
}
