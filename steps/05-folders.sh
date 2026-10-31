# shellcheck shell=bash
# Creates the local folders and links ~/Drive to Google Drive.
#
# Where things live:
#   ~/Drive (Google Drive, My Drive)  documents, research, everything to keep
#   ~/Developer                        code, kept local and on GitHub (Drive
#                                      sync breaks git and node_modules)
#   ~/Downloads                        an inbox, sorted by tidy-downloads
#   ~/Pictures/Screenshots             captures, never the Desktop

step_folders() {
  run mkdir -p "$SCREENSHOTS_DIR" "$BACKGROUNDS_DIR" "$HOME/Developer"
  local img
  for img in "$REPO_DIR"/backgrounds/*; do
    [[ -f "$img" && ! -f "$BACKGROUNDS_DIR/$(basename "$img")" ]] && run cp "$img" "$BACKGROUNDS_DIR/"
  done
  ok "Folders ready: Pictures/Screenshots, Pictures/Backgrounds, Developer"

  # Google Drive appears only after signing in, so this part waits until then
  # (the update command runs this step again).
  local dir drive=""
  for dir in "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive"; do
    [[ -d "$dir" ]] && { drive="$dir"; break; }
  done
  if [[ -z "$drive" ]]; then
    info "Google Drive is not signed in yet. After signing in, run: update"
    return 0
  fi
  link_into_place "$drive" "$DRIVE_LINK"
  # New Finder windows and the first save dialog in each app open in Drive.
  run defaults write com.apple.finder NewWindowTarget -string PfLo
  run defaults write com.apple.finder NewWindowTargetPath -string "file://$DRIVE_LINK/"
  run defaults write NSGlobalDomain NSNavLastRootDirectory -string "$DRIVE_LINK"
  ok "Drive link (in your home folder) opens your Google Drive, and Finder and save dialogs start there"
}
