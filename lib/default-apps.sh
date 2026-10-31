# shellcheck shell=bash
# Default app per file type, read from config/mac-setup/default-apps.tsv.
# Used by the default-apps setup step and by the default-apps command.
# Needs lib/common.sh (run, ok, warn, bundle_id_of).

# apply_default_apps primary    first app in each row, its fallback if missing
# apply_default_apps fallback   the fallback app in every row
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
      local helper="$MAC_SETUP_BUILD/setdefault"
      [[ -x "$helper" ]] && "$helper" "$(app_path_of "$app")" $exts >/dev/null
      # Last resort: write the setting where macOS keeps it, then restart the
      # service that reads it (it starts again by itself).
      if [[ -x "$helper" && "$(default_app_for "${exts%% *}")" != "$app.app" ]]; then
        local uti
        for ext in $exts; do
          uti="$("$helper" --uti "${ext#.}")" || continue
          defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add \
            "{LSHandlerContentType=\"$uti\";LSHandlerRoleAll=\"$id\";LSHandlerPreferredVersions={LSHandlerRoleAll=\"-\";};}"
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
