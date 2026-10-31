# shellcheck shell=bash
# The package never deletes anything: it moves it to the Trash.
# Sourced by lib/common.sh (setup steps) and lib/bin-common.sh (commands).

# move_to_trash PATH: a unique name if the Trash already has one, sudo only
# when needed, and root-owned items handed back to you so the Trash empties
# without a password.
move_to_trash() {
  local src="$1" name stem ext dest
  [[ -e "$src" || -L "$src" ]] || return 0
  name="$(basename "$src")"; stem="${name%.*}"; ext="${name#"$stem"}"
  dest="$HOME/.Trash/$name"
  [[ -e "$dest" ]] && dest="$HOME/.Trash/$stem $(date +%H%M%S)$ext"
  mkdir -p "$HOME/.Trash"
  mv "$src" "$dest" 2>/dev/null && return 0
  sudo mv "$src" "$dest" && sudo chown -R "$(id -un)" "$dest"
}
