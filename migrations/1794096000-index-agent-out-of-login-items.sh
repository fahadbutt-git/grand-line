# shellcheck shell=bash
# grandline:unattended
# Grand Line Index used to carry its launch agent inside the app and register
# it with Login Items (SMAppService), and macOS said "Grand Line Index can run
# in the background" at every login. It now starts from a plain launch agent
# in ~/Library/LaunchAgents, the way the Downloads agent does, which macOS
# mentions once. On a Mac set up earlier this:
#   removes the old Login Items registration (GrandLineIndex --unregister;
#   a copy with nothing registered says so and that is fine)
#   writes ~/Library/LaunchAgents/com.grandline.index.plist and loads it, when
#   it is missing, different or not loaded
# Nothing is deleted and no other setting is changed. Safe to run again: once
# the agent is in place it changes nothing.
source "$GRAND_LINE_REPO/lib/bin-common.sh"
# shellcheck source=lib/service-agents.sh
source "$GRAND_LINE_REPO/lib/service-agents.sh"

app="${GRAND_LINE_APPS_DEST:-/Applications}/Grand Line Index.app"
program="$app/Contents/MacOS/GrandLineIndex"
tpl="$GRAND_LINE_REPO/apps/finder/LaunchAgents/GrandLineIndex.plist"

# Not installed (yet): setup starts it when it installs it.
[[ -x "$program" ]] || exit 0

# The old registration. Failure is not an error: there may be none.
"$program" --unregister >/dev/null 2>&1

if service_agent_ensure "$tpl" "$program"; then
  [[ "$SERVICE_AGENT_STARTED" == 1 ]] && echo "Grand Line Index now starts at login from ~/Library/LaunchAgents/com.grandline.index.plist"
  exit 0
fi
echo "Grand Line Index could not be started in the background. The next update tries again." >&2
exit 1
