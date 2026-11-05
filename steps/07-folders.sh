# shellcheck shell=bash
# Creates the local folders and links ~/Drive to Google Drive.
#
# Where things live:
#   ~/Drive (Google Drive, My Drive)  everything to keep, in four folders:
#     0 Inbox                            new files to file (old Downloads too)
#     1 Projects                         work with an end, one folder each
#     2 Areas                            ongoing areas (Research by subspecialty)
#     3 Resources                        reference material
#   ~/Code                             code, kept local and on GitHub (Drive
#                                      sync breaks git and node_modules)
#   ~/Downloads                        an inbox, sorted by tidy-downloads
#   ~/Pictures/Screenshots             captures, never the Desktop

step_folders() {
  run mkdir -p "$SCREENSHOTS_DIR" "$BACKGROUNDS_DIR" "$CODE_DIR"
  local img
  for img in "$REPO_DIR"/backgrounds/*; do
    [[ -f "$img" && ! -f "$BACKGROUNDS_DIR/$(basename "$img")" ]] && run cp "$img" "$BACKGROUNDS_DIR/"
  done
  ok "Folders ready: Pictures/Screenshots, Pictures/Backgrounds, Code"

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
  if [[ -L "$DRIVE_LINK" && "$(readlink "$DRIVE_LINK")" == "$drive" ]]; then
    ok "Drive link (in your home folder) opens your Google Drive"
    return 0
  fi
  link_into_place "$drive" "$DRIVE_LINK"
  # New Finder windows and the first save dialog in each app open in Drive.
  run defaults write com.apple.finder NewWindowTarget -string PfLo
  run defaults write com.apple.finder NewWindowTargetPath -string "file://$DRIVE_LINK/"
  run defaults write NSGlobalDomain NSNavLastRootDirectory -string "$DRIVE_LINK"
  ok "Drive link (in your home folder) opens your Google Drive, and Finder and save dialogs start there"
}
