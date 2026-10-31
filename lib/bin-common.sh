# shellcheck shell=bash
# Shared helpers for the commands in bin/. Keyboard shortcuts run these with
# a minimal environment, so the PATH is set here.

# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
# shellcheck source=lib/trash.sh
source "$(dirname "${BASH_SOURCE[0]}")/trash.sh"
# shellcheck source=lib/personal.sh
source "$(dirname "${BASH_SOURCE[0]}")/personal.sh"

export PATH="${GRAND_LINE_TEST_PATH:+$GRAND_LINE_TEST_PATH:}$BREW_PREFIX/bin:$GRAND_LINE_BIN:$GRAND_LINE_BUILD:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export GRAND_LINE_CONFIG="$GRAND_LINE_LINK/config/grand-line"
[[ -d "$GRAND_LINE_STATE" ]] || mkdir -p "$GRAND_LINE_STATE"

# Show a macOS notification without waiting for it.
notify() {
  osascript - "$1" "${2:-}" <<'EOF' >/dev/null 2>&1 &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
EOF
}

# say TITLE [TEXT]: a notification, unless the caller shows the outcome
# itself (Sight sets GRAND_LINE_QUIET and reads the exit status).
say() {
  [[ -n "${GRAND_LINE_QUIET:-}" ]] || notify "$@"
}

# fail CODE REASON: print why a change could not be made, tell the person, and
# stop. The codes Sight reads: 3 Automation permission missing, 4 a tool
# is not installed, 5 Accessibility permission missing, 1 anything else.
fail() {
  printf '%s\n' "$2"
  say "Could not do that" "$2"
  exit "$1"
}

# osa ARGS...: run osascript, and on failure stop with the reason. macOS
# answers -1743 when Automation (sending Apple events) is not allowed, and
# 1002 when keystrokes need Accessibility. Use it as a statement, never
# inside $( ), so the exit stops the command itself.
osa() {
  local out
  if out="$(osascript "$@" 2>&1)"; then
    [[ -z "$out" ]] || printf '%s\n' "$out"
    return 0
  fi
  case "$out" in
    *-1743*|*"Not authorized to send Apple events"*)
      fail 3 "Allow Automation for System Events in Privacy & Security" ;;
    *1002*|*"not allowed to send keystrokes"*|*"assistive access"*)
      fail 5 "Allow Accessibility in Privacy & Security" ;;
  esac
  fail 1 "macOS refused: ${out##*: }"
}

# The menus' font and colours, rendered by the theme command
# (config/themed/menu-flags.tpl). The older location is read until the next
# theme change.
: "${GRAND_LINE_CHOOSE_FLAGS:=$(cat "$GRAND_LINE_STATE/current/theme/menu-flags" 2>/dev/null || cat "$GRAND_LINE_STATE/menu-flags" 2>/dev/null)}"

# Pick one line from stdin in the pop-up menu. Prints the choice.
pick() {
  if command -v choose >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    choose ${GRAND_LINE_CHOOSE_FLAGS:-}
  else
    notify "Menu unavailable" "Run: bash ~/grand-line/setup.sh --only apps"
    return 1
  fi
}

# Ask for one line of text. Prints the answer.
prompt_text() {
  osascript - "$1" "${2:-}" <<'EOF' 2>/dev/null
on run argv
  set r to display dialog (item 1 of argv) default answer (item 2 of argv) buttons {"Cancel", "OK"} default button "OK"
  return text returned of r
end run
EOF
}

# Print the POSIX paths of the files selected in Nexus or Finder, one per line.
# Nexus, when it is in front, keeps its selection in a file, one path per
# line, so a shortcut can read it without asking the app.
finder_selection() {
  local front
  front="$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null)"
  if [[ "$front" == *com.grandline.nexus* ]]; then
    cat "$GRAND_LINE_STATE/nexus-selection" 2>/dev/null
    return 0
  fi
  osascript <<'EOF' 2>/dev/null
tell application "Finder" to set sel to selection as alias list
set out to ""
repeat with f in sel
  set out to out & POSIX path of f & linefeed
end repeat
return out
EOF
}

# Karabiner stops a running shortcut command when the next shortcut fires.
# Long jobs call this first so they keep running in their own session.
detach_self() {
  [[ -n "${GRAND_LINE_DETACHED:-}" ]] && return 0
  GRAND_LINE_DETACHED=1 perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' -- "$@" \
    </dev/null >/dev/null 2>&1 &
  exit 0
}

# focus_window APP [TITLE]: focus an open window of APP (whose title contains
# TITLE, when given) through AeroSpace, which also switches to its workspace.
# Fails when there is no such window, so the caller can open one.
focus_window() {
  local app="$1" title="${2:-}" id
  command -v aerospace >/dev/null 2>&1 || return 1
  id="$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
        | awk -F'|' -v app="$app" -v title="$title" '
            $2 == app && (title == "" || index(substr($0, length($1 $2) + 3), title)) { print $1; exit }')"
  [[ -n "$id" ]] && aerospace focus --window-id "$id" >/dev/null 2>&1
}
