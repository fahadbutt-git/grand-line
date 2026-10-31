# shellcheck shell=bash
# Applies the starting theme once. Later changes come from: theme pick

step_theme() {
  if [[ -f "$MAC_SETUP_STATE/theme" ]]; then
    ok "Keeping the current theme: $(cat "$MAC_SETUP_STATE/theme")"
    return 0
  fi
  if [[ "$CI_MODE" == 1 ]]; then
    run "$REPO_DIR/bin/theme" set graphite --no-wallpaper
  else
    run "$REPO_DIR/bin/theme" set graphite
  fi
}
