# shellcheck shell=bash
# Installs Homebrew (and with it Apple's command line tools).

# Homebrew's installer at a fixed commit, checked against its SHA-256 before
# it runs, so a changed script (or a tampered download) never runs unseen. To
# move it forward, take the newest commit of github.com/Homebrew/install and
# the SHA-256 of its install.sh:
#   git ls-remote https://github.com/Homebrew/install.git HEAD
#   curl -fsSL https://raw.githubusercontent.com/Homebrew/install/<commit>/install.sh | shasum -a 256
HOMEBREW_INSTALL_COMMIT=8c82c081753d4263da0cfe615ef8d9433425f22b
HOMEBREW_INSTALL_SHA256=5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148

homebrew_install() {
  local url="https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_COMMIT/install.sh" work status
  if [[ "$DRY_RUN" == 1 ]]; then
    run "download $url, check its SHA-256, run it"
    return 0
  fi
  work="$(mktemp -d)" || return 1
  if ! curl -fsSL --retry 3 --connect-timeout 10 -o "$work/install.sh" "$url"; then
    err "Could not download Homebrew's installer."; rm -rf "$work"; return 1
  fi
  if [[ "$(shasum -a 256 "$work/install.sh" | cut -d' ' -f1)" != "$HOMEBREW_INSTALL_SHA256" ]]; then
    err "Homebrew's installer is not the one this package checked, so it was not run."
    rm -rf "$work"; return 1
  fi
  NONINTERACTIVE=1 /bin/bash "$work/install.sh"; status=$?
  rm -rf "$work"
  return "$status"
}

step_homebrew() {
  if [[ -x "$BREW_BIN" ]]; then
    ok "Homebrew already installed"
  else
    info "Installing Homebrew and Apple's command line tools (about 5 minutes)"
    homebrew_install || return 1
  fi
  [[ "$DRY_RUN" == 0 ]] && eval "$("$BREW_BIN" shellenv)"
  append_once "eval \"\$(${BREW_BIN} shellenv)\"" "$HOME/.zprofile"
  export HOMEBREW_NO_ENV_HINTS=1
  ok "Homebrew ready"
}
