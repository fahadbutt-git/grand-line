# shellcheck shell=bash
# The state of each toggle, for the menu's check marks and for bin/toggle.
# Each check is cheap (one quick command or a file test), because the menu
# runs all of them before it opens. Where the state cannot be read cheaply,
# bin/toggle keeps a flag file in ~/.local/state/grand-line/toggles/, as
# Omarchy does.

TOGGLE_FLAGS="$HOME/.local/state/grand-line/toggles"

# is_on NAME: succeeds when that toggle is on.
is_on() {
  case "$1" in
    awake)   launchctl list grand-line.caffeinate >/dev/null 2>&1 ;;
    ollama)  launchctl list grand-line.ollama >/dev/null 2>&1 ;;
    dark)    [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == Dark ]] ;;
    hidden)  [[ "$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)" == 1 ]] ;;
    desktop-icons) [[ "$(defaults read com.apple.finder CreateDesktop 2>/dev/null)" != 0 ]] ;;
    dock)    [[ "$(defaults read com.apple.dock autohide 2>/dev/null)" != 1 ]] ;;
    menubar) [[ "$(defaults read -g _HIHideMenuBar 2>/dev/null)" != 1 ]] ;;
    wifi)    networksetup -getairportpower "$(wifi_device)" 2>/dev/null | grep -q 'On$' ;;
    bluetooth) [[ "$(blueutil -p 2>/dev/null)" == 1 ]] ;;
    mic-muted) [[ -f "$TOGGLE_FLAGS/$1" ]] ;;
    mute)    [[ "$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)" == true ]] ;;
    dnd)     dnd_on ;;
    # Colima's VM does not survive a restart, so the flag counts only when it
    # was set since the Mac last started.
    docker)  [[ -f "$TOGGLE_FLAGS/docker" && "$(< "$TOGGLE_FLAGS/docker")" == "$(boot_time)" ]] ;;
    # Nexus and Sight, on unless switched back (lib/takeover.sh).
    files|search) [[ "$(cat "$HOME/.local/state/grand-line/takeover-$1" 2>/dev/null || echo on)" == on ]] ;;
    *) return 1 ;;
  esac
}

# The output volume, 0 to 100, or nothing when the output has no volume
# control (some USB and HDMI outputs).
volume_level() {
  local v
  v="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v"
}

# Whether a Focus (Do Not Disturb or another) is on. macOS keeps the active
# one in Assertions.json; when that file cannot be read (it can need Full
# Disk Access), the flag bin/toggle keeps is the answer instead.
dnd_on() {
  local db="$HOME/Library/DoNotDisturb/DB/Assertions.json" text
  if text="$(cat "$db" 2>/dev/null)"; then
    [[ "$text" == *storeAssertionRecords* ]]
  else
    [[ -f "$TOGGLE_FLAGS/dnd" ]]
  fi
}

# The Wi-Fi interface (en0 on laptops, often en1 on desktops).
# Looking it up is slow, so it is kept in the toggles folder once found.
wifi_device() {
  local cache="$TOGGLE_FLAGS/.wifi-device" dev
  if [[ -s "$cache" ]]; then cat "$cache"; return; fi
  dev="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/ { getline; print $2; exit }')"
  [[ -n "$dev" ]] && mkdir -p "$TOGGLE_FLAGS" && printf '%s\n' "$dev" > "$cache"
  printf '%s\n' "$dev"
}

# When the Mac last started ("{ sec = N"), written into each flag.
boot_time() {
  local t; t="$(sysctl -n kern.boottime 2>/dev/null)"
  printf '%s\n' "${t%%,*}"
}

# flag NAME on|off: record a toggle's state.
flag() {
  mkdir -p "$TOGGLE_FLAGS"
  if [[ "$2" == on ]]; then boot_time > "$TOGGLE_FLAGS/$1"; else rm -f "$TOGGLE_FLAGS/$1"; fi
}

# theme_is NAME: succeeds when NAME is the current theme, or the family
# (harbour for harbour-dark and harbour-light) it belongs to.
theme_is() {
  local current=""
  read -r current < "$HOME/.local/state/grand-line/theme" 2>/dev/null
  [[ "$current" == "$1" || "$current" == "$1-dark" || "$current" == "$1-light" ]]
}
