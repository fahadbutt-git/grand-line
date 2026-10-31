# shellcheck shell=bash
# Default app per file type, read from config/grand-line/default-apps.tsv.
# Used by the default-apps setup step and by the default-apps command.
# Needs lib/common.sh (run, ok, warn, bundle_id_of).

# apply_default_apps primary    first app in each row, its fallback if missing
# apply_default_apps fallback   the fallback app in every row
# Writes the default app for one type into macOS's own settings file,
# replacing any earlier entry for that type so the list never grows.
LS_PREFS=com.apple.LaunchServices/com.apple.launchservices.secure
# set_ls_handler TYPE ID [KEY]: KEY is LSHandlerContentType (a file type, the
# default) or LSHandlerURLScheme (a link such as https).
set_ls_handler() {
  local uti="$1" id="$2" key="${3:-LSHandlerContentType}" work; work="$(mktemp -d)"
  if defaults export "$LS_PREFS" "$work/ls.plist" 2>/dev/null \
     && plutil -convert json -o "$work/ls.json" "$work/ls.plist" 2>/dev/null \
     && jq --arg k "$key" --arg u "$uti" --arg i "$id" '.LSHandlers = ([.LSHandlers[]? | select(.[$k] != $u)]
          + [{($k): $u, LSHandlerRoleAll: $i, LSHandlerPreferredVersions: {LSHandlerRoleAll: "-"}}])' \
          "$work/ls.json" > "$work/new.json" \
     && plutil -convert xml1 -o "$work/new.plist" "$work/new.json" \
     && defaults import "$LS_PREFS" "$work/new.plist"; then
    :
  else
    # The settings file holds a value JSON cannot express: add the entry instead.
    defaults write "$LS_PREFS" LSHandlers -array-add \
      "{$key=\"$uti\";LSHandlerRoleAll=\"$id\";LSHandlerPreferredVersions={LSHandlerRoleAll=\"-\";};}"
  fi
  rm -rf "$work"
}

# set_default_browser ID: links and web pages open in this app. Written where
# macOS keeps the choice, which avoids its "change your default browser?" prompt.
set_default_browser() {
  local id="$1" scheme
  for scheme in http https; do set_ls_handler "$scheme" "$id" LSHandlerURLScheme; done
  set_ls_handler public.html "$id"
  set_ls_handler public.xhtml "$id"
  killall lsd 2>/dev/null
  return 0
}

# The app that opens files with this extension now, as "Name.app".
default_app_for() { duti -x "${1#.}" 2>/dev/null | head -1; }

apply_default_apps() {
  local mode="${1:-primary}" table="$2"
  local primary exts fallback app id ext failed=0
  while IFS=$'\t' read -r primary exts fallback; do
    [[ -z "$primary" || "$primary" == \#* ]] && continue
    app="$primary"
    [[ "$mode" == fallback ]] && app="$fallback"
    id="$(bundle_id_of "$app")"
    if [[ -z "$id" && "$app" != "$fallback" ]]; then
      [[ "$DRY_RUN" == 0 ]] && warn "$app is not installed. Using $fallback for $exts for now."
      app="$fallback"; id="$(bundle_id_of "$app")"
    fi
    if [[ -z "$id" && "$DRY_RUN" == 1 ]]; then
      id="bundle.id.of.$app"
    fi
    if [[ -z "$id" ]]; then
      warn "Neither $primary nor $fallback is installed, so $exts keep their current app."
      failed=1; continue
    fi
    register_app "$(app_path_of "$app")"
    for ext in $exts; do
      run duti -s "$id" "$ext" all || failed=1
    done
    # duti can report success while macOS keeps the old app, so read it back.
    # If macOS refused, try again through NSWorkspace (tools/setdefault.swift).
    if [[ "$DRY_RUN" == 0 && "$(default_app_for "${exts%% *}")" != "$app.app" ]]; then
      local helper="$GRAND_LINE_BUILD/setdefault"
      # The extension list (from default-apps.tsv in the package) is split on purpose.
      # shellcheck disable=SC2086
      [[ -x "$helper" ]] && "$helper" "$(app_path_of "$app")" $exts >/dev/null
      # Last resort: write the setting where macOS keeps it, then restart the
      # service that reads it (it starts again by itself).
      if [[ -x "$helper" && "$(default_app_for "${exts%% *}")" != "$app.app" ]]; then
        local uti
        for ext in $exts; do
          uti="$("$helper" --uti "${ext#.}")" || continue
          set_ls_handler "$uti" "$id"
        done
        killall lsd 2>/dev/null; sleep 1
      fi
      local now; now="$(default_app_for "${exts%% *}")"
      if [[ "$now" != "$app.app" ]]; then
        warn "macOS kept ${now:-no app} for $exts instead of $app. To fix by hand: select a ${exts%% *} file in Finder, Get Info, Open with, $app, Change All."
        failed=1; continue
      fi
    fi
    ok "$app opens $exts"
  done < "$table"
  return "$failed"
}
