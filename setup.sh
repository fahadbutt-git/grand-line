#!/usr/bin/env bash
# Sets up a fresh Mac: apps, tools, settings, keyboard layer, window tiling,
# default apps and themes. Safe to run again at any time.
#
#   bash setup.sh               full setup
#   bash setup.sh --dry-run     print every action without changing anything
#   bash setup.sh --only artcraft,default-apps
#   bash setup.sh --skip r-packages
#   bash setup.sh --update      only the steps that update apps and settings
#   bash setup.sh --ci          unattended mode for test machines
#   bash setup.sh --list        list the steps
#
# Steps are the files in steps/, run in file-name order. To add one, create
# steps/NN-name.sh containing a function step_name (dashes become underscores).

set -uo pipefail

ORIGINAL_ARGS=("$@")
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

# Steps that keep an installed Mac current (used by --update and bin/update).
UPDATE_STEPS="apps,artcraft,folders,dotfiles,native-tools,default-apps,downloads"

STEPS=()
for f in "$REPO_DIR"/steps/[0-9][0-9]-*.sh; do
  name="$(basename "$f" .sh)"; STEPS+=("${name#[0-9][0-9]-}")
done

ONLY=""
SKIP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --ci)      CI_MODE=1 ;;
    --only)    ONLY="${2:-}"; shift ;;
    --skip)    SKIP="${2:-}"; shift ;;
    --update)  ONLY="$UPDATE_STEPS" ;;
    --list)    printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done
export DRY_RUN CI_MODE
[[ "$CI_MODE" == 1 ]] && export MAC_SETUP_NO_APPLEEVENTS=1

# Reject misspelled step names instead of silently skipping them.
for name in ${ONLY//,/ } ${SKIP//,/ }; do
  if [[ " ${STEPS[*]} " != *" $name "* ]]; then
    err "There is no step called '$name'. Steps: ${STEPS[*]}"
    exit 2
  fi
done

# Keep the package in one stable place so the links it creates stay valid.
MAC_SETUP_HOME="${MAC_SETUP_HOME:-$HOME/mac-setup}"
# The first run copies it there. Later runs from elsewhere (an old download)
# use the existing copy, so local edits and GitHub updates are never overwritten.
if [[ "$DRY_RUN" == 0 && "$REPO_DIR" != "$MAC_SETUP_HOME" ]]; then
  if [[ -f "$MAC_SETUP_HOME/setup.sh" ]]; then
    info "Using the existing package in $MAC_SETUP_HOME"
  elif [[ -e "$MAC_SETUP_HOME" ]]; then
    err "$MAC_SETUP_HOME exists and is not this package. Move it, then run again."
    exit 1
  else
    info "Copying the package to $MAC_SETUP_HOME"
    rsync -a --exclude .build "$REPO_DIR/" "$MAC_SETUP_HOME/" || exit 1
  fi
  exec /bin/bash "$MAC_SETUP_HOME/setup.sh" "${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}"
fi

if [[ "$DRY_RUN" == 0 ]]; then
  mkdir -p "$MAC_SETUP_LOGS"
  LOG_FILE="$MAC_SETUP_LOGS/setup-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "Log: $LOG_FILE"
fi

for f in "$REPO_DIR"/steps/[0-9][0-9]-*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

selected() {
  local step="$1"
  [[ "$step" == preflight ]] && return 0
  if [[ -n "$ONLY" && ",$ONLY," != *",$step,"* ]]; then return 1; fi
  [[ ",$SKIP," != *",$step,"* ]]
}

KEEPALIVE_PID=""
trap '[[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null' EXIT

FAILED=()
for step in "${STEPS[@]}"; do
  selected "$step" || continue
  heading "$step"
  if ! "step_${step//-/_}"; then
    err "Step '$step' did not finish. The rest of the setup continues."
    FAILED+=("$step")
    if [[ "$step" == preflight || "$step" == homebrew ]]; then
      err "Stopping, because later steps need '$step'."
      break
    fi
  fi
done

heading "Summary"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  log "Warnings:"
  printf '  - %s\n' "${WARNINGS[@]}"
  # On GitHub's test machines, also post each warning where the run page shows it.
  [[ -n "${GITHUB_ACTIONS:-}" ]] && printf '::warning title=setup::%s\n' "${WARNINGS[@]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error title=setup::Steps that failed: ${FAILED[*]}"
  err "Steps that need another run: ${FAILED[*]}"
  log "Run the same command again. It only redoes what is missing."
  exit 1
fi
ok "Setup finished."
