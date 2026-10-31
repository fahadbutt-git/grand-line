#!/usr/bin/env bash
# Sets up a fresh Mac: apps, tools, settings, keyboard layer, window tiling,
# default apps and themes. Safe to run again at any time.
#
#   bash setup.sh               full setup
#   bash setup.sh --dry-run     print every action without changing anything
#   bash setup.sh --only artcraft,default-apps
#   bash setup.sh --skip r-packages
#   bash setup.sh --update      only the steps that update apps and settings
#   bash setup.sh --unattended  only the steps that need no password or answer
#                               (bin/update --unattended; combine with --only)
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
UPDATE_STEPS="apps,artcraft,security,folders,dotfiles,native-tools,default-apps,downloads,auto-update"
# The steps the unattended update runs: none asks for a password or an
# answer, or shows a dialog.
UNATTENDED_STEPS="folders,dotfiles,native-tools,downloads"

STEPS=()
for f in "$REPO_DIR"/steps/[0-9][0-9]-*.sh; do
  name="$(basename "$f" .sh)"; STEPS+=("${name#[0-9][0-9]-}")
done

ONLY=""
SKIP=""
UNATTENDED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --ci)      CI_MODE=1 ;;
    --only)    ONLY="${2:-}"; shift ;;
    --skip)    SKIP="${2:-}"; shift ;;
    --update)  ONLY="$UPDATE_STEPS" ;;
    --unattended) UNATTENDED=1 ;;
    --list)    printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done
export DRY_RUN CI_MODE
[[ "$CI_MODE" == 1 ]] && export GRAND_LINE_NO_APPLEEVENTS=1
if [[ "$UNATTENDED" == 1 ]]; then
  export GRAND_LINE_UNATTENDED=1
  [[ -n "$ONLY" ]] || ONLY="$UNATTENDED_STEPS"
  for name in ${ONLY//,/ }; do
    if [[ ",$UNATTENDED_STEPS," != *",$name,"* ]]; then
      err "'$name' may ask for a password or an answer, so it does not run unattended."
      exit 2
    fi
  done
fi

# Reject misspelled step names instead of silently skipping them.
for name in ${ONLY//,/ } ${SKIP//,/ }; do
  if [[ " ${STEPS[*]} " != *" $name "* ]]; then
    err "There is no step called '$name'. Steps: ${STEPS[*]}"
    exit 2
  fi
done

# Keep the package in one stable place so the links it creates stay valid.
GRAND_LINE_HOME="${GRAND_LINE_HOME:-$HOME/grand-line}"
# The first run copies it there. Later runs from elsewhere (an old download)
# use the existing copy, so local edits and GitHub updates are never overwritten.
if [[ "$DRY_RUN" == 0 && "$REPO_DIR" != "$GRAND_LINE_HOME" ]]; then
  if [[ -f "$GRAND_LINE_HOME/setup.sh" ]]; then
    info "Using the existing package in $GRAND_LINE_HOME"
  elif [[ -e "$GRAND_LINE_HOME" ]]; then
    err "$GRAND_LINE_HOME exists and is not this package. Move it, then run again."
    exit 1
  else
    info "Copying the package to $GRAND_LINE_HOME"
    rsync -a --exclude .build "$REPO_DIR/" "$GRAND_LINE_HOME/" || exit 1
  fi
  exec /bin/bash "$GRAND_LINE_HOME/setup.sh" "${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}"
fi

# One setup or update at a time (bin/update holds the lock for the setup it runs).
# shellcheck source=lib/auto-update.sh
source "$REPO_DIR/lib/auto-update.sh"
if [[ "$DRY_RUN" == 0 && -z "${GRAND_LINE_LOCK_HELD:-}" ]]; then
  if ! update_lock_take; then
    err "An update or another setup is running${UPDATE_LOCK_HOLDER:+ (process $UPDATE_LOCK_HOLDER)}. Wait for it to finish."
    exit 1
  fi
  OWN_LOCK=1
  trap update_lock_release EXIT
fi

# The unattended update writes everything to its own log.
if [[ "$DRY_RUN" == 0 && "$UNATTENDED" == 0 ]]; then
  mkdir -p "$GRAND_LINE_LOGS"
  LOG_FILE="$GRAND_LINE_LOGS/setup-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "Log: $LOG_FILE"
fi

for f in "$REPO_DIR"/steps/[0-9][0-9]-*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

# A fresh install needs none of the one-time changes in migrations/, so they
# are recorded as done. A Mac set up before migrations existed already has a
# theme, so its migrations still run (bin/update runs them).
if [[ ! -d "$GRAND_LINE_STATE/migrations" && ! -f "$GRAND_LINE_STATE/theme" ]]; then
  run "$REPO_DIR/bin/migrate" --mark-all
fi

selected() {
  local step="$1"
  [[ "$step" == preflight ]] && return 0
  if [[ -n "$ONLY" && ",$ONLY," != *",$step,"* ]]; then return 1; fi
  [[ ",$SKIP," != *",$step,"* ]]
}

KEEPALIVE_PID=""
trap '[[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null; [[ -n "${OWN_LOCK:-}" ]] && update_lock_release' EXIT

FAILED=()
# The password is needed only up to the declutter step (installers, the
# firewall, moving Apple's apps). After it, sudo is closed again, so nothing
# later in the run can use it.
end_sudo() {
  [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
  KEEPALIVE_PID=""
  [[ "$DRY_RUN" == 0 ]] && sudo -k
}

for step in "${STEPS[@]}"; do
  [[ "$step" == r-packages ]] && end_sudo
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
