# shellcheck shell=bash
# The daily unattended update: a launch agent that runs `update --unattended`
# at 3:47 and after login. It applies only commits signed by a key you trust
# (lib/update-trust.sh), never asks for a password, and tells you with one
# notification when something changed or needs you. Off with: update auto off

# shellcheck source=lib/auto-update.sh
source "$REPO_DIR/lib/auto-update.sh"
# shellcheck source=lib/update-trust.sh
source "$REPO_DIR/lib/update-trust.sh"

step_auto_update() {
  if [[ "$DRY_RUN" == 1 ]]; then
    run "write $ALLOWED_SIGNERS from your git signing key (once)"
    run "write $UPDATE_AGENT_PLIST and load it (daily update)"
    return 0
  fi
  local said
  said="$(trust_init)" && [[ -n "$said" ]] && info "$said"
  if [[ "$(trusted_keys)" == 0 ]]; then
    info "Automatic updates only apply commits signed by a key in $ALLOWED_SIGNERS. It lists none, so they will ask you to run: update"
  fi
  if [[ -f "$UPDATE_AGENT_OFF" ]]; then
    ok "Automatic updates are off (turn on with: update auto on)"
    return 0
  fi
  # GitHub's test machines have no one to notify, and no use for it.
  if [[ "$CI_MODE" == 1 ]]; then
    mkdir -p "$(dirname "$UPDATE_AGENT_PLIST")" && update_agent_plist > "$UPDATE_AGENT_PLIST"
    ok "Automatic update agent written (not loaded on test machines)"
    return 0
  fi
  if ! update_agent_load; then
    warn "Automatic updates could not start. Run: update auto on"
    return 1
  fi
  ok "Automatic updates on (daily at $UPDATE_AGENT_HOUR:$UPDATE_AGENT_MINUTE and after login; off with: update auto off)"
}
