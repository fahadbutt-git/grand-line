# shellcheck shell=bash
# Sets the default app for each file type, from config/grand-line/default-apps.tsv.

step_default_apps() {
  if ! have duti && [[ "$DRY_RUN" == 0 ]]; then
    warn "duti is not installed, so default apps were not set."
    return 1
  fi
  # shellcheck source=lib/default-apps.sh
  source "$REPO_DIR/lib/default-apps.sh"
  # Keep whichever set you last chose (default-apps primary or fallback).
  local mode; mode="$(cat "$GRAND_LINE_STATE/default-apps-mode" 2>/dev/null || echo primary)"
  local status=0
  apply_default_apps "$mode" "$REPO_DIR/config/grand-line/default-apps.tsv" || status=1
  # Zen for links and web pages, set once so a browser you pick later stays.
  if first_time default-browser && [[ -d /Applications/Zen.app ]]; then
    run set_default_browser app.zen-browser.zen && ok "Links open in Zen" && mark_done default-browser
  fi
  # Log Pose for folders and Byakugan for Command + Space, once installed.
  # shellcheck source=lib/takeover.sh
  source "$REPO_DIR/lib/takeover.sh"
  apply_takeovers
  return "$status"
}
