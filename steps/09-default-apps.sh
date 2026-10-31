# shellcheck shell=bash
# Sets the default app for each file type, from config/mac-setup/default-apps.tsv.

step_default_apps() {
  if ! have duti && [[ "$DRY_RUN" == 0 ]]; then
    warn "duti is not installed, so default apps were not set."
    return 1
  fi
  # shellcheck source=lib/default-apps.sh
  source "$REPO_DIR/lib/default-apps.sh"
  apply_default_apps primary "$REPO_DIR/config/mac-setup/default-apps.tsv"
}
