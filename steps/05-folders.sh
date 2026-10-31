# shellcheck shell=bash
# Creates the screenshots, backgrounds and developer folders.

step_folders() {
  run mkdir -p "$SCREENSHOTS_DIR" "$BACKGROUNDS_DIR" "$HOME/Developer"
  local img
  for img in "$REPO_DIR"/backgrounds/*; do
    [[ -f "$img" && ! -f "$BACKGROUNDS_DIR/$(basename "$img")" ]] && run cp "$img" "$BACKGROUNDS_DIR/"
  done
  ok "Folders ready: Pictures/Screenshots, Pictures/Backgrounds, Developer"
}
