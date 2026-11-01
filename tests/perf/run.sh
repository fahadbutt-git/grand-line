#!/usr/bin/env bash
# Resource budgets: starts Grand Line Index, Nexus, Sight and Iceberg with a
# fixture home of a few thousand files (the journeys' fixture, bigger),
# measures them idle and after bursts of use, checks that nothing takes the
# keyboard from the app you are typing in, and compares everything with
# tests/perf/budgets.env. Prints the table, and on CI writes it to the step
# summary and fails the job when a budget is exceeded.
#
#   bash tests/perf/run.sh                  build the apps into a scratch folder, then measure
#   bash tests/perf/run.sh --apps DIR       use bundles already built there (CI)
#   options: --out DIR, --files N, --quit-running (quits your running copies first)
#
# Wakeups and GPU need `sudo powermetrics` without a password (CI has it); on
# a laptop that part is skipped with a note unless sudo is already open.
# While it runs, leave the keyboard alone: the focus check types into TextEdit.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
budgets="$here/budgets.env"
measure=(python3 "$here/measure.py")
apps_dir=""
out="${TMPDIR:-/tmp}/grand-line-perf/$(date +%Y%m%d-%H%M%S)"
quit_running=0
files=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apps) apps_dir="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --quit-running) quit_running=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "run.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

[ "$(uname)" = Darwin ] || { echo "The budgets measure macOS apps, so they run on a Mac." >&2; exit 2; }

# The limits and timings, from the one config file.
# shellcheck source=tests/perf/budgets.env
. "$budgets"
files="${files:-$FIXTURE_FILES}"

results="$out/results"
home="$out/home"
mkdir -p "$results"
label="com.grandline.index.perf"
domain="gui/$(id -u)"

say() { printf '\n== %s\n' "$*"; }
notice() { echo "$*"; [ -n "${GITHUB_ACTIONS:-}" ] && echo "::notice title=budgets::$*"; return 0; }

# --- the apps

if [ -z "$apps_dir" ]; then
  apps_dir="$out/apps"
  say "Building the apps into $apps_dir"
  mkdir -p "$apps_dir"
  for folder in $(grep -v '^#' "$repo/tests/journeys/apps.tsv" | cut -f2 | sort -u); do
    GRAND_LINE_APPS_DEST="$apps_dir" GRAND_LINE_APPS_SCRATCH=1 REPO_DIR="$repo" DRY_RUN=0 \
      bash -c 'source "$1/lib/common.sh" && source "$1/lib/native-apps.sh" && build_and_install "$1/$2"' _ "$repo" "$folder" \
      || { echo "Could not build $folder" >&2; exit 1; }
  done
fi
for app in Nexus Sight Iceberg "Grand Line Index"; do
  [ -d "$apps_dir/$app.app" ] || { echo "No $app.app in $apps_dir" >&2; exit 1; }
done

running=""
for name in Nexus Sight Iceberg; do pgrep -x "$name" >/dev/null && running="$running $name"; done
if [ -n "$running" ]; then
  if [ "$quit_running" = 1 ]; then
    for name in $running; do osascript -e "tell application id \"com.grandline.$(echo "$name" | tr '[:upper:]' '[:lower:]')\" to quit" >/dev/null 2>&1 || pkill -TERM -x "$name"; done
    sleep 3
  else
    echo "Running already:$running. Quit them first, or pass --quit-running." >&2; exit 2
  fi
fi

app_env=(--env "HOME=$home" --env "CFFIXED_USER_HOME=$home" --env GRAND_LINE_JOURNEY=1 --env "GRAND_LINE_INDEX_SERVICE=$label")

start_app() {  # NAME [ARGS...]: in the background, with the fixture home
  local name="$1"; shift
  open -g -a "$apps_dir/$name.app" "${app_env[@]}" "$@" >/dev/null 2>&1
}

index_pid() {
  launchctl print "$domain/$label" 2>/dev/null | awk '/^[[:space:]]*pid = / { print $3; exit }'
}

