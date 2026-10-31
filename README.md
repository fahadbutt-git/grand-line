# Mac setup

One command turns a new Mac into a ready workstation: apps, command line tools, the ArtCraft office apps as defaults, Omarchy-style keyboard shortcuts on Right Command (Super), tiling windows, themes and system settings. Running it again only fixes what is missing, so the same command also repairs a Mac.

## On the new Mac

1. Finish Apple's setup screens (Apple ID, user account, FileVault).
2. Copy this folder to the new Mac. AirDrop from the old Mac is easiest. It lands in Downloads.
3. Open Terminal and run:

   ```
   bash ~/Downloads/mac-setup/setup.sh
   ```

4. Type your Mac password once when asked. The rest runs unattended for 30 to 60 minutes.
5. Work through `Finish setup.txt`, which appears on the Desktop at the end. It lists the clicks macOS insists on (Karabiner and AeroSpace permissions, notifications, Google Drive, app sign-ins).

The first run copies the package to `~/mac-setup`. That copy is the one to edit and keep. Later runs, from anywhere, use it.

## Everyday commands

| Command | Does |
| --- | --- |
| `update` | Updates every app, tool and this package |
| `keybindings --print` | Prints every shortcut |
| `theme pick` | Changes theme (Graphite, Nord, Forest, Paper) |
| `app install`, `app remove` | Installs or removes an app and updates the Brewfile to match (also in the menu) |
| `tidy-downloads` | Sorts Downloads now (`--dry-run` shows the plan, `--log` the recent moves) |
| `default-apps fallback` | LibreOffice and Preview open documents instead of ArtCraft (`primary` switches back). Videos stay in IINA |
| `bash ~/mac-setup/setup.sh --only artcraft` | Re-runs one step (`--list` shows them) |
| `bash ~/mac-setup/setup.sh --dry-run` | Shows what setup would do, changes nothing |

## The terminal

Ghostty with Omarchy's shell tools, set up in `config/zsh/mac-setup.zsh`, `config/tmux/tmux.conf` and `config/starship.toml`.

| Type | Does |
| --- | --- |
| `cd res` | Jumps to the folder you use most that matches "res" (zoxide) |
| `ff` | Finds a file by name with a live preview (fzf) |
| Ctrl + R | Searches your command history as you type |
| `ls`, `lt`, `lsa` | Lists files with icons, as a tree, or including hidden files (eza) |
| `rg word`, `fd name` | Searches inside files, or for files by name |
| `compress folder`, `decompress file` | Makes a .tar.gz, or opens any archive (.zip, .tar.gz, .7z, .rar) with macOS's own tar |
| `tdl` | Splits the window: terminal on the left, Claude Code on the right (`tdl codex` for Codex) |
| Super + Option + Return | Opens a terminal inside a lasting tmux session |
| Ctrl + Space, then ? | Lists every tmux key: Option + Return splits, Option + Escape closes a pane |

## Where files live

| Place | Holds | Why |
| --- | --- | --- |
| `~/Drive` (Google Drive, My Drive) | Documents, research, everything to keep | Synced and backed up. Finder windows and the first save dialog in each app open here |
| `~/Developer` | Code and anything you build | Local and on GitHub. Drive sync corrupts git folders and slows builds |
| `~/Downloads` | An inbox only | Sorted as files arrive (below), then filed into Drive by you |
| `~/Pictures/Screenshots` | Screenshots and recordings | Keeps the Desktop clear |
| Inside the Docker VM | Containers and their data | Removed with `colima delete` when no longer needed |

Research follows the Drive layout: each paper has one folder under `01 Research` (by status: `_Active`, `_Under-Review`, `_Published` and so on), and one-off Claude work goes to `Claude Projects`.

## Building

As in Omarchy: mise for language versions, uv for Python packages, Docker, lazygit, lazydocker and btop, with Neovim and LazyVim as the editor and Claude Code or Codex beside it (`tdl`).

