#!/usr/bin/env bash
# Grants Accessibility, Screen Recording and event posting to the journey
# driver on a CI Mac, by adding rows to the privacy database (TCC.db).
#
#   bash tests/journeys/grant-tcc.sh /path/to/journeys [more clients...]
#
# Only for throwaway CI machines: GitHub's macOS runners have System Integrity
# Protection off, which is what lets the system database be written. On a
# person's Mac the database is protected; use System Settings instead (run.sh
# asks for it). The columns are read from the database itself, so a schema
# change shows up here as a clear error rather than a silent miss.

set -uo pipefail

[ "$#" -ge 1 ] || { echo "usage: grant-tcc.sh CLIENT_PATH..." >&2; exit 2; }

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

grant "/Library/Application Support/com.apple.TCC/TCC.db" 1 "$@" || failed=1
mkdir -p "$HOME/Library/Application Support/com.apple.TCC"
grant "$HOME/Library/Application Support/com.apple.TCC/TCC.db" 0 "$@" || failed=1

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
