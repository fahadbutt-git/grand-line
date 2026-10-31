# shellcheck shell=bash
# Installs Homebrew (and with it Apple's command line tools).

step_homebrew() {
  if [[ -x "$BREW_BIN" ]]; then
    ok "Homebrew already installed"
  else
    info "Installing Homebrew and Apple's command line tools (about 5 minutes)"
    run_sh 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' || return 1
  fi
  [[ "$DRY_RUN" == 0 ]] && eval "$("$BREW_BIN" shellenv)"
  append_once "eval \"\$(${BREW_BIN} shellenv)\"" "$HOME/.zprofile"
  export HOMEBREW_NO_ENV_HINTS=1
  ok "Homebrew ready"
}
