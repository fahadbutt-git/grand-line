# Mac setup

One command turns a new Mac into a ready workstation: apps, command line tools, the ArtCraft office apps as defaults, an Omarchy-style keyboard layer on Caps Lock, tiling windows, themes and system settings. Running it again only fixes what is missing, so the same command also repairs a Mac.

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
| `default-apps fallback` | LibreOffice, Preview and IINA open documents instead of ArtCraft (`primary` switches back) |
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
| `compress folder`, `decompress file` | Makes a .tar.gz, or opens any archive (.zip, .tar.gz, .7z, .rar) |
| `tdl` | Splits the window: terminal on the left, Claude Code on the right (`tdl codex` for Codex) |
| Caps + Option + Return | Opens a terminal inside a lasting tmux session |
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

As in Omarchy: mise for language versions, uv for Python packages, Docker, lazygit, lazydocker and btop, with Zed as the editor and Claude Code or Codex in the terminal (`tdl`).

| Type | Does |
| --- | --- |
| Caps menu, Toggle, Docker | Starts or stops Docker (a Colima VM: 6 cores, 12 GB memory, Rosetta for Intel images). Nothing runs until you start it |
| `mise use node@22` | Pins a language version for the current project |
| `uv init`, `uv add pandas` | Starts a Python project and adds packages |
| `lzg`, `lzd`, `btop` | Git, containers, and system load in the terminal |
| `g`, `gcm "message"`, `gcam`, `gcad` | git, commit, commit all, amend |

Building native Mac apps (such as the search app) needs Xcode from the App Store. Install it when that work starts. It is about 15 GB.

## Downloads

New files are sorted as they arrive, by the rules in `config/mac-setup/downloads-rules.tsv`. Files from Claude, ChatGPT and Gemini go to `Downloads/AI/<app>`, papers from journal and PubMed sites to `Downloads/Papers`, and everything else by type (Documents, Data, Slides, Images, Video, Installers and so on). Installers go to the Trash after a week, and anything left loose moves to `Downloads/Archive/<year-month>` after 30 days. Nothing is deleted, and every move is logged. The first time it runs, macOS asks whether bash may use Downloads. Allow it.

## Text shortcuts

Espanso replaces short triggers as you type, in any app: `;date` (October 31, 2026), `;iso` (2026-10-31), `;sig` (your signature), `;br`, `;ty`, `;ci`, `;sd`. Add your own in `config/espanso/match/mac-setup.yml`.

## The Caps Lock layer

Hold Caps Lock where Omarchy uses the Super key. Tap it alone for Escape. Caps + K lists every shortcut and runs the one you pick. The table is generated from `tools/bindings.py` (workspaces 2 to 8 follow the same pattern as 1 and 9).

<!-- shortcuts:start (generated by tools/bindings.py) -->

