# Apps and tools for the new Mac. To add one, add a line here, then run:
#   bash ~/mac-setup/setup.sh --only apps
# Video compression, image conversion and PDF shrinking use tools built into
# macOS (avconvert, sips, tools/pdfshrink.swift), so no extra libraries.

tap "nikitabobko/tap"

# Command line tools (git, Swift and jq come with macOS and its command line tools)
brew "gh"               # GitHub, for keeping this package in sync
brew "duti"             # sets default apps per file type
brew "choose-gui"       # the pop-up menu behind every Omarchy-style menu
brew "blueutil"         # Bluetooth menu (Caps + Ctrl + B)
brew "switchaudio-osx"  # audio output menu (Caps + Ctrl + A, M)

# Terminal, as in Omarchy (see config/zsh/mac-setup.zsh for the shortcuts)
brew "eza"              # ls with colour and icons
brew "fzf"              # fuzzy finder: ff, Ctrl+R history
brew "zoxide"           # cd that remembers folders
brew "ripgrep"          # rg: search inside files
brew "fd"               # simpler find
brew "tmux"             # panes, windows and lasting sessions
brew "starship"         # the prompt line
brew "bat"              # cat with syntax colours (also the ff preview)
brew "tlrc"             # tldr: short worked examples for any command
brew "rclone"           # Drive from the command line: bulk tidying now, NAS sync later
cask "font-jetbrains-mono-nerd-font"

# Building, as in Omarchy. Docker runs in a Colima VM that starts only when
# asked (Caps menu, Toggle, Docker), so nothing runs in the background.
brew "mise"             # language versions per project (node, python, go...)
brew "uv"               # Python packages and virtual environments
brew "colima"           # the Linux VM that Docker runs in
brew "docker"           # docker command
brew "docker-compose"   # docker compose
brew "docker-buildx"    # docker buildx (multi-platform builds)
brew "docker-credential-helper"  # keeps registry logins in the Keychain
brew "lazygit"          # git in the terminal (lzg)
brew "lazydocker"       # containers in the terminal (lzd)
brew "btop"             # what is using the CPU, memory and disk
brew "duckdb"           # SQL over large CSV and Parquet exports (TriNetX, All of Us)
brew "ollama"           # local AI models for private text; runs only when toggled on
brew "neovim"           # the editor: LazyVim, as in Omarchy (config/nvim)
brew "tree-sitter-cli"  # code highlighting parsers for Neovim

# AI
cask "claude"
cask "claude-code"
cask "codex"
cask "chatgpt"
cask "google-gemini"
brew "ccusage"              # where Claude Code tokens go: ccusage daily, ccusage blocks --live
cask "antigravity-cli"      # Google's replacement for gemini-cli (command: agy)

# Storage and notes (tasks live in Apple Reminders, built in)
cask "google-drive"
cask "notion"

# Research and study
cask "r-app"
cask "rstudio"
cask "anki"
cask "plaud"                # the Plaud recorder, for in-person conversations

# Voice, all on the Mac (nothing leaves it)
cask "handy"                # dictation into any app: hold Caps + Ctrl + X, as Voxtype in Omarchy
cask "meetily"              # records and transcribes online meetings (both sides), Caps + Ctrl + Option + M

# Office fallback (the ArtCraft apps are installed by the artcraft step)
cask "libreoffice"

# Clinical remote access
cask "citrix-workspace"
cask "omnissa-horizon-client"

# Communication
cask "whatsapp"
cask "zoom"
cask "discord"

# Media. Converting and compressing use the transcode shortcuts, and macOS
# opens every archive itself (decompress in the terminal), so no separate
# converter or archive apps.
cask "iina"                 # plays every video format; FilmCraft is for editing

# Privacy and the homelab
cask "protonvpn"            # free VPN with no data cap; open-source, audited apps
cask "tailscale-app"        # private network to your own NAS and servers, from anywhere
brew "nmap"             # find devices and open ports on your network
brew "mtr"              # trace where a connection slows or drops
brew "iperf3"           # measure speed between two machines
brew "wakeonlan"        # wake the NAS or a server from sleep

# Browser, terminal and music
cask "google-chrome"
cask "ghostty"
cask "spotify"

# Keyboard, windows and clipboard
cask "karabiner-elements"
cask "nikitabobko/tap/aerospace"
cask "maccy"
cask "espanso"              # text shortcuts (config/espanso)
