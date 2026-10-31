# shellcheck shell=bash
# Shared helpers for the commands in bin/. Keyboard shortcuts run these with
# a minimal environment, so the PATH is set here.

# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

export PATH="${MAC_SETUP_TEST_PATH:+$MAC_SETUP_TEST_PATH:}$BREW_PREFIX/bin:$MAC_SETUP_BIN:$MAC_SETUP_BUILD:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export MAC_SETUP_CONFIG="$MAC_SETUP_LINK/config/mac-setup"
[[ -d "$MAC_SETUP_STATE" ]] || mkdir -p "$MAC_SETUP_STATE"

# Show a macOS notification without waiting for it.
notify() {
  osascript - "$1" "${2:-}" <<'EOF' >/dev/null 2>&1 &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
EOF
}

# Pick one line from stdin in the pop-up menu. Prints the choice.
pick() {
  if command -v choose >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    choose ${MAC_SETUP_CHOOSE_FLAGS:-}
  else
    notify "Menu unavailable" "Run: bash ~/mac-setup/setup.sh --only apps"
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

# Print the POSIX paths of the files selected in Finder, one per line.
finder_selection() {
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
  [[ -n "${MAC_SETUP_DETACHED:-}" ]] && return 0
  MAC_SETUP_DETACHED=1 perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' -- "$@" \
    </dev/null >/dev/null 2>&1 &
  exit 0
}
