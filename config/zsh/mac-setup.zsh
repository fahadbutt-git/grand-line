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

# Editor and agents, as in Omarchy: n opens Neovim, cx opens Claude Code
export EDITOR=nvim VISUAL=nvim
alias n='nvim'
alias cx='claude'

# Git and Docker shortcuts, as in Omarchy
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
alias lzg='lazygit'
alias d='docker'
alias lzd='lazydocker'

# ff: find a file with a live preview, then print its path
alias ff="fzf --preview 'head -100 {}'"

# Archives
compress()   { tar -czf "${1%/}.tar.gz" "${1%/}"; }
# decompress any archive: tar handles .zip and .tar.*, 7zz the rest (.7z, .rar).
decompress() {
  case "$1" in
    *.7z|*.rar) 7zz x "$1" ;;
    *) tar -xf "$1" ;;
  esac
}

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
