# Terminal setup, after Omarchy's shell tools. Loaded from ~/.zshrc.
# Every tool is optional: a missing one is simply skipped.

# Prompt
command -v starship >/dev/null && eval "$(starship init zsh)"

# cd that remembers folders: "cd res" jumps to the most used folder matching "res"
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"

# Fuzzy finder: Ctrl+R searches history, Ctrl+T inserts a file path
command -v fzf >/dev/null && source <(fzf --zsh)

# History that is shared between windows and survives restarts
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Listing files (eza)
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons=auto --git'
  alias lta='lt -a'
fi

# Language versions per project (mise), as in Omarchy
command -v mise >/dev/null && eval "$(mise activate zsh)"

# Editor and agents, as in Omarchy: n opens Neovim (in this folder when
# given nothing), cx opens Claude Code
export EDITOR=nvim VISUAL=nvim
unalias n 2>/dev/null
n() { if (( $# == 0 )); then command nvim .; else command nvim "$@"; fi; }
alias cx='claude'

# Folders and sessions, as in Omarchy
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias t='tmux attach 2>/dev/null || tmux new -s Work'

# Git and Docker shortcuts, as in Omarchy
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
alias lzg='lazygit'

# lp [folder]: open this folder (or another) in Log Pose, or Finder if Log
# Pose is not installed.
lp() { open -b com.grandline.logpose "${1:-.}" 2>/dev/null || open "${1:-.}"; }

# ga branch: a new branch in its own folder beside this one (a git worktree),
# so two pieces of work never share a checkout. gd, run inside that folder,
# removes the folder and the branch, but only when nothing in them would be
# lost. As in Omarchy.
ga() {
  [[ -n "$1" ]] || { echo "usage: ga branch-name"; return 1; }
  local wt="../$(basename "$PWD")--$1"
  git worktree add -b "$1" "$wt" || return 1
  command -v mise >/dev/null && mise trust "$wt" >/dev/null 2>&1
  cd "$wt"
}
gd() {
  local here="$PWD" name="${PWD:t}" root branch
  root="${name%%--*}"; branch="${name#*--}"
  [[ "$root" != "$name" ]] || { echo "Not in a folder made by ga."; return 1; }
  read -q "?Remove this worktree and the branch $branch? [y/N] " || { echo; return 1; }
  echo
  # No --force and -d, not -D: git refuses while the folder has uncommitted
  # changes or the branch has commits that are not merged, so no work is lost.
  cd "../$root" && git worktree remove "$here" && git branch -d "$branch"
}
alias d='docker'
alias lzd='lazydocker'

# Homelab, as in Omarchy
# fip host port...  forward ports from a server to this Mac over SSH
# dip port...       stop forwarding those ports
# lip               list forwarded ports
fip() { local h="$1"; shift; for p in "$@"; do ssh -f -N -L "$p:localhost:$p" "$h" && echo "localhost:$p -> $h:$p"; done; }
dip() { for p in "$@"; do pkill -f "ssh -f -N -L $p:localhost:$p( |\$)" && echo "stopped $p"; done; }
lip() { pgrep -lf "ssh -f -N -L" || echo "no ports forwarded"; }

# iso2sd image.iso disk4: write an image to an SD card or USB stick.
# Refuses anything that is not an external disk, and asks before writing.
iso2sd() {
  local img="$1" disk="${2#/dev/}"
  [[ -f "$img" && -n "$disk" ]] || { echo "usage: iso2sd image.iso disk4   (find the disk with: diskutil list external)"; return 1; }
  diskutil info "$disk" | grep -q "Device Location: *External" || { echo "$disk is not an external disk. Stopping."; return 1; }
  diskutil list "$disk"
  read -r "?Erase /dev/$disk and write $(basename "$img") to it? Type yes: " ok
  [[ "$ok" == yes ]] || return 1
  diskutil unmountDisk "/dev/$disk" && sudo dd if="$img" of="/dev/r$disk" bs=4m status=progress && sync && diskutil eject "/dev/$disk"
}

# ff: find a file with a live preview, then print its path
alias ff="fzf --preview 'bat --color=always --style=numbers --line-range=:100 {} 2>/dev/null || head -100 {}'"
# eff: pick a file with ff, then edit it (nothing opens if you press Escape)
unalias eff 2>/dev/null
eff() { local f; f="$(ff)" && [[ -n "$f" ]] && "$EDITOR" "$f"; }

# Archives
compress()   { tar -czf "${1%/}.tar.gz" "${1%/}"; }
# decompress any archive: macOS's tar opens .zip, .tar.*, .7z and .rar
decompress() { tar -xf "$1"; }

# tdl [agent]: a tmux layout with a terminal on the left and an AI agent on
# the right (claude by default), in the current folder.
tdl() {
  local agent="${1:-claude}"
  if [[ -z "$TMUX" ]]; then
    tmux new-session -s "$(basename "$PWD")" -c "$PWD" \; split-window -h -p 45 -c "$PWD" "$agent" \; select-pane -L
  else
    tmux split-window -h -p 45 -c "$PWD" "$agent" \; select-pane -L
  fi
}
