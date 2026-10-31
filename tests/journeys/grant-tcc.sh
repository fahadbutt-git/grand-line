#!/usr/bin/env bash
# Grants Accessibility, Screen Recording and event posting to the journey
# driver on a CI Mac, by adding rows to the privacy database (TCC.db). With
# --automation APP, the app (and the bash and osascript it runs) may also send
# Apple events to System Events, which the launcher's settings rows need: dark
# mode, the menu bar and the Dock are switched through it.
#
#   bash tests/journeys/grant-tcc.sh [--automation /path/to/App.app]... /path/to/journeys [more clients...]
#
# Only for throwaway CI machines: GitHub's macOS runners have System Integrity
# Protection off, which is what lets the system database be written. On a
# person's Mac the database is protected; use System Settings instead (run.sh
# asks for it). The columns are read from the database itself, so a schema
# change shows up here as a clear error rather than a silent miss.

set -uo pipefail

usage="usage: grant-tcc.sh [--automation APP_BUNDLE]... CLIENT_PATH..."
automation_apps=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --automation)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      automation_apps+=("$2"); shift 2 ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) break ;;
  esac
done
[ "$#" -ge 1 ] || { echo "$usage" >&2; exit 2; }

services="kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent"
clients="$* /bin/bash /bin/sh /usr/sbin/screencapture"
now="$(date +%s)"
failed=0

# grant DB USE_SUDO CLIENT...: the clients named are listed afterwards
grant() {
  local db="$1" sudo="$2" cols insert client service names values
  local sq=(sqlite3)
  [ "$sudo" = 1 ] && sq=(sudo sqlite3)
  if [ "$sudo" = 1 ]; then
    sudo test -f "$db" || { echo "no database at $db"; return 1; }
  else
    [ -f "$db" ] || { echo "no database at $db"; return 1; }
  fi
  cols="$("${sq[@]}" "$db" "SELECT group_concat(name, ' ') FROM pragma_table_info('access');" 2>&1)" || {
    echo "cannot read $db: $cols"; return 1; }
  for needed in service client client_type auth_value auth_reason auth_version; do
    case " $cols " in *" $needed "*) ;; *) echo "$db: no column $needed (columns: $cols)"; return 1 ;; esac
  done
  for client in $clients; do
    for service in $services; do
      names="service, client, client_type, auth_value, auth_reason, auth_version"
      values="'$service', '$client', 1, 2, 4, 1"
      case " $cols " in *" indirect_object_identifier "*) names="$names, indirect_object_identifier"; values="$values, 'UNUSED'" ;; esac
      case " $cols " in *" flags "*) names="$names, flags"; values="$values, 0" ;; esac
      case " $cols " in *" last_modified "*) names="$names, last_modified"; values="$values, $now" ;; esac
      case " $cols " in *" boot_uuid "*) names="$names, boot_uuid"; values="$values, 'UNUSED'" ;; esac
      case " $cols " in *" last_reminded "*) names="$names, last_reminded"; values="$values, $now" ;; esac
      insert="INSERT OR REPLACE INTO access ($names) VALUES ($values);"
      if ! out="$("${sq[@]}" "$db" "$insert" 2>&1)"; then
        echo "$db: could not grant $service to $client: $out"; return 1
      fi
    done
  done
  echo "$db:"
  shift 2
  for client in "$@"; do
    "${sq[@]}" -separator '  ' "$db" "SELECT service, client, auth_value FROM access WHERE client = '$client' ORDER BY service;" | sed 's/^/  /'
  done
}

# Automation (kTCCServiceAppleEvents): one row per sender, with System Events
# as the target in indirect_object_identifier, as the runner images grant it
# to their own agent. Senders are listed "TYPE CLIENT": 0 a bundle id, 1 a path.
target="com.apple.systemevents"
event_clients=()
for app in ${automation_apps[@]+"${automation_apps[@]}"}; do
  plist="$app/Contents/Info.plist"
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)" || id=""
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)" || exe=""
  if [ -z "$id" ] || [ -z "$exe" ]; then
    echo "--automation $app: no bundle id or executable in $plist"; failed=1; continue
  fi
  event_clients+=("0 $id" "1 $app/Contents/MacOS/$exe")