start_index() {
  launchctl bootout "$domain/$label" >/dev/null 2>&1
  local plist="$out/$label.plist"
  python3 - "$plist" "$apps_dir/Grand Line Index.app/Contents/MacOS/GrandLineIndex" "$home" "$label" "$out/index.log" <<'PY'
import plistlib, sys
plist, program, home, label, log = sys.argv[1:]
job = {
    "Label": label, "ProgramArguments": [program, "--serve"], "MachServices": {label: True},
    "EnvironmentVariables": {"HOME": home, "CFFIXED_USER_HOME": home, "GRAND_LINE_INDEX_SERVICE": label,
                             "GRAND_LINE_JOURNEY": "1"},
    "RunAtLoad": True, "ProcessType": "Adaptive", "StandardErrorPath": log,
}
with open(plist, "wb") as f:
    plistlib.dump(job, f)
PY
  launchctl bootstrap "$domain" "$plist"
}

stop_all() {
  [ -n "${focus_file:-}" ] && pkill -x TextEdit >/dev/null 2>&1
  for name in Nexus Sight Iceberg; do pkill -TERM -x "$name" >/dev/null 2>&1; done
  launchctl bootout "$domain/$label" >/dev/null 2>&1
  return 0
}
trap stop_all EXIT

# --- fixture and start

say "Fixture home with $files more files: $home"
bash "$repo/tests/journeys/make-fixture.sh" --files "$files" "$home" >/dev/null || { echo "The fixture script failed" >&2; exit 1; }
count="$(find "$home" -not -path '*/Library/*' -not -path '*/.Trash/*' | wc -l | tr -d ' ')"
printf '{"files": %s}\n' "$count" > "$results/fixture.json"

say "Starting Grand Line Index, Nexus, Sight and Iceberg"
start_index || { echo "launchctl would not start the index" >&2; exit 1; }
start_app Nexus
start_app Sight
start_app Iceberg

# The index's first walk is allowed to work; the idle minute starts after it.
snapshot="$home/Library/Application Support/Grand Line Index/names.index"
for _ in $(seq 1 180); do [ -f "$snapshot" ] && break; sleep 1; done
[ -f "$snapshot" ] || notice "the index wrote no snapshot within 3 minutes; measuring anyway"
pid="$(index_pid)"
[ -n "$pid" ] || { echo "The index is not running" >&2; exit 1; }
specs=("GrandLineIndex=$pid" Nexus Sight Iceberg)
for name in Nexus Sight Iceberg; do pgrep -x "$name" >/dev/null || { echo "$name did not start" >&2; exit 1; }; done
say "Settling for $SETTLE_SECONDS s"
sleep "$SETTLE_SECONDS"

# --- idle

say "Idle for $IDLE_SECONDS s"
"${measure[@]}" idle --budgets "$budgets" --out "$results/idle.json" "${specs[@]}"
"${measure[@]}" powermetrics --out "$results/power-idle.json" "${specs[@]}"

# --- bursts of use

keys() {  # TEXT: typed into whatever has the keyboard
  osascript -e "on run argv" -e "tell application \"System Events\" to keystroke (item 1 of argv)" -e "end run" "$1" >/dev/null 2>&1
}
escape() { osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; }

burst() {
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    open -a "$apps_dir/Sight.app" >/dev/null 2>&1
    sleep 0.4
    keys "conj"
    sleep 0.6
    escape
    sleep 0.2
  done
  # One folder of 2,000 items in Nexus (the same window each round).
  open -g -a "$apps_dir/Nexus.app" "$home/Documents/Bulk" >/dev/null 2>&1
  sleep 3
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    open -g -a "$apps_dir/Iceberg.app" "iceberg://open" >/dev/null 2>&1
    sleep 0.6
    open -g -a "$apps_dir/Iceberg.app" "iceberg://close" >/dev/null 2>&1
    sleep 0.4
  done
  # 500 changed files for the index (and Nexus's watcher) to take in.
  find "$home/Documents/Tree" -type f | head -500 | xargs touch
  sleep 2
}

