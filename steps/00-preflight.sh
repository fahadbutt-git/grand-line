# shellcheck shell=bash
# Checks the Mac and asks for the password once. Always runs first.

step_preflight() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "This package only runs on macOS."
    return 1
  fi
  if [[ "$(id -u)" == 0 ]]; then
    err "Run this as your normal user, not with sudo. It asks for your password when needed."
    return 1
  fi

  local arch version
  arch="$(uname -m)"
  version="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  info "macOS $version on $arch"
  [[ "$arch" == arm64 ]] || warn "Built for Apple silicon. Some apps may differ on $arch."
  if [[ "${version%%.*}" =~ ^[0-9]+$ && "${version%%.*}" -lt 15 ]]; then
    err "macOS 15 or later is needed (this Mac has $version). Update macOS first."
    return 1
  fi

  [[ "$DRY_RUN" == 1 ]] && return 0

  if ! curl -fsS --max-time 15 -o /dev/null https://github.com; then
    err "No internet connection. Connect to Wi-Fi and run again."
    return 1
  fi
  ok "Internet connection works"

  # Ask for the password once and keep it fresh until setup ends.
  if ! sudo -n true 2>/dev/null; then
    info "Enter your Mac password once. It is used for app installers."
    sudo -v || return 1
  fi
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
  KEEPALIVE_PID=$!  # stopped by the exit trap in setup.sh
  export KEEPALIVE_PID
  ok "Administrator access ready"

  local free_gb
  free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
  if [[ -n "$free_gb" && "$free_gb" -lt 35 ]]; then
    warn "Only ${free_gb} GB free. A first install needs about 30 GB."
  fi
}
