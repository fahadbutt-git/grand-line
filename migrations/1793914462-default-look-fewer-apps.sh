# shellcheck shell=bash
# The package no longer changes how macOS or any other app looks, no longer
# installs Nexus, Ghostty, Espanso, Citrix Workspace or Tailscale, and
# folders open in Finder again. On a Mac set up earlier this puts back:
#   macOS: the Light appearance, the system accent and highlight colours, the
#     default wallpaper (only while the package's own picture is showing),
#     and the Dock, desktop icons, animations, hot corners, window tiling,
#     Spaces and Finder views as macOS has them
#   other apps: the colours the package wrote for btop, lazygit and Claude
#     Code, and its rendered theme files, go
#   Nexus: quit, moved to the Trash, and Finder opens folders again
#   Ghostty, Espanso, Citrix Workspace and Tailscale: uninstalled with
#     Homebrew (their settings and data are kept), and the package's links
#     to their settings go to the Trash
# Only what the package itself wrote is removed, files to the Trash, so
# nothing of yours is lost. It changes only what setup changed (each part
# checks setup's record of it first) and is safe to run again.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

APPS="${GRAND_LINE_APPS_DEST:-/Applications}"
LS_PREFS=com.apple.LaunchServices/com.apple.launchservices.secure
status=0
restart_ui=0
notes=()

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# trash_own PATH: PATH goes to the Trash when it is there.
trash_own() {
  [[ -e "$1" || -L "$1" ]] || return 0
  if move_to_trash "$1"; then echo "Moved $1 to the Trash"
  else echo "Could not move $1 to the Trash." >&2; status=1; fi
}

# links_into DIR PATH: PATH is a link whose target is inside DIR.
links_into() { [[ -L "$2" && "$(readlink "$2")" == *"$1"* ]]; }

# quit_app PROCESS: ask the app to quit, and wait up to five seconds.
quit_app() {
  pgrep -x "$1" >/dev/null 2>&1 || return 0
  pkill -x "$1" 2>/dev/null
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$1" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

# --- macOS appearance, accent colour and wallpaper (set by the theme step)
# A run that stopped early (Ghostty still open) does not do these twice.
looks_done="$GRAND_LINE_STATE/default-look-restored"
if [[ -f "$GRAND_LINE_STATE/theme" && ! -f "$looks_done" ]]; then
  if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == Dark ]]; then
    if osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null 2>&1; then
      echo "macOS is back to the Light appearance"
    else
      notes+=("macOS could not be switched to Light from here. In System Settings, Appearance, choose Light.")
    fi
  fi
  defaults delete -g AppleAccentColor >/dev/null 2>&1
  defaults delete -g AppleHighlightColor >/dev/null 2>&1
  echo "The accent and highlight colours are back to the system's"

  # The wallpaper goes back only while it is one of the package's pictures,
  # and only to Apple's default picture when that file is there.
  default_pic=/System/Library/CoreServices/DefaultDesktop.heic
  pictures="$(osascript -e 'tell application "System Events" to get picture of every desktop' 2>/dev/null)"
  if [[ -z "$pictures" ]]; then
    notes+=("The wallpaper could not be read, so it was left as it is. To change it: System Settings, Wallpaper.")
  elif [[ "$pictures" == *"$BACKGROUNDS_DIR/"* || "$pictures" == *"$GRAND_LINE_REPO/backgrounds/"* || "$pictures" == *"$GRAND_LINE_LINK/backgrounds/"* ]]; then
    if [[ -f "$default_pic" ]] && osascript - "$default_pic" <<'EOF' >/dev/null 2>&1
on run argv
  tell application "System Events" to tell every desktop to set picture to (POSIX file (item 1 of argv))
end run
EOF
    then
      echo "The wallpaper is back to macOS's default"
    else
      notes+=("The package's wallpaper is still showing. To change it: System Settings, Wallpaper, and choose one of Apple's.")
    fi
  fi
  rm -f "$GRAND_LINE_STATE/background"
fi

# --- Dock, desktop, animations, hot corners, tiling and Finder views
# (set by the macOS defaults step on its first run)
if [[ -f "$GRAND_LINE_STATE/done-macos-defaults" && ! -f "$looks_done" ]]; then
  for pair in \
    "NSGlobalDomain NSAutomaticWindowAnimationsEnabled" "NSGlobalDomain NSWindowResizeTime" \
    "NSGlobalDomain NSWindowShouldDragOnGesture" \
    "com.apple.dock autohide" "com.apple.dock autohide-delay" "com.apple.dock autohide-time-modifier" \
    "com.apple.dock tilesize" "com.apple.dock show-recents" "com.apple.dock expose-animation-duration" \
    "com.apple.dock expose-group-apps" "com.apple.dock mru-spaces" \
    "com.apple.dock wvous-tl-corner" "com.apple.dock wvous-tr-corner" \
    "com.apple.dock wvous-bl-corner" "com.apple.dock wvous-br-corner" \
    "com.apple.finder DisableAllAnimations" "com.apple.finder CreateDesktop" \
    "com.apple.finder FXPreferredViewStyle" "com.apple.finder ShowPathbar" "com.apple.finder ShowStatusBar" \
    "com.apple.WindowManager EnableStandardClickToShowDesktop" "com.apple.WindowManager StandardHideWidgets" \
    "com.apple.WindowManager StageManagerHideWidgets" "com.apple.WindowManager EnableTilingByEdgeDrag" \
    "com.apple.WindowManager EnableTopTilingByEdgeDrag" "com.apple.WindowManager EnableTilingOptionAccelerator" \
    "com.apple.spaces spans-displays" "com.apple.screencapture disable-shadow"; do
    # Word splitting on purpose: "domain key".
    # shellcheck disable=SC2086
    defaults delete $pair >/dev/null 2>&1
  done
  restart_ui=1
  echo "The Dock, desktop, animations, hot corners, window tiling and Finder views are back to macOS's defaults"