| Keys | Action |
| --- | --- |
| Caps + Space | Search (Spotlight until the search app ships) |
| Caps + Option + Space | Main menu |
| Caps + K | Shortcut list (type to filter, Return runs it) |
| Caps + Escape | System menu (lock, sleep, restart, shut down) |
| Caps + W | Close window |
| Caps + Ctrl + L | Lock screen |
| Caps + T | Toggle tiling and floating |
| Caps + J | Toggle split direction |
| Caps + F | Full screen |
| Caps + G | Toggle grouping (stacked windows) |
| Caps + = | Grow window |
| Caps + - | Shrink window |
| Caps + Left | Focus window left |
| Caps + Shift + Left | Swap window left |
| Caps + Down | Focus window down |
| Caps + Shift + Down | Swap window down |
| Caps + Up | Focus window up |
| Caps + Shift + Up | Swap window up |
| Caps + Right | Focus window right |
| Caps + Shift + Right | Swap window right |
| Caps + Tab | Next workspace |
| Caps + Shift + Tab | Previous workspace |
| Caps + Ctrl + Tab | Last used workspace |
| Caps + Option + Tab | Focus next monitor |
| Caps + Option + Shift + Left | Move workspace to previous monitor |
| Caps + Option + Shift + Right | Move workspace to next monitor |
| Caps + 1 | Go to workspace 1 |
| Caps + Shift + 1 | Move window to workspace 1 and follow |
| Caps + Option + Shift + 1 | Move window to workspace 1, stay here |
| Caps + 9 | Go to workspace 9 |
| Caps + Shift + 9 | Move window to workspace 9 and follow |
| Caps + Option + Shift + 9 | Move window to workspace 9, stay here |
| Caps + Return | Terminal (Ghostty) |
| Caps + Option + Return | Terminal in a tmux session |
| Caps + Shift + Return | Browser (Chrome) |
| Caps + Option + Shift + B | Private browser window |
| Caps + Shift + F | Finder |
| Caps + Shift + D | Google Drive folder |
| Caps + Shift + A | Claude |
| Caps + Option + Shift + A | ChatGPT |
| Caps + Ctrl + Shift + A | Gemini |
| Caps + Shift + N | Notion |
| Caps + Shift + T | Reminders (tasks) |
| Caps + Shift + G | WhatsApp |
| Caps + Shift + M | Spotify |
| Caps + Shift + R | RStudio |
| Caps + Shift + W | WordCraft (documents) |
| Caps + Shift + S | GridCraft (spreadsheets) |
| Caps + Shift + K | DeckCraft (presentations) |
| Caps + Shift + O | PdfCraft (PDFs) |
| Caps + Shift + V | FilmCraft (video) |
| Caps + Shift + / | Passwords |
| Caps + Shift + E | Gmail |
| Caps + Shift + C | Google Calendar |
| Caps + Shift + P | PubMed |
| Caps + Shift + Y | YouTube |
| Caps + Ctrl + A | Audio output menu |
| Caps + Ctrl + M | Next audio output |
| Caps + Ctrl + B | Bluetooth menu |
| Caps + Ctrl + W | Wi-Fi settings |
| Caps + Ctrl + S | Share with AirDrop |
| Caps + Ctrl + T | Activity Monitor |
| Caps + Ctrl + H | Hardware menu |
| Caps + Ctrl + O | Toggle menu |
| Caps + Ctrl + C | Capture menu |
| Caps + Ctrl + X | Copy text from a screen area |
| Caps + Ctrl + . | Transcode menu (video, images, PDF) |
| Caps + Ctrl + V | Clipboard history (Maccy) |
| Caps + Ctrl + E | Emoji and symbols |
| Caps + Ctrl + I | Keep the Mac awake |
| Caps + Ctrl + N | Dark and light mode |
| Caps + Shift + Space | Hide or show the menu bar |
| Caps + Ctrl + R | Set a reminder |
| Caps + Ctrl + Option + T | Show the time |
| Caps + Ctrl + Option + B | Show the battery |
| Caps + Ctrl + Option + W | Show the weather |
| Caps + Ctrl + Shift + Space | Pick a theme |
| Caps + Ctrl + Space | Next background |

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

The future search app takes over Caps + Space by changing that one line in `tools/bindings.py` and turning off Spotlight's own shortcut in System Settings, Keyboard Shortcuts.

## Testing

Run these before installing on a new Mac, and after any change.

1. **Quick checks, any computer, about 1 minute.** Syntax, lint, macOS bash 3.2 compatibility, config validity, generated files up to date, menus, themes, the ArtCraft download choice, a full dry run that must not touch the home folder, and every Brewfile name against Homebrew's live catalogue.

   ```
   bash tests/run-all.sh
   ```

2. **GitHub's macOS machines.** Every push runs the quick checks on Linux and on macOS. In the Actions tab, "Run workflow" also runs the full install on a clean Mac, checks the result, and runs setup again to prove it is safe to repeat.

3. **A disposable macOS virtual machine on an Apple silicon Mac, 30 to 60 minutes.** The closest rehearsal to a real install, with a fresh copy of macOS. Needs about 70 GB free.

   ```
   bash tests/vm-test.sh            # run and report
   bash tests/vm-test.sh --keep     # leave the VM open to look around
   bash tests/vm-test.sh --clean    # delete the VM afterwards
   ```

   Karabiner's keyboard driver cannot load inside a virtual machine, so try the Caps Lock layer on the real Mac.

After setup on any Mac, `bash ~/mac-setup/tests/verify-install.sh` checks every app, link, default app and setting.

## What runs in the background

Kept deliberately small: Karabiner-Elements (keyboard), AeroSpace (windows), Maccy (clipboard), Espanso (text shortcuts) and Google Drive. Shortcut commands start, act and exit, and long jobs (video compression, keep-awake, app installs) run on their own so they never block the keyboard. The Downloads sorter is not a running process: macOS starts it at low priority when Downloads changes, and once an hour for the age rules, and it exits in well under a second. Nothing in the package indexes. The checklist turns off the apps that open themselves at login.

## Layout

```
setup.sh            entry point (runs steps/ in order)
Brewfile            apps and tools
steps/              one file per setup step
bin/                commands behind the menus and shortcuts
lib/                shared helpers and paths
config/             Karabiner, AeroSpace, Ghostty, menus, themes, data files
backgrounds/        theme wallpapers
tools/              shortcut generator and native helpers (Swift)
tests/              checks, dry run, VM rehearsal, post-install verification
```
