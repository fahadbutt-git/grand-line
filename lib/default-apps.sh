# shellcheck shell=bash
# Default app per file type, read from config/mac-setup/default-apps.tsv.
# Used by the default-apps setup step and by the default-apps command.
# Needs lib/common.sh (run, ok, warn, bundle_id_of).

# apply_default_apps primary    first app in each row, its fallback if missing
# apply_default_apps fallback   the fallback app in every row
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
    local now
    now="$([[ "$DRY_RUN" == 0 ]] && duti -x "${exts%% *}" 2>/dev/null | head -1)"
    if [[ "$DRY_RUN" == 0 && "$now" != "$app.app" ]]; then
      warn "$app was set for $exts, but macOS still opens ${exts%% *} with ${now:-nothing}."
      failed=1; continue
    fi
    ok "$app opens $exts"
  done < "$table"
  return "$failed"
}
