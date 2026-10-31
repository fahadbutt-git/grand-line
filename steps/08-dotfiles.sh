# shellcheck shell=bash
# Puts the window, terminal and keyboard settings in place and adds the
# package's commands (bin/) to the PATH.

step_dotfiles() {
  local cfg="$REPO_DIR/config"

  # One link to the package. Shortcuts and the PATH go through it.
  link_into_place "$REPO_DIR" "$MAC_SETUP_LINK"
  append_once "export PATH=\"$MAC_SETUP_BIN:$MAC_SETUP_BUILD:\$PATH\"" "$HOME/.zprofile"

  link_into_place "$cfg/aerospace/aerospace.toml" "$HOME/.aerospace.toml"
  link_into_place "$cfg/ghostty" "$HOME/.config/ghostty"
  link_into_place "$cfg/tmux" "$HOME/.config/tmux"
  link_into_place "$cfg/starship.toml" "$HOME/.config/starship.toml"
  link_into_place "$cfg/nvim" "$HOME/.config/nvim"
  append_once "source \"$MAC_SETUP_LINK/config/zsh/mac-setup.zsh\"" "$HOME/.zshrc"

  # Git: the package's defaults are included, so ~/.gitconfig stays yours.
  if ! git config --global --get-all include.path 2>/dev/null | grep -qF "$MAC_SETUP_LINK/config/git/config"; then
    run git config --global --add include.path "$MAC_SETUP_LINK/config/git/config"
  fi
  git config --global user.name >/dev/null 2>&1 || run git config --global user.name "Your Name"
  git config --global user.email >/dev/null 2>&1 || run git config --global user.email "you@example.com"

  # Docker: find Homebrew's compose and buildx plugins, keep logins in the Keychain.
  local dcfg="$HOME/.docker/config.json" plug="$BREW_PREFIX/lib/docker/cli-plugins"
  if [[ "$DRY_RUN" == 1 ]]; then
    run "point Docker at $plug in $dcfg"
  elif [[ ! -f "$dcfg" ]]; then
    mkdir -p "$HOME/.docker"
    printf '{"cliPluginsExtraDirs": ["%s"], "credsStore": "osxkeychain"}\n' "$plug" > "$dcfg"
  elif [[ ! -L "$dcfg" ]] && ! grep -qF "$plug" "$dcfg"; then
    jq --arg p "$plug" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$p])' "$dcfg" > "$dcfg.new" \
      && mv "$dcfg.new" "$dcfg" || rm -f "$dcfg.new"
  fi

  # Espanso: the package's shortcuts are linked, its settings copied once so
  # changes made in Espanso itself are kept.
  local esp="$HOME/Library/Application Support/espanso"
  run mkdir -p "$esp/match" "$esp/config"
  link_into_place "$cfg/espanso/match/mac-setup.yml" "$esp/match/mac-setup.yml"
  [[ -f "$esp/config/default.yml" ]] || run cp "$cfg/espanso/config/default.yml" "$esp/config/default.yml"

  # Download Neovim's plugins now, so the first launch is instant.
  # Plugin versions are pinned in config/nvim/lazy-lock.json, so a new Mac
  # gets exactly the tested set (update moves them forward).
  if have nvim && [[ ! -d "$HOME/.local/share/nvim/lazy/LazyVim" ]]; then
    local lazy_cmd="Lazy! sync"
    [[ -f "$cfg/nvim/lazy-lock.json" ]] && lazy_cmd="Lazy! restore"
    run_sh "nvim --headless '+$lazy_cmd' +qa >/dev/null 2>&1" || warn "Neovim plugins did not download. Open nvim once to finish."
  fi

  # Karabiner rewrites and backs up its own settings file, so it gets a copy
  # rather than a link. The copy is replaced only when the package's shortcuts
  # change, so settings made in Karabiner's own window are kept otherwise.
  local kdir="$HOME/.config/karabiner" kfile="$cfg/karabiner/karabiner.json"
  local sum_file="$MAC_SETUP_STATE/karabiner.sha" sum
  sum="$(shasum -a 256 "$kfile" 2>/dev/null | cut -d' ' -f1)"
  [[ -L "$kdir" ]] && backup_path "$kdir"
  if [[ ! -f "$kdir/karabiner.json" || "$(cat "$sum_file" 2>/dev/null)" != "$sum" ]]; then
    run mkdir -p "$kdir"
    [[ -f "$kdir/karabiner.json" ]] && backup_path "$kdir/karabiner.json"
    run cp "$kfile" "$kdir/karabiner.json"
    run mkdir -p "$MAC_SETUP_STATE"
    run_sh "printf '%s\n' $sum > $(printf '%q' "$sum_file")"
    # Karabiner reads the file on change, but a restart covers the first install.
    run_sh "launchctl kickstart -k gui/\$(id -u)/org.pqrs.service.agent.karabiner_console_user_server 2>/dev/null || true"
    ok "Keyboard shortcuts updated"
  fi
}
