# shellcheck shell=bash
# System settings: keyboard, Finder, screenshots, Dock, and what AeroSpace needs.

step_macos_defaults() {
  if ! first_time macos-defaults; then
    ok "System settings were set on the first run (yours are kept)"
    return 0
  fi
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

  # Dock: hidden, no recent apps, and appears at once instead of after a pause
  run defaults write com.apple.dock autohide -bool true
  run defaults write com.apple.dock autohide-delay -float 0
  run defaults write com.apple.dock autohide-time-modifier -float 0.15
  run defaults write com.apple.dock show-recents -bool false
  run defaults write com.apple.dock tilesize -int 48

  # Faster: no window-opening animation, quick sheets and Mission Control,
  # no Finder animations
  run defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  run defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
  run defaults write com.apple.dock expose-animation-duration -float 0.1
  run defaults write com.apple.finder DisableAllAnimations -bool true

  # Keyboard first, as in Omarchy: Tab moves through every control in dialogs
  run defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

  # No surprises: hot corners off (a new Mac opens Quick Note from the
  # bottom-right corner), clicking the wallpaper does not hide every window,
  # Time Machine does not ask about every new disk, no .DS_Store on USB drives
  local corner
  for corner in tl tr bl br; do run defaults write com.apple.dock "wvous-$corner-corner" -int 1; done
  run defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
  run defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
  run defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

  # Clipboard history never keeps what is copied in the clinical remote
  # apps (Citrix, Horizon), so patient information stays out of it.
  run defaults write org.p0deje.Maccy ignoredApps -array \
    com.citrix.receiver.icaviewer.mac com.citrix.receiver.nomas com.vmware.horizon com.omnissa.horizon.client.mac
  run defaults write org.p0deje.Maccy historySize -int 300

  # Screenshots without the drop shadow
  run defaults write com.apple.screencapture disable-shadow -bool true

  # Recommended by AeroSpace for tiling to work well: Spaces span displays
  # and keep their order, and macOS's own window tiling is off so the two
  # never fight over the same window
  run defaults write com.apple.spaces spans-displays -bool true
  run defaults write com.apple.dock expose-group-apps -bool true
  run defaults write com.apple.dock mru-spaces -bool false
  run defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
  run defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false
  run defaults write com.apple.WindowManager EnableTilingOptionAccelerator -bool false


  run_sh "killall Finder Dock SystemUIServer 2>/dev/null || true"
  mark_done macos-defaults
  ok "System settings applied"
}