fi

# --- The Dock's contents (replaced once by the declutter step)
if [[ -f "$GRAND_LINE_STATE/dock-set" ]]; then
  defaults delete com.apple.dock persistent-apps >/dev/null 2>&1
  defaults delete com.apple.dock persistent-others >/dev/null 2>&1
  rm -f "$GRAND_LINE_STATE/dock-set"
  restart_ui=1
  echo "The Dock has Apple's default apps again"
fi

if [[ "$restart_ui" == 1 ]]; then
  killall Dock Finder SystemUIServer >/dev/null 2>&1
fi
mkdir -p "$GRAND_LINE_STATE" && touch "$looks_done"

# --- The colours the package wrote for other apps
btop="$HOME/.config/btop"
trash_own "$btop/themes/grand-line.theme"
if [[ -f "$btop/btop.conf" ]] && grep -qE '^color_theme *= *"grand-line"' "$btop/btop.conf"; then
  perl -i -ne 'print unless /^color_theme *= *"grand-line"/' "$btop/btop.conf" && echo "btop uses its own colours again"
fi
lg="$HOME/Library/Application Support/lazygit/config.yml"
links_into "grand-line/current/theme" "$lg" && trash_own "$lg"
trash_own "$HOME/.claude/themes/grand-line.json"
# The rendered theme files (tmux, Neovim and the menus read them) and older copies.
rm -rf "$GRAND_LINE_STATE/current" "$GRAND_LINE_STATE/menu-flags" "$GRAND_LINE_STATE/nvim-theme"

# --- Nexus, and folders back to Finder
quit_app Nexus
if [[ -d "$APPS/Nexus.app" ]]; then
  if move_to_trash "$APPS/Nexus.app"; then echo "Moved Nexus to the Trash"
  else echo "Could not move $APPS/Nexus.app to the Trash." >&2; status=1; fi
fi
if [[ "$(lower "$(defaults read -g NSFileViewer 2>/dev/null)")" == com.grandline.nexus ]]; then
  defaults delete -g NSFileViewer 2>/dev/null
fi
# The folder entry setup wrote for Nexus is removed, so macOS's own choice,
# Finder, applies again.
if defaults export "$LS_PREFS" - 2>/dev/null | grep -qi 'com.grandline.nexus'; then
  work="$(mktemp -d)"
  if defaults export "$LS_PREFS" "$work/ls.plist" 2>/dev/null \
     && plutil -convert json -o "$work/ls.json" "$work/ls.plist" 2>/dev/null \
     && jq '.LSHandlers = [.LSHandlers[]? | select(((.LSHandlerRoleAll // "") | ascii_downcase) != "com.grandline.nexus")]' \
          "$work/ls.json" > "$work/new.json" \
     && plutil -convert xml1 -o "$work/new.plist" "$work/new.json" \
     && defaults import "$LS_PREFS" "$work/new.plist"; then
    :
  else
    # The settings hold a value JSON cannot express: name Finder instead.
    # shellcheck source=lib/default-apps.sh
    source "$GRAND_LINE_REPO/lib/default-apps.sh"
    set_ls_handler public.folder com.apple.finder
  fi
  rm -rf "$work"
  killall lsd 2>/dev/null
fi
rm -f "$GRAND_LINE_STATE/takeover-files" "$GRAND_LINE_STATE/nexus-selection"
echo "Folders and Show in Finder open in Finder"

# --- Ghostty, Espanso, Citrix Workspace and Tailscale
# The package's links to their settings first.
links_into "$GRAND_LINE_REPO/config/ghostty" "$HOME/.config/ghostty" && trash_own "$HOME/.config/ghostty"
links_into "$GRAND_LINE_LINK/config/ghostty" "$HOME/.config/ghostty" && trash_own "$HOME/.config/ghostty"
# Ghostty's theme.conf was written into the package's own folder.
[[ -d "$GRAND_LINE_REPO/config/ghostty" ]] && trash_own "$GRAND_LINE_REPO/config/ghostty"
esp="$HOME/Library/Application Support/espanso/match/grand-line.yml"
[[ -L "$esp" ]] && trash_own "$esp"

brew="$(command -v brew 2>/dev/null || echo /opt/homebrew/bin/brew)"
if [[ -x "$brew" ]]; then
  installed="$("$brew" list --cask 2>/dev/null)"
  for cask in ghostty espanso citrix-workspace tailscale-app; do
    printf '%s\n' "$installed" | grep -qx "$cask" || continue
    case "$cask" in
      ghostty)
        # Quitting Ghostty would stop this update if it runs in Ghostty.
        if [[ "${TERM_PROGRAM:-}" == ghostty || -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
          notes+=("Ghostty is still installed because this update runs in it. Open Terminal and run update once more to remove it.")
          status=1; continue
        fi
        quit_app ghostty ;;
      espanso)
        # Espanso starts itself at login through its own service.
        command -v espanso >/dev/null 2>&1 && { espanso service stop >/dev/null 2>&1; espanso service unregister >/dev/null 2>&1; }
        quit_app espanso ;;
      tailscale-app) quit_app Tailscale ;;
    esac
    if "$brew" uninstall --cask "$cask"; then echo "Uninstalled $cask"
    else echo "Could not uninstall $cask. The next update tries again." >&2; status=1; fi
  done
fi

notes+=("Spaces across displays and the window tiling settings take effect after you log out and back in.")
for n in "${notes[@]}"; do echo "$n"; done
exit "$status"
