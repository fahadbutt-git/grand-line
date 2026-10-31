#!/bin/bash
# Builds Den Den.app without Xcode, with the same functions Grand Line's
# setup uses (lib/native-apps.sh), so there is one way to make the app.
#
#   bash build.sh            release build into build/Den Den.app
#   bash build.sh --debug    debug build
#   bash build.sh --test     run the unit and stress tests only
#   bash build.sh --open     build, then open the app
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$here/../.." && pwd)"
case "${1:-}" in
  --test) cd "$here" && exec swift test ;;
  --debug) export GRAND_LINE_APPS_CONFIG=debug ;;
  --open|"") ;;
  *) echo "usage: build.sh [--debug | --test | --open]" >&2; exit 2 ;;
esac
[[ "$(uname -s)" == Darwin ]] || { echo "build.sh: Den Den builds on macOS only" >&2; exit 1; }

export GRAND_LINE_APPS_DEST="$here/build" GRAND_LINE_APPS_SCRATCH=1 DRY_RUN=0
mkdir -p "$GRAND_LINE_APPS_DEST"
# shellcheck source=../../lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=../../lib/native-apps.sh
source "$REPO_DIR/lib/native-apps.sh"
build_and_install "$here"
plutil -lint "$GRAND_LINE_APPS_DEST/Den Den.app/Contents/Info.plist" >/dev/null
[[ "${1:-}" == --open ]] && open "$GRAND_LINE_APPS_DEST/Den Den.app"
exit 0
