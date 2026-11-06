# shellcheck shell=bash
# grandline:unattended
# Nexus is gone and Sight and Iceberg take their look from macOS, so the
# package keeps no themes. On a Mac set up earlier this moves to the Trash
# what is left of both:
#   Nexus: its preferences (com.grandline.nexus.plist, after cfprefsd lets
#     go of it), Application Support, caches, container, saved window state,
#     HTTP storage, log, crash record, any launch agent of its own, and its
#     folder in ~/.config/grand-line (saved searches move to Sight's folder
#     first, so @name searches keep working). A Nexus.app LaunchServices
#     still knows about (in the Trash, say) is unregistered, so its URL
#     scheme no longer opens it and Sight drops its rows from Recent.
#   Themes: the theme state the old theme command kept, and the hook sample
#     for theme changes, which nothing calls any more.
# Nothing is deleted outright and nothing of macOS's own look is changed.
# Safe to run again: each part does nothing once its files are gone.
source "$GRAND_LINE_REPO/lib/bin-common.sh"

APPS="${GRAND_LINE_APPS_DEST:-/Applications}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
status=0
notes=()

# trash_own PATH: PATH goes to the Trash when it is there.
trash_own() {
  [[ -e "$1" || -L "$1" ]] || return 0
  if move_to_trash "$1"; then echo "Moved ${1/#$HOME/~} to the Trash"
  else echo "Could not move $1 to the Trash." >&2; status=1; fi
}

# --- Nexus is not running, and launchd starts nothing of it
pkill -x Nexus 2>/dev/null
for agent in "$HOME/Library/LaunchAgents/"*[Nn]exus*.plist; do
  [[ -f "$agent" ]] || continue
  label="$(defaults read "${agent%.plist}" Label 2>/dev/null)"
  [[ -n "$label" ]] || label="$(basename "$agent" .plist)"
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  trash_own "$agent"
done

# --- Its preferences. cfprefsd holds the domain in memory and would write
# the file back, so the file goes to the Trash first and the cached copy is
# then dropped (defaults delete), and anything written back meanwhile goes too.
prefs="$HOME/Library/Preferences/com.grandline.nexus.plist"
if [[ -e "$prefs" ]] || defaults read com.grandline.nexus >/dev/null 2>&1; then
  trash_own "$prefs"
  defaults delete com.grandline.nexus >/dev/null 2>&1
  [[ -e "$prefs" ]] && trash_own "$prefs"
fi

# --- Its other files in ~/Library
for left in \
  "$HOME/Library/Application Support/Nexus" \
  "$HOME/Library/Caches/com.grandline.nexus" \
  "$HOME/Library/Containers/com.grandline.nexus" \
  "$HOME/Library/Saved Application State/com.grandline.nexus.savedState" \
  "$HOME/Library/HTTPStorages/com.grandline.nexus" \
  "$HOME/Library/HTTPStorages/com.grandline.nexus.binarycookies" \
  "$HOME/Library/WebKit/com.grandline.nexus" \
  "$HOME/Library/Logs/grand-line/nexus.log" \
  "$HOME/.local/state/grand-line-runtime/nexus.json" \
  "$HOME/.local/state/grand-line/nexus-selection"; do
  trash_own "$left"
done

# --- Its folder in ~/.config/grand-line. Saved searches are Sight's now.
cfg="$HOME/.config/grand-line"
if [[ -f "$cfg/nexus/saved-searches.tsv" ]]; then
  mkdir -p "$cfg/sight"
  if [[ ! -e "$cfg/sight/saved-searches.tsv" ]] && mv -n "$cfg/nexus/saved-searches.tsv" "$cfg/sight/saved-searches.tsv"; then
    echo "Saved searches are now in ~/.config/grand-line/sight/saved-searches.tsv"
  else
    notes+=("Sight already has saved searches, so the old ones went to the Trash with Nexus's folder; copy any you want into ~/.config/grand-line/sight/saved-searches.tsv.")
  fi
fi
for left in "$cfg"/*[Nn]exus*; do
  trash_own "$left"
done

# --- Nexus.app: none left installed, and none still registered with
# LaunchServices (a copy in the Trash would still answer its URL scheme).
for app in "$APPS/Nexus.app" "$HOME/Applications/Nexus.app"; do
  [[ -d "$app" ]] || continue
  pkill -x Nexus 2>/dev/null
  trash_own "$app"
done
if [[ -x "$LSREGISTER" ]]; then
  {
    mdfind 'kMDItemCFBundleIdentifier == "com.grandline.nexus"' 2>/dev/null
    for app in "$HOME/.Trash/"Nexus*.app "$APPS/Nexus.app"; do [[ -e "$app" ]] && echo "$app"; done
  } | sort -u | while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    "$LSREGISTER" -u "$app" >/dev/null 2>&1 && echo "LaunchServices no longer opens ${app/#$HOME/~}"
  done
fi

# --- Theme leftovers: the package's own state, and the theme hook sample.
st="$GRAND_LINE_STATE"
for left in "$st/theme" "$st/theme-follows-macos" "$st/theme-follow.lock" "$st/theme.lock" "$st/current"; do
  trash_own "$left"
done
trash_own "$cfg/hooks/theme-set.sample"
if [[ -e "$cfg/hooks/theme-set" || -d "$cfg/hooks/theme-set.d" ]]; then
  notes+=("Your theme-set hook in ~/.config/grand-line/hooks no longer runs, since there are no themes. It was left as it is.")
fi

for n in "${notes[@]+"${notes[@]}"}"; do echo "$n"; done
exit "$status"