| Type | Does |
| --- | --- |
| Super menu, Toggle, Docker | Starts or stops Docker (a Colima VM: 6 cores, 12 GB memory, Rosetta for Intel images). Nothing runs until you start it |
| `mise use node@22` | Pins a language version for the current project |
| `uv init`, `uv add pandas` | Starts a Python project and adds packages |
| `n` | Neovim (LazyVim). Space Space finds a file, Space / searches text, Space g g opens lazygit, Space e the file tree |
| `cx`, `codex` | Claude Code or Codex in the current folder |
| `ccusage`, `ccusage blocks --live` | Claude Code token use by day, and the current usage window as it runs |
| Super menu, Transcode, To text | Turns selected PDFs and Word files into plain text before giving them to an AI, which costs far fewer tokens than PDF pages |
| `bat file`, `tldr command` | Shows a file with syntax colours, or short examples for a command |
| `duckdb` | SQL straight over CSV or Parquet files: `duckdb -c "select count(*) from 'export.csv'"` |
| Super menu, Toggle, Local AI | Starts or stops Ollama for local models (`ollama run llama3.2`). Nothing runs until you start it |
| `lzg`, `lzd`, `btop` | Git, containers, and system load in the terminal |
| `g`, `gcm "message"`, `gcam`, `gcad` | git, commit, commit all, amend |

For the homelab: Tailscale joins this Mac to a private network with your NAS and servers. `nmap`, `mtr`, `iperf3` and `wakeonlan` find, trace, speed-test and wake machines. `fip server 8080` forwards a server's port to this Mac, `dip 8080` stops it, and `lip` lists them. `iso2sd image.iso disk4` writes an image to an SD card or USB stick, and refuses internal disks.

Building native Mac apps (such as the search app) needs Xcode from the App Store. Install it when that work starts. It is about 15 GB.

## Downloads

