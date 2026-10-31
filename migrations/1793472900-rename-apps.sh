# shellcheck shell=bash
# The package's apps have new names and bundle ids: Log Pose is now Nexus,
# Byakugan is now Sight and Den Den is now Iceberg. This carries each app's
# settings, saved state and file index over, so nothing is rebuilt or lost,
# moves the old app to the Trash, and hands folders and Command + Space to the
# new apps (the remembered takeover-files and takeover-search choices are kept,
# and the default browser is left alone).
#
# Setup's native-tools step also runs this, every run, right after it installs
# the new apps and before anything starts them, so their first launch finds the
# moved files. It is safe to run any number of times and does nothing on a Mac
# that never had the old apps. An old app whose replacement is not installed
# yet (its build failed) is left exactly as it is until a later run.
source "$GRAND_LINE_REPO/lib/bin-common.sh"
# shellcheck source=lib/default-apps.sh
source "$GRAND_LINE_REPO/lib/default-apps.sh"
# shellcheck source=lib/takeover.sh
source "$GRAND_LINE_REPO/lib/takeover.sh"

APPS="${GRAND_LINE_APPS_DEST:-/Applications}"
SUPPORT="$HOME/Library/Application Support"
CONFIG="$HOME/.config/grand-line"
status=0
retired=""   # old apps moved to the Trash in this run, as a list for people
restart=()   # bundle ids of new apps to start, because the old one was running
notes=()
kept=()      # old folders left beside new ones, worth a word only in the run that retires the app

# move_once FROM TO: FROM becomes TO, unless TO already exists (then both stay).
move_once() {
  [[ -e "$1" || -L "$1" ]] || return 0
  if [[ -e "$2" || -L "$2" ]]; then
    kept+=("Kept both $1 and $2; the new app uses the second.")
    return 0
  fi
  mkdir -p "$(dirname "$2")" && mv "$1" "$2" && echo "Moved $1 to $2" && return 0
  echo "Could not move $1 to $2." >&2
  status=1
}

# any_keys DOMAIN: the domain holds settings. own_keys DOMAIN: the same,
# ignoring TakesCommandSpace, which setup writes itself (and writes again below).
any_keys() { defaults export "$1" - 2>/dev/null | grep -q '<key>'; }
own_keys() {
  defaults export "$1" - 2>/dev/null | grep '<key>' | grep -qv '<key>TakesCommandSpace</key>'
}

# copy_defaults OLD NEW [SED]: the old domain's settings into the new one when
# the new one has none of its own yet. SED renames keys on the way.
copy_defaults() {
  own_keys "$1" || return 0
  own_keys "$2" && return 0
  if defaults export "$1" - | sed "${3:-s/^//}" | defaults import "$2" -; then
    echo "Copied the settings of $1 to $2"
  else
    echo "Could not copy the settings of $1 to $2." >&2
    status=1
  fi
}

# ready OLD NEW: whether the old app can be retired. An old app stays while its
# replacement is missing, so the Mac is never left without it.
ready() {
  if [[ -d "$APPS/$1.app" && ! -d "$APPS/$2.app" ]]; then
    notes+=("$2 is not installed yet, so $1 stays for now. Run: update")
    return 1
  fi
  return 0
}

