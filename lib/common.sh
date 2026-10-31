# shellcheck shell=bash
# Shared helpers for setup.sh and the steps it runs.

: "${DRY_RUN:=0}"
: "${CI_MODE:=0}"

# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

if [[ -t 1 ]]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RESET=""
fi

WARNINGS=()

log()     { printf '%s\n' "$*"; }
info()    { printf '%s  %s%s\n' "${C_BLUE}" "$*" "${C_RESET}"; }
ok()      { printf '%s  ✓ %s%s\n' "${C_GREEN}" "$*" "${C_RESET}"; }
warn()    { printf '%s  ! %s%s\n' "${C_YELLOW}" "$*" "${C_RESET}"; WARNINGS+=("$*"); }
err()     { printf '%s  ✗ %s%s\n' "${C_RED}" "$*" "${C_RESET}" >&2; }
heading() { printf '\n%s== %s ==%s\n' "${C_BOLD}" "$*" "${C_RESET}"; }

# Run a command, or print it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  [dry-run] %s%s\n' "${C_DIM}" "$*" "${C_RESET}"
    return 0
  fi
  "$@"
}

# Run a shell snippet, or print it in dry-run mode.
run_sh() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  [dry-run] %s%s\n' "${C_DIM}" "$1" "${C_RESET}"
    return 0
  fi
  /bin/bash -c "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Move an existing file or folder aside before replacing it with a link.
backup_path() {
  local target="$1"
  if [[ -L "$target" ]]; then
    run rm "$target"
  elif [[ -e "$target" ]]; then
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    run mv "$target" "${target}.backup-${stamp}"
    info "Backed up ${target} to ${target}.backup-${stamp}"
  fi
}

# Link a file or folder from the repo into place, idempotently.
link_into_place() {
  local source="$1" target="$2"
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    return 0
  fi
  run mkdir -p "$(dirname "$target")"
  backup_path "$target"
  run ln -s "$source" "$target"
  ok "Linked ${target}"
}

# Append a line to a file once.
append_once() {
  local line="$1" file="$2"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    return 0
  fi
  run_sh "printf '%s\n' $(printf '%q' "$line") >> $(printf '%q' "$file")"
}

# Read the bundle identifier of an installed app, e.g. "WordCraft" or "Preview".
bundle_id_of() {
  local app="$1" path
  for path in "/Applications/${app}.app" "$HOME/Applications/${app}.app" "/System/Applications/${app}.app"; do
    if [[ -d "$path" ]]; then
      defaults read "${path}/Contents/Info" CFBundleIdentifier 2>/dev/null && return 0
    fi
  done
  return 1
}
