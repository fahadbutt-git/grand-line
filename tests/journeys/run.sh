#!/usr/bin/env bash
# Runs the user journeys on this Mac: builds the apps into a scratch folder
# (the installed copies are not touched), builds the driver, and drives each
# app through its journeys with a fixture home folder. Screenshots and
# results.tsv go to the output folder, which opens at the end.
#
#   bash tests/journeys/run.sh                 every journey
#   bash tests/journeys/run.sh files           one app, by role (files, launcher, notch)
#   bash tests/journeys/run.sh files-search    one journey, or a name prefix
#   bash tests/journeys/run.sh --list
#
# Options: --apps DIR uses bundles already built there, --out DIR, --no-build,
# --quit-running quits a running copy of an app first (otherwise it stops).
# The first run asks for Accessibility and Screen Recording for the app you
# run it from (Terminal, Ghostty); allow both, then run it again.
# While it runs, leave the keyboard and mouse alone: it types and clicks.
# Moving a file to the Trash in a journey uses your Trash; the journey undoes it.
# launcher-settings switches system settings and back, so it runs only when
# named: bash tests/journeys/run.sh launcher-settings

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
apps_dir=""
out="${TMPDIR:-/tmp}/grand-line-journeys/$(date +%Y%m%d-%H%M%S)"
build=1
list=0
only=""
extra=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apps) apps_dir="$2"; build=0; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --no-build) build=0; shift ;;
    --quit-running) extra+=(--quit-running); shift ;;
    --list) list=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "run.sh: unknown option $1" >&2; exit 2 ;;
    *) only="${only:+$only,}$1"; shift ;;
  esac
done

[ "$(uname)" = Darwin ] || { echo "The journeys drive macOS apps, so they run on a Mac." >&2; exit 2; }
command -v swift >/dev/null || { echo "Swift is needed: xcode-select --install" >&2; exit 2; }

echo "Building the journey driver"
swift build -c release --package-path "$here" 2>&1 | tail -n 20
driver="$(swift build -c release --package-path "$here" --show-bin-path)/journeys"
if [ "$list" = 1 ]; then exec "$driver" --list; fi

if [ -z "$apps_dir" ]; then
  apps_dir="${TMPDIR:-/tmp}/grand-line-journeys/apps"
fi
if [ "$build" = 1 ]; then
  echo "Building the apps into $apps_dir"
  mkdir -p "$apps_dir"
  folders="$(grep -v '^#' "$here/apps.tsv" | cut -f2 | sort -u)"
  for folder in $folders; do
    GRAND_LINE_APPS_DEST="$apps_dir" GRAND_LINE_APPS_SCRATCH=1 REPO_DIR="$repo" DRY_RUN=0 \
      bash -c 'source "$1/lib/common.sh" && source "$1/lib/native-apps.sh" && build_and_install "$1/$2"' _ "$repo" "$folder"
  done
fi

if ! "$driver" --check-permissions >/dev/null 2>&1; then
  "$driver" --check-permissions --prompt || true
  echo
  echo "Allow the app you ran this from in System Settings > Privacy & Security,"
  echo "under Accessibility and under Screen Recording, then run this again."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
  exit 1
fi

status=0
"$driver" --apps "$apps_dir" --fixture-script "$here/make-fixture.sh" --config "$here/apps.tsv" \
  --out "$out" ${only:+--only "$only"} ${extra[@]+"${extra[@]}"} || status=$?
# Any app whose hang watchdog saw its main thread stall for over a second
# fails the run (each app logs stalls in the fixture home's logs).
worst="$(grep -rhoE 'main thread stalled [0-9]+ ms' "$out"/homes/*/journeyhome/Library/Logs/grand-line/ 2>/dev/null \
  | awk '{ if ($4 > max) max = $4 } END { print max + 0 }')"
if [ "${worst:-0}" -gt 1000 ]; then
  echo "An app's main thread stalled for $worst ms (over 1 s); see the logs under $out/homes" >&2
  status=1
fi
[ -d "$out" ] && open "$out" 2>/dev/null || true
exit "$status"