New files are sorted as they arrive, by the rules in `config/mac-setup/downloads-rules.tsv`. Files from Claude, ChatGPT and Gemini go to `Downloads/AI/<app>`, papers from journal and PubMed sites to `Downloads/Papers`, and everything else by type (Documents, Data, Slides, Images, Video, Installers and so on). Installers go to the Trash after a week, and anything left loose moves to `Downloads/Archive/<year-month>` after 30 days. Nothing is deleted, and every move is logged. The first time it runs, macOS asks whether downloads-agent (the sorter's own small launcher) may use Downloads. Allow it. No other program gets that access.

## Text shortcuts

Espanso replaces short triggers as you type, in any app: `;date` (October 31, 2026), `;iso` (2026-10-31), `;time` (14:05), `;sig` (your signature), `;br`, `;ty`, `;ci`, `;sd`. Add your own in `config/espanso/match/mac-setup.yml`.

## The Super key (Right Command)

Hold Right Command where Omarchy uses the Super key. Left Command and Caps Lock work as on any Mac, and any Right Command combination not listed below is plain Command. Super + K lists every shortcut and runs the one you pick. The table is generated from `tools/bindings.py` (workspaces 2 to 8 follow the same pattern as 1 and 9).

<!-- shortcuts:start (generated by tools/bindings.py) -->

| Keys | Action |
| --- | --- |
| Super + Space | Search (Spotlight until the search app ships) |
| Super + Option + Space | Main menu |
| Super + K | Shortcut list (type to filter, Return runs it) |
| Super + Escape | System menu (lock, sleep, restart, shut down) |
| Super + Ctrl + L | Lock screen |
| Super + T | Toggle tiling and floating |
| Super + J | Toggle split direction |
| Super + F | Full screen |
| Super + G | Toggle grouping (stacked windows) |
| Super + = | Grow window |
| Super + - | Shrink window |
| Super + Left | Focus window left |
| Super + Shift + Left | Swap window left |
| Super + Down | Focus window down |
| Super + Shift + Down | Swap window down |
| Super + Up | Focus window up |
| Super + Shift + Up | Swap window up |
| Super + Right | Focus window right |
| Super + Shift + Right | Swap window right |
| Super + Tab | Next workspace |
| Super + Shift + Tab | Previous workspace |
| Super + Ctrl + Tab | Last used workspace |
| Super + Option + Tab | Focus next monitor |
| Super + Option + Shift + Left | Move workspace to previous monitor |
| Super + Option + Shift + Right | Move workspace to next monitor |
| Super + 1 | Go to workspace 1 |
| Super + Shift + 1 | Move window to workspace 1 and follow |
| Super + Option + Shift + 1 | Move window to workspace 1, stay here |
| Super + 9 | Go to workspace 9 |
| Super + Shift + 9 | Move window to workspace 9 and follow |
| Super + Option + Shift + 9 | Move window to workspace 9, stay here |
| Super + Return | Terminal (Ghostty) |
| Super + Option + Return | Terminal in a tmux session |
| Super + Shift + Return | Browser (Chrome) |
| Super + Option + Shift + B | Private browser window |
| Super + Shift + F | Finder |
| Super + Shift + D | Google Drive folder |
| Super + Shift + A | Claude |
| Super + Option + Shift + A | ChatGPT |
| Super + Ctrl + Shift + A | Gemini |
| Super + Shift + N | Notion |
| Super + Shift + T | Reminders (tasks) |
| Super + Shift + G | WhatsApp |
| Super + Shift + M | Spotify |
| Super + Shift + R | RStudio |
| Super + Shift + W | WordCraft (documents) |
| Super + Shift + S | GridCraft (spreadsheets) |
| Super + Shift + K | DeckCraft (presentations) |
| Super + Shift + O | PdfCraft (PDFs) |
| Super + Shift + V | FilmCraft (video) |
| Super + Shift + / | Passwords |
| Super + Shift + E | Gmail |
| Super + Shift + C | Google Calendar |
| Super + Shift + P | PubMed |
| Super + Shift + Y | YouTube |
| Super + Ctrl + A | Audio output menu |
| Super + Ctrl + M | Next audio output |
| Super + Ctrl + B | Bluetooth menu |
| Super + Ctrl + W | Wi-Fi settings |
| Super + Ctrl + S | Share with AirDrop |
| Super + Ctrl + T | What is using the Mac (btop) |
| Super + Ctrl + H | Hardware menu |
| Super + Ctrl + O | Toggle menu |
| Super + Ctrl + C | Capture menu |
| Super + Ctrl + Shift + X | Copy text from a screen area |
| Super + Ctrl + . | Transcode menu (video, images, PDF) |
| Super + Option + V | Paste as plain text (no formatting) |
| Super + Ctrl + V | Clipboard history (Maccy) |
| Super + Ctrl + E | Emoji and symbols |
| Super + Ctrl + X | Dictate: hold, speak, release (Handy) |
| Super + Ctrl + Option + M | Record and transcribe a meeting (Meetily) |
| Super + Ctrl + I | Keep the Mac awake |
| Super + Ctrl + N | Dark and light mode |
| Super + Shift + Space | Hide or show the menu bar |
| Super + Ctrl + Shift + M | Mute or unmute the microphone |
| Super + Ctrl + R | Set a reminder |
| Super + Ctrl + Option + T | Show the time |
| Super + Ctrl + Option + B | Show the battery |
| Super + Ctrl + Option + W | Show the weather |
| Super + Ctrl + Shift + Space | Pick a theme |
| Super + Ctrl + Space | Next background |

<!-- shortcuts:end -->

## How to add things

| To add | Do this |
| --- | --- |
| An app | Add a `cask "name"` line to `Brewfile`, then `bash ~/mac-setup/setup.sh --only apps` |
| An ArtCraft app | Add a line to `config/mac-setup/artcraft.tsv`, then `--only artcraft` |
| A default app for a file type | Add a line to `config/mac-setup/default-apps.tsv`, then `--only default-apps` |
| A shortcut | Add a line to `BINDINGS` in `tools/bindings.py`, run `python3 tools/bindings.py`, then `--only dotfiles` |
| A menu entry | Add a line to `config/mac-setup/menu.tsv`. It works at once |
| A command | Add an executable script to `bin/`. It is on the PATH at once |
| A theme | Add `config/themes/name.theme` (copy an existing one) and its image to `backgrounds/` |
| An R package | Add a line to `config/mac-setup/r-packages.txt`, then `--only r-packages` |
| A native helper | Add `tools/name.swift`. Setup builds it into `~/.mac-setup/.build` |
| A setup step | Add `steps/NN-name.sh` with a function `step_name`. Steps run in file-name order |

The future search app takes over Super + Space by changing that one line in `tools/bindings.py` and turning off Spotlight's own shortcut in System Settings, Keyboard Shortcuts.

## Testing

Run these before installing on a new Mac, and after any change.

1. **Quick checks, any computer, about 1 minute.** Syntax, lint, macOS bash 3.2 compatibility, config validity, generated files up to date, menus, themes, the ArtCraft download choice, a full dry run that must not touch the home folder, and every Brewfile name against Homebrew's live catalogue.

   ```
   bash tests/run-all.sh
   ```

2. **GitHub's macOS machines.** Every push runs the quick checks on Linux and on macOS. In the Actions tab, "Run workflow" also runs the full install on clean macOS 27 and macOS 26 machines, checks the result, and runs setup again, failing if the second run changes anything. The full install also runs every Monday, to catch apps renamed or removed from Homebrew.

3. **A disposable macOS virtual machine on an Apple silicon Mac, 30 to 60 minutes.** The closest rehearsal to a real install, with a fresh copy of macOS. Needs about 70 GB free.

   ```
   bash tests/vm-test.sh            # run and report
   bash tests/vm-test.sh --keep     # leave the VM open to look around
   bash tests/vm-test.sh --clean    # delete the VM afterwards
   ```

   Karabiner's keyboard driver cannot load inside a virtual machine, so try the Super key shortcuts on the real Mac.

After setup on any Mac, `bash ~/mac-setup/tests/verify-install.sh` checks every app, link, default app and setting.

## What runs in the background

Kept deliberately small: Karabiner-Elements (keyboard), AeroSpace (windows), Maccy (clipboard), Espanso (text shortcuts), Handy (waits for the dictation key) and Google Drive. Docker, local AI (Ollama) and the VPNs run only while you turn them on. Shortcut commands start, act and exit, and long jobs (video compression, keep-awake, app installs) run on their own so they never block the keyboard. The Downloads sorter is not a running process: macOS starts it at low priority when Downloads changes, and once an hour for the age rules. Nothing in the package indexes. The checklist shows how to stop other apps opening at login.

## Security

Every run checks that the firewall (in stealth mode) and automatic security updates are on, and warns if FileVault is off. Nothing turns off Gatekeeper or System Integrity Protection. ArtCraft downloads must carry the expected app name, match GitHub's checksum when one is published, and keep the same signing developer on every update. An app that Apple has not notarized is flagged so macOS asks before it first opens. sudo is used only by the steps that need it, then closed. The Downloads permission belongs to the sorter's own launcher, not to bash. Clipboard history ignores Citrix and Horizon, so patient information is not kept. Neovim plugins are pinned, and the GitHub test runs can only read the repository. Nothing is ever deleted: removed apps, old installers and replaced files go to the Trash, and removing an app keeps its data. No service listens on the network: Ollama and Docker answer only on this Mac.

## Running setup again

Setup only fills in what is missing, so it is safe to run any time, and `update` runs it for you. Settings you change yourself are kept: system settings, the Dock and the checklist are applied on the first run only. To apply one again, name its step, for example `bash ~/mac-setup/setup.sh --only macos-defaults`.

## Layout

```
setup.sh            entry point (runs steps/ in order)
Brewfile            apps and tools
steps/              one file per setup step
bin/                commands behind the menus and shortcuts
lib/                shared helpers and paths
config/             aerospace, karabiner, ghostty, tmux, zsh, starship, nvim, git,
                    espanso, themes, and mac-setup (menus, rules, data files)
backgrounds/        theme wallpapers
tools/              shortcut generator and native helpers (Swift)
tests/              checks, dry run, VM rehearsal, post-install verification
.github/workflows/  the GitHub test runs
publish.sh          first upload of this package to GitHub
```