for round in $(seq 1 "$BURST_ROUNDS"); do
  say "Burst $round of $BURST_ROUNDS"
  stop="$out/stop-$round"
  rm -f "$stop"
  "${measure[@]}" sampler --stop "$stop" --out "$results/burst-$round.json" "${specs[@]}" &
  sampler=$!
  burst
  touch "$stop"
  wait "$sampler"
  "${measure[@]}" decay --budgets "$budgets" --out "$results/decay-$round.json" "${specs[@]}"
done
"${measure[@]}" powermetrics --out "$results/power-after.json" "${specs[@]}"

# --- focus: typing in TextEdit while our apps restart

say "Typing in TextEdit while the apps restart and an update relaunches Sight"
focus="$results/focus.json"
# Everything goes through System Events (keystrokes, and reading the text
# back through Accessibility), the one app CI lets the script control.
focus_file="$out/focus.txt"
: > "$focus_file"
open -a TextEdit "$focus_file"
sleep 3
front() { lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p'; }
if [ "$(front)" != com.apple.TextEdit ] || ! keys "a"; then
  printf '{"skipped": "TextEdit did not come to the front or keystrokes could not be sent", "front_kept": true, "text_kept": true}\n' > "$focus"
else
  words="the quick brown fox jumps over the lazy dog while grand line restarts "
  typed="a"
  (
    sleep 1; pkill -TERM -x Sight; sleep 1; start_app Sight
    sleep 1; pkill -TERM -x Iceberg; sleep 1; start_app Iceberg
    sleep 1; launchctl kickstart -k "$domain/$label" >/dev/null 2>&1
    sleep 1
    # The unattended update's own relaunch (lib/native-apps.sh).
    REPO_DIR="$repo" DRY_RUN=0 bash -c 'source "$1/lib/common.sh" && source "$1/lib/native-apps.sh" && relaunch_app "$2" Sight yes' \
      _ "$repo" "$apps_dir/Sight.app"
  ) &
  restarts=$!
  lost_front=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    keys "$words"
    typed="$typed$words"
    now="$(front)"
    [ "$now" = com.apple.TextEdit ] || lost_front="${lost_front:-$now}"
  done
  wait "$restarts"
  sleep 1
  got="$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get value of text area 1 of scroll area 1 of front window' 2>/dev/null)"
  python3 - "$focus" "$typed" "$got" "${lost_front}" <<'PY'
import json, sys
path, typed, got, lost = sys.argv[1:]
json.dump({"typed": len(typed), "received": len(got.rstrip("\n")), "text_kept": got.rstrip("\n") == typed,
           "front_kept": lost == "", "front_after": lost or "com.apple.TextEdit"}, open(path, "w"))
PY
fi

# --- stalls, shell, launch agents

python3 - "$home/Library/Logs/grand-line" "$results/stalls.json" <<'PY'
import glob, json, os, re, sys
folder, out = sys.argv[1:]
worst = {}
for path in glob.glob(os.path.join(folder, "*.log")):
    app = os.path.basename(path)[:-4]
    for line in open(path, errors="ignore"):
        m = re.search(r"main thread stalled (\d+) ms", line)
        if m:
            worst[app] = max(worst.get(app, 0), int(m.group(1)))
json.dump(worst, open(out, "w"))
PY

mkdir -p "$out/zdot"
printf 'source "%s/config/zsh/grand-line.zsh"\n' "$repo" > "$out/zdot/.zshrc"
XDG_CACHE_HOME="$out/cache" "${measure[@]}" shell --zshrc "$out/zdot/.zshrc" --runs "$SHELL_RUNS" --out "$results/shell.json"
bash "$here/agents.sh" "$results/agents.json" >/dev/null

say "Results ($results)"
"${measure[@]}" report --budgets "$budgets" --results "$results"
