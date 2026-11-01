# shellcheck shell=bash
# Every folder and path the package uses, defined once.
# Sourced by lib/common.sh (setup steps) and lib/bin-common.sh (commands).

# A stable link to wherever this package lives. Shortcuts and PATH use it,
# so moving the package only means re-running setup.
# Sight sets it to its own copy of the commands when setup has not run.
GRAND_LINE_LINK="${GRAND_LINE_LINK:-$HOME/.grand-line}"
GRAND_LINE_BIN="$GRAND_LINE_LINK/bin"
GRAND_LINE_BUILD="$GRAND_LINE_LINK/.build"        # compiled helpers (tools/*.swift)
GRAND_LINE_STATE="$HOME/.local/state/grand-line"  # remembered theme, ArtCraft versions
GRAND_LINE_LOGS="$HOME/Library/Logs/grand-line"

SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
BACKGROUNDS_DIR="$HOME/Pictures/Backgrounds"
DRIVE_LINK="$HOME/Drive"                       # link to Google Drive, My Drive

# GRAND_LINE_BREW_PREFIX lets the tests point at a pretend Homebrew, so they
# behave the same whether or not the test machine has Homebrew.
if [[ -n "${GRAND_LINE_BREW_PREFIX:-}" ]]; then
  BREW_PREFIX="$GRAND_LINE_BREW_PREFIX"
elif [[ -d /opt/homebrew || "$(uname -m 2>/dev/null)" == arm64 ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi
BREW_BIN="$BREW_PREFIX/bin/brew"

export GRAND_LINE_LINK GRAND_LINE_BIN GRAND_LINE_BUILD GRAND_LINE_STATE GRAND_LINE_LOGS
export SCREENSHOTS_DIR BACKGROUNDS_DIR DRIVE_LINK BREW_PREFIX BREW_BIN
