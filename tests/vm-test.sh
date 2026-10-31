#!/usr/bin/env bash
# Full rehearsal on a throwaway macOS virtual machine, using Tart
# (https://tart.run). Runs on any Apple silicon Mac.
#
#   bash tests/vm-test.sh                 fresh VM, full setup, checks, second run
#   bash tests/vm-test.sh --keep          leave the VM running afterwards to look around
#   bash tests/vm-test.sh --image NAME    use another macOS image
#   bash tests/vm-test.sh --clean         delete the test VM and stop
#
# Needs about 70 GB of free disk space (the macOS image plus the apps).
# Runs setup with --ci because nobody can answer macOS permission prompts
# over SSH; everything else is exactly what a real install does.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM="grand-line-test"
IMAGE="ghcr.io/cirruslabs/macos-tahoe-vanilla:latest"
KEEP=0
SETUP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)  KEEP=1 ;;
    --image) IMAGE="$2"; shift ;;
    --clean) tart stop "$VM" >/dev/null 2>&1; tart delete "$VM" && echo "Deleted $VM"; exit 0 ;;
    --skip)  SETUP_ARGS+=(--skip "$2"); shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

[[ "$(uname -m)" == arm64 ]] || { echo "Tart needs an Apple silicon Mac."; exit 1; }
if ! command -v tart >/dev/null 2>&1; then
  say "Installing Tart"
  brew install cirruslabs/cli/tart || exit 1
fi

free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
if [[ "$free_gb" -lt 70 ]]; then
  echo "Only ${free_gb} GB free. The test needs about 70 GB."; exit 1
fi

# Password login for the image's default account (admin / admin), without
# extra tools: ssh reads the password from this helper.
askpass="$(mktemp)"; printf '#!/bin/sh\necho admin\n' > "$askpass"; chmod +x "$askpass"
cleanup() {
  rm -f "$askpass"
  if [[ "$KEEP" == 0 ]]; then tart stop "$VM" >/dev/null 2>&1; fi
}
trap cleanup EXIT

say "Preparing a fresh macOS VM from $IMAGE"
tart stop "$VM" >/dev/null 2>&1
tart delete "$VM" >/dev/null 2>&1
tart clone "$IMAGE" "$VM" || exit 1
tart set "$VM" --disk-size 100 --cpu 6 --memory 12288 || echo "Could not resize the VM; continuing with the image defaults."

say "Starting the VM"
if [[ "$KEEP" == 1 ]]; then
  tart run "$VM" --dir="pkg:$ROOT:ro" >/dev/null 2>&1 &
else
  tart run "$VM" --no-graphics --dir="pkg:$ROOT:ro" >/dev/null 2>&1 &
fi
ip="$(tart ip "$VM" --wait 300)" || { echo "The VM did not start."; exit 1; }
echo "VM address: $ip"

vm() {
  SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=none \
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ServerAliveInterval=30 "admin@$ip" "$@"
}

for _ in $(seq 1 30); do vm true 2>/dev/null && break; sleep 5; done
vm 'echo admin | sudo -S sh -c "echo \"admin ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/admin-test"' >/dev/null 2>&1

SRC='/Volumes/My Shared Files/pkg'
results=()

say "Run 1: full setup on a fresh Mac (20 to 60 minutes)"
start=$(date +%s)
vm "cp -R '$SRC' ~/grand-line-download && bash ~/grand-line-download/setup.sh --ci ${SETUP_ARGS[*]-}"
r1=$?; t1=$(( ($(date +%s) - start) / 60 ))
results+=("Run 1 (fresh install): exit $r1, ${t1} min")

say "Checking the installed Mac"
vm "bash ~/grand-line/tests/verify-install.sh --ci"
rv=$?
results+=("Checks after run 1: exit $rv")

say "Run 2: running setup again must change nothing and succeed"
start=$(date +%s)
vm "bash ~/grand-line/setup.sh --ci ${SETUP_ARGS[*]-}"
r2=$?; t2=$(( ($(date +%s) - start) / 60 ))
results+=("Run 2 (repeat): exit $r2, ${t2} min")

say "Copying the setup logs to tests/vm-logs"
mkdir -p "$ROOT/tests/vm-logs"
vm 'cd ~/Library/Logs/grand-line && tar cf - .' | tar xf - -C "$ROOT/tests/vm-logs" 2>/dev/null

say "Result"
printf '  %s\n' "${results[@]}"
if [[ "$KEEP" == 1 ]]; then
  echo "The VM is still running in its window. Delete it later with: bash tests/vm-test.sh --clean"
fi
[[ $r1 -eq 0 && $rv -eq 0 && $r2 -eq 0 ]] && echo "PASS: the package is ready for the new Mac." && exit 0
echo "FAIL: read the logs in tests/vm-logs."
exit 1