# quit PROCESS NEW_ID: stop the old app before its files move, and remember to
# start the new one if it was running.
quit() {
  pgrep -x "$1" >/dev/null 2>&1 || return 0
  restart+=("$2")
  pkill -x "$1" 2>/dev/null
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$1" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

# retire OLD: the old app bundle goes to the Trash.
retire() {
  [[ -d "$APPS/$1.app" ]] || return 0
  if move_to_trash "$APPS/$1.app"; then
    retired="${retired:+$retired, }$1"
    echo "Moved $1 to the Trash"
  else
    echo "Could not move $APPS/$1.app to the Trash." >&2
    status=1
  fi
}

# Log Pose to Nexus: view settings, workspaces, Put Back records, recents, the
# hidden sidebar items and the name index (Application Support), settings and
# saved searches (~/.config), the selection file and the window's place.
nexus_retired=0
if ready "Log Pose" Nexus; then
  quit LogPose com.grandline.nexus
  move_once "$SUPPORT/Log Pose" "$SUPPORT/Nexus"
  move_once "$CONFIG/logpose" "$CONFIG/nexus"
  move_once "$GRAND_LINE_STATE/logpose-selection" "$GRAND_LINE_STATE/nexus-selection"
  copy_defaults com.grandline.logpose com.grandline.nexus 's/NSWindow Frame LogPoseBrowser/NSWindow Frame NexusBrowser/'
  [[ -d "$APPS/Log Pose.app" ]] && nexus_retired=1
  retire "Log Pose"
fi

# Byakugan to Sight: learned ranking, the name index and exchange rates
# (Application Support), aliases, quicklinks and providers (~/.config), and its
# defaults (CloseAfterSettingChange and the rest; TakesCommandSpace is set again
# by the takeover below).
sight_retired=0
if ready Byakugan Sight; then
  quit Byakugan com.grandline.sight
  move_once "$SUPPORT/Byakugan" "$SUPPORT/Sight"
  move_once "$CONFIG/byakugan" "$CONFIG/sight"
  copy_defaults com.grandline.byakugan com.grandline.sight
  if [[ -d "$APPS/Byakugan.app" ]]; then
    sight_retired=1
    # Should macOS still start the old copy at login, it must not take
    # Command + Space from Sight.
    any_keys com.grandline.byakugan && defaults write com.grandline.byakugan TakesCommandSpace -bool false
  fi
  retire Byakugan
fi

# Den Den to Iceberg: denden.toml and the widgets (~/.config), the Now Playing
# adapter copy (Application Support, made again if missing), the log, and the
# Settings window's place. iceberg:// is the new URL scheme; Iceberg answers
# denden:// too for one release, so old shortcuts keep working.
if ready "Den Den" Iceberg; then
  quit DenDen com.grandline.iceberg
  move_once "$CONFIG/denden" "$CONFIG/iceberg"
  move_once "$CONFIG/iceberg/denden.toml" "$CONFIG/iceberg/iceberg.toml"
  move_once "$SUPPORT/Den Den" "$SUPPORT/Iceberg"
  move_once "$GRAND_LINE_LOGS/denden.log" "$GRAND_LINE_LOGS/iceberg.log"
  copy_defaults com.grandline.denden com.grandline.iceberg 's/NSWindow Frame DenDenSettings/NSWindow Frame IcebergSettings/'
  retire "Den Den"
fi

# Folders and Command + Space named the old bundle ids: hand them to the new
# apps, keeping the choice made with toggle files and toggle search.
if [[ "$nexus_retired" == 1 && -d "$NEXUS_APP" ]]; then
  takeover_files "$(takeover_mode files)" && echo "Folders open in $( [[ "$(takeover_mode files)" == on ]] && echo Nexus || echo Finder)"
fi
if [[ "$sight_retired" == 1 && -d "$SIGHT_APP" ]]; then
  takeover_search "$(takeover_mode search)" && echo "Command + Space opens $( [[ "$(takeover_mode search)" == on ]] && echo Sight || echo Spotlight)"
fi

# Start again what was running (takeover_search already started Sight).
for id in "${restart[@]}"; do
  [[ "$id" == com.grandline.sight && "$sight_retired" == 1 ]] && continue
  launch_quietly "$id"
done

# Said once, in the run that retires an old app.
if [[ -n "$retired" ]]; then
  notes+=("${kept[@]}")
  # Your own scripts may read the old variable names.
  old_vars="$(grep -rlE 'BYAKUGAN_QUERY|GRAND_LINE_DENDEN_' "$CONFIG/sight" "$CONFIG/iceberg" 2>/dev/null)"
  if [[ -n "$old_vars" ]]; then
    notes+=("These files use the old names BYAKUGAN_QUERY or GRAND_LINE_DENDEN_*; rename them to SIGHT_QUERY and GRAND_LINE_ICEBERG_*: $(tr '\n' ' ' <<<"$old_vars")")
  fi
  # Apps register their own login items, and only an app can remove its own.
  notes+=("If System Settings, General, Login Items still lists $retired, select it and click the minus button. The new apps add themselves when they start.")
  # Permissions belong to a bundle id, so macOS asks the new apps again.
  notes+=("macOS asks again for the new apps' permissions: allow Sight under Privacy & Security, Accessibility, and Iceberg's Calendars and Reminders when asked. The old names can be removed from those lists.")
fi

for n in "${notes[@]}"; do echo "$n"; done
exit "$status"
