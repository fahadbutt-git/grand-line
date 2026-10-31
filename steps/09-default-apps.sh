# shellcheck shell=bash
# Sets the default app for each file type, from config/mac-setup/default-apps.tsv.

step_default_apps() {
  if ! have duti && [[ "$DRY_RUN" == 0 ]]; then
    warn "duti is not installed, so default apps were not set."
    return 1
  fi
  # shellcheck source=lib/default-apps.sh
  source "$REPO_DIR/lib/default-apps.sh"
  # Keep whichever set you last chose (default-apps primary or fallback).
  local mode; mode="$(cat "$MAC_SETUP_STATE/default-apps-mode" 2>/dev/null || echo primary)"
  apply_default_apps "$mode" "$REPO_DIR/config/mac-setup/default-apps.tsv"
}
