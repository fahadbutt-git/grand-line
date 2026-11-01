#!/usr/bin/env bash
# Writes every launch agent the package installs into a folder (as setup
# would write them, without loading anything) and checks their schedules
# with measure.py: no KeepAlive that restarts a job forever, a throttle on
# watched jobs, background priority and low-priority disk for all but the
# index (Adaptive, restarted only after a crash).
#
#   bash tests/perf/agents.sh [OUT.json]

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${1:--}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

REPO_DIR="$repo" DRY_RUN=0 bash -c '
  source "$1/lib/common.sh"
  source "$1/steps/13-downloads.sh"
  source "$1/lib/auto-update.sh"
  downloads_plist > "$2/downloads.plist"
  update_agent_plist > "$2/update.plist"
' _ "$repo" "$dir" || { echo "agents.sh: could not write the agents" >&2; exit 1; }
cp "$repo/apps/finder/Bundle/GrandLineIndex/Library/LaunchAgents/com.grandline.index.plist" "$dir/index.plist"
python3 "$here/measure.py" agents --out "$out" "$dir"/*.plist
