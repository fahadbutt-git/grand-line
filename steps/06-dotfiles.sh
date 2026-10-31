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
  append_once "source \"$MAC_SETUP_LINK/config/zsh/mac-setup.zsh\"" "$HOME/.zshrc"

  # Karabiner rewrites and backs up its own settings file, so it gets a copy
  # rather than a link. The copy is replaced only when the package's shortcuts
  # change, so settings made in Karabiner's own window are kept otherwise.
  local kdir="$HOME/.config/karabiner" kfile="$cfg/karabiner/karabiner.json"
  local sum_file="$MAC_SETUP_STATE/karabiner.sha" sum
  sum="$(shasum -a 256 "$kfile" 2>/dev/null | cut -d' ' -f1)"
  if [[ -L "$kdir" ]]; then run rm "$kdir"; fi
  if [[ ! -f "$kdir/karabiner.json" || "$(cat "$sum_file" 2>/dev/null)" != "$sum" ]]; then
    run mkdir -p "$kdir"
    [[ -f "$kdir/karabiner.json" ]] && backup_path "$kdir/karabiner.json"
    run cp "$kfile" "$kdir/karabiner.json"
    run mkdir -p "$MAC_SETUP_STATE"
    run_sh "printf '%s\n' $sum > $(printf '%q' "$sum_file")"
    # Karabiner reads the file on change, but a restart covers the first install.
    run_sh "launchctl kickstart -k gui/\$(id -u)/org.pqrs.service.agent.karabiner_console_user_server 2>/dev/null || true"
    ok "Caps Lock shortcuts updated"
  fi
}
