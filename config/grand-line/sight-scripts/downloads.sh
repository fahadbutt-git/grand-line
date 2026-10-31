#!/usr/bin/env bash
# A Sight script command, as an example. It does nothing until copied:
#   mkdir -p ~/.config/grand-line/sight/scripts
#   cp ~/.grand-line/config/grand-line/sight-scripts/downloads.sh ~/.config/grand-line/sight/scripts/
# Then type "downloads" in Sight. The protocol is in apps/finder/README.md
# (Script commands): print one JSON object per line; a chosen row's value
# comes back as the only argument; {"close": true} closes the window.

set -uo pipefail

# A JSON string: backslashes, quotes and tabs escaped.
json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

row() { # title subtitle icon value
  printf '{"title": %s, "subtitle": %s, "icon": %s, "value": %s}\n' \
    "$(json "$1")" "$(json "$2")" "$(json "$3")" "$(json "$4")"
}

folder="$HOME/Downloads"
choice="${1:-}"

case "$choice" in
  "")
    # The first step: the twenty newest files.
    count=0
    while IFS= read -r name; do
      [[ -z "$name" || "$name" == .* ]] && continue
      row "$name" "Downloads" "doc" "file:$folder/$name"
      count=$((count + 1))
      [[ "$count" -ge 20 ]] && break
    done < <(ls -t "$folder" 2>/dev/null)
    [[ "$count" -gt 0 ]] || row "Downloads is empty" "Nothing to show" "tray" "none"
    ;;
  file:*)
    # The second step: what to do with the chosen file.
    path="${choice#file:}"
    row "Open" "${path##*/}" "arrow.up.forward" "open:$path"
    row "Show in Nexus" "${path##*/}" "folder" "reveal:$path"
    row "Copy path" "$path" "doc.on.clipboard" "copy:$path"
    ;;
  open:*) open "${choice#open:}"; echo '{"close": true}' ;;
  reveal:*) open -R "${choice#reveal:}"; echo '{"close": true}' ;;
  copy:*) printf '%s' "${choice#copy:}" | pbcopy; echo '{"close": true}' ;;
  *) echo '{"close": true}' ;;
esac
