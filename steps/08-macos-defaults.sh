# shellcheck shell=bash
# System settings: keyboard, Finder, screenshots, Dock, and what AeroSpace needs.

step_macos_defaults() {
  # Keyboard: fast key repeat, no accent pop-up when holding a key
  run defaults write NSGlobalDomain KeyRepeat -int 2
  run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # Files: show extensions, save locally by default, expanded save dialogs
  run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
  run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

  # Drag any window with Control + Command, as Super + drag does in Omarchy
  run defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true

  # Finder: path bar, status bar, list view, folders first, search this folder
  run defaults write com.apple.finder ShowPathbar -bool true
  run defaults write com.apple.finder ShowStatusBar -bool true
  run defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
  run defaults write com.apple.finder _FXSortFoldersFirst -bool true
  run defaults write com.apple.finder FXDefaultSearchScope -string SCcf
  run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Screenshots into their own folder
  run defaults write com.apple.screencapture location -string "$SCREENSHOTS_DIR"
  run defaults write com.apple.screencapture type -string png

  # Dock: hidden, no recent apps
  run defaults write com.apple.dock autohide -bool true
  run defaults write com.apple.dock show-recents -bool false
  run defaults write com.apple.dock tilesize -int 48

  # Recommended by AeroSpace for tiling to work well
  run defaults write com.apple.spaces spans-displays -bool true
  run defaults write com.apple.dock expose-group-apps -bool true

  # Dark mode needs an Automation permission prompt, which nobody can answer
  # on an unattended test machine.
  if [[ "$CI_MODE" == 0 ]]; then
    run_sh "osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to true'" \
      || warn "Could not switch to dark mode. Set it in System Settings, Appearance."
  fi

  run_sh "killall Finder Dock SystemUIServer 2>/dev/null || true"
  ok "System settings applied"
}
