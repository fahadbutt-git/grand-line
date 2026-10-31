# shellcheck shell=bash
# Every folder and path the package uses, defined once.
# Sourced by lib/common.sh (setup steps) and lib/bin-common.sh (commands).

# A stable link to wherever this package lives. Shortcuts and PATH use it,
# so moving the package only means re-running setup.
MAC_SETUP_LINK="$HOME/.mac-setup"
MAC_SETUP_BIN="$MAC_SETUP_LINK/bin"
MAC_SETUP_BUILD="$MAC_SETUP_LINK/.build"        # compiled helpers (tools/*.swift)
MAC_SETUP_STATE="$HOME/.local/state/mac-setup"  # remembered theme, ArtCraft versions
MAC_SETUP_LOGS="$HOME/Library/Logs/mac-setup"

SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
BACKGROUNDS_DIR="$HOME/Pictures/Backgrounds"

# MAC_SETUP_BREW_PREFIX lets the tests point at a pretend Homebrew, so they
# behave the same whether or not the test machine has Homebrew.
if [[ -n "${MAC_SETUP_BREW_PREFIX:-}" ]]; then
  BREW_PREFIX="$MAC_SETUP_BREW_PREFIX"
elif [[ -d /opt/homebrew || "$(uname -m 2>/dev/null)" == arm64 ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi
BREW_BIN="$BREW_PREFIX/bin/brew"

export MAC_SETUP_LINK MAC_SETUP_BIN MAC_SETUP_BUILD MAC_SETUP_STATE MAC_SETUP_LOGS
export SCREENSHOTS_DIR BACKGROUNDS_DIR BREW_PREFIX BREW_BIN
