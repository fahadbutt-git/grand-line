# shellcheck shell=bash
# Removes the apps Apple preinstalls that the package replaces, and starts the
# Dock with only what you use. Everything goes to the Trash, so it can be put
# back. Apple's system apps (Mail, Photos, Music...) are part of the sealed
# system and cannot be removed; the Dock and the Caps menus keep them out of
# the way instead.

# App              replaced by
#   Pages          WordCraft and LibreOffice
#   Numbers        GridCraft and LibreOffice
#   Keynote        DeckCraft and LibreOffice
#   iMovie         FilmCraft
#   GarageBand     not needed (with its 2 to 6 GB sound library)
DECLUTTER_APPS=(Pages Numbers Keynote iMovie GarageBand)
DECLUTTER_DATA=("/Library/Application Support/GarageBand" "/Library/Application Support/Logic" "/Library/Audio/Apple Loops")

# The Dock starts with these; anything you add later is kept.
DOCK_APPS=(/Applications/Google\ Chrome.app /Applications/Ghostty.app /Applications/Claude.app /Applications/WordCraft.app)


step_declutter() {
  local app path removed=0
  for app in "${DECLUTTER_APPS[@]}"; do
    path="/Applications/$app.app"
    [[ -d "$path" ]] || continue
    trash_path "$path" && removed=$((removed + 1))
  done
  # The sound library is shared with Logic Pro and MainStage: keep it if either is here.
  if [[ ! -d /Applications/GarageBand.app && ! -d "/Applications/Logic Pro.app" && ! -d /Applications/MainStage.app ]]; then
    for path in "${DECLUTTER_DATA[@]}"; do trash_path "$path"; done
  fi

  # The Dock, once: only on the first run, so your own changes stay.
  local flag="$MAC_SETUP_STATE/dock-set"
  if [[ ! -f "$flag" ]]; then
    run defaults write com.apple.dock persistent-apps -array
    run defaults write com.apple.dock persistent-others -array
    for app in "${DOCK_APPS[@]}"; do
      [[ -d "$app" || "$DRY_RUN" == 1 ]] || continue
      run defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    done
    run mkdir -p "$MAC_SETUP_STATE"
    run touch "$flag"
    run_sh "killall Dock 2>/dev/null || true"
  fi
  ok "Preinstalled apps the package replaces are in the Trash ($removed this run), and the Dock is minimal"
}
