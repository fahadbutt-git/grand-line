# shellcheck shell=bash
# The package never deletes anything: it moves it to the Trash.
# Sourced by lib/common.sh (setup steps) and lib/bin-common.sh (commands).

# trash_dest NAME: a name in the Trash that nothing has yet, not even a link.
trash_dest() {
  local name="$1" stem ext dest n=0
  stem="${name%.*}"; ext="${name#"$stem"}"
  dest="$HOME/.Trash/$name"
  while [[ -e "$dest" || -L "$dest" ]]; do
    n=$((n + 1))
    if [[ "$n" == 1 ]]; then dest="$HOME/.Trash/$stem $(date +%H%M%S)$ext"
    else dest="$HOME/.Trash/$stem $(date +%H%M%S) $n$ext"; fi
  done
  printf '%s\n' "$dest"
}

# move_to_trash PATH: a unique name if the Trash already has one, sudo only
# when needed, and root-owned items handed back to you so the Trash empties
# without a password.
#
# The Trash is yours, so any program running as you can put a link in it
# that points somewhere only root may write. Root therefore never moves an
# item into the Trash: it moves it into a new folder that only root can
# write, hands it back to you there (never following links), and you move it
# on into the Trash. mv -n never replaces anything already there.
move_to_trash() {
  local src="$1" name parent dest stage user nopw=()
  [[ -e "$src" || -L "$src" ]] || return 0
  name="$(basename "$src")"
  mkdir -p "$HOME/.Trash"
  mv -n "$src" "$(trash_dest "$name")" 2>/dev/null
  [[ -e "$src" || -L "$src" ]] || return 0

  # The unattended update never waits for a password.
  [[ "${GRAND_LINE_UNATTENDED:-0}" == 1 ]] && nopw=(-n)
  # The folder holding the item, with any links in its path resolved, so
  # root acts on the real place.
  parent="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd -P)" || return 1
  src="$parent/$name"
  user="$(id -un)"
  stage="$(sudo "${nopw[@]+"${nopw[@]}"}" mktemp -d "${GRAND_LINE_TRASH_STAGE:-/private/var/tmp}/grand-line-trash.XXXXXX")" || return 1
  if ! sudo "${nopw[@]+"${nopw[@]}"}" mv -n "$src" "$stage/$name" || [[ ! -e "$stage/$name" && ! -L "$stage/$name" ]]; then
    sudo "${nopw[@]+"${nopw[@]}"}" rmdir "$stage" 2>/dev/null
    return 1
  fi
  sudo "${nopw[@]+"${nopw[@]}"}" chown -R -h "$user" "$stage" || return 1
  dest="$(trash_dest "$name")"
  if mv -n "$stage/$name" "$dest" 2>/dev/null && [[ ! -e "$stage/$name" && ! -L "$stage/$name" ]]; then
    rmdir "$stage" 2>/dev/null
    return 0
  fi
  echo "Moved $name to $stage (it could not go on into the Trash)" >&2
  return 1
}