done
if [ "${#automation_apps[@]}" -gt 0 ]; then
  event_clients+=("1 /bin/bash" "1 /usr/bin/osascript")
fi

# The target's code requirement, compiled; NULL when csreq cannot make it.
target_req="NULL"
req_file="$(mktemp)"
if csreq -r="identifier \"$target\" and anchor apple" -b "$req_file" 2>/dev/null && [ -s "$req_file" ]; then
  target_req="X'$(xxd -p "$req_file" | tr -d '\n')'"
fi
rm -f "$req_file"

# grant_events DB USE_SUDO
grant_events() {
  local db="$1" sudo="$2" cols entry type client names values insert out
  local sq=(sqlite3)
  [ "$sudo" = 1 ] && sq=(sudo sqlite3)
  cols="$("${sq[@]}" "$db" "SELECT group_concat(name, ' ') FROM pragma_table_info('access');" 2>&1)" || {
    echo "cannot read $db: $cols"; return 1; }
  case " $cols " in
    *" indirect_object_identifier "*) ;;
    *) echo "$db: no column indirect_object_identifier, so Automation cannot be granted (columns: $cols)"; return 1 ;;
  esac
  for entry in "${event_clients[@]}"; do
    type="${entry%% *}"
    client="${entry#* }"
    names="service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier"
    values="'kTCCServiceAppleEvents', '${client//\'/\'\'}', $type, 2, 3, 1, '$target'"
    case " $cols " in *" indirect_object_identifier_type "*) names="$names, indirect_object_identifier_type"; values="$values, 0" ;; esac
    case " $cols " in *" indirect_object_code_identity "*) names="$names, indirect_object_code_identity"; values="$values, $target_req" ;; esac
    case " $cols " in *" flags "*) names="$names, flags"; values="$values, 0" ;; esac
    case " $cols " in *" last_modified "*) names="$names, last_modified"; values="$values, $now" ;; esac
    case " $cols " in *" boot_uuid "*) names="$names, boot_uuid"; values="$values, 'UNUSED'" ;; esac
    case " $cols " in *" last_reminded "*) names="$names, last_reminded"; values="$values, $now" ;; esac
    insert="INSERT OR REPLACE INTO access ($names) VALUES ($values);"
    if ! out="$("${sq[@]}" "$db" "$insert" 2>&1)"; then
      echo "$db: could not allow $client to control System Events: $out"; return 1
    fi
  done
  echo "$db (Automation):"
  "${sq[@]}" -separator '  ' "$db" "SELECT client, auth_value, indirect_object_identifier FROM access WHERE service = 'kTCCServiceAppleEvents' ORDER BY client;" | sed 's/^/  /'
}

grant "/Library/Application Support/com.apple.TCC/TCC.db" 1 "$@" || failed=1
mkdir -p "$HOME/Library/Application Support/com.apple.TCC"
grant "$HOME/Library/Application Support/com.apple.TCC/TCC.db" 0 "$@" || failed=1
if [ "${#event_clients[@]}" -gt 0 ]; then
  # Automation is asked per user; the system database gets the rows too.
  grant_events "$HOME/Library/Application Support/com.apple.TCC/TCC.db" 0 || failed=1
  grant_events "/Library/Application Support/com.apple.TCC/TCC.db" 1 || failed=1
fi

# macOS 15 and later also ask, now and then, before a program captures the
# screen without the system picker. The approvals file is keyed by the program
# responsible for the capture; a far-off date keeps the question away.
approvals="$HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"
mkdir -p "$(dirname "$approvals")"
for client in $clients; do
  defaults write "$approvals" "$client" -date "3024-01-01 00:00:00 +0000" 2>/dev/null || true
done
killall cfprefsd 2>/dev/null || true
# tccd reads the database again when it restarts.
sudo killall tccd 2>/dev/null || true
killall tccd 2>/dev/null || true
sleep 1

if [ "$failed" = 1 ]; then
  echo "Some grants failed (above). The runner image may already allow its agent and /bin/bash, so the driver can still work; its own permission check decides."
fi
exit 0
