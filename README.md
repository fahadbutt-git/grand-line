# Grand Line

One command turns a new Mac into a ready workstation: apps, command line tools, the ArtCraft office apps as defaults, an Omarchy-style keyboard layer on Caps Lock, tiling windows, themes and system settings. Running it again only fixes what is missing, so the same command also repairs a Mac.

## On the new Mac

1. Finish Apple's setup screens (Apple ID, user account, FileVault).
2. Copy this folder to the new Mac. AirDrop from the old Mac is easiest. It lands in Downloads.
3. Open Terminal and run:

   ```
   bash ~/Downloads/grand-line/setup.sh
   ```

4. Type your Mac password once when asked. The rest runs unattended for 30 to 60 minutes.
5. Work through `Finish setup.txt`, which opens at the end (it is saved in Documents). It lists the clicks macOS insists on (Karabiner and AeroSpace permissions, notifications, Google Drive, app sign-ins).

The first run copies the package to `~/grand-line`. That copy is the one to edit and keep. Later runs, from anywhere, use it.

## Everyday commands

| Command | Does |
| --- | --- |
| `update` | Updates every app, tool and this package, then runs any one-time changes and your post-update hook. New commits from GitHub are checked first (see "Updates" below): unsigned ones are shown and applied only if you say yes. One run at a time, the Mac stays awake, and the whole run is saved to `~/Library/Logs/grand-line/update-<date>.log`. It also records what was installed before (`~/.local/state/grand-line/brew-before-update.Brewfile`) and says when Karabiner-Elements or AeroSpace need a restart. `update --window` runs it in its own terminal window |
| `update auto on`, `off`, `status` | The daily unattended update (also in the Update menu) |
| `update --apps-only --notify` | Updates this package and rebuilds only the apps whose sources changed, then posts one notification. The apps' "Update now" buttons run this |
| `keybindings --print` | Prints every shortcut |
| `theme pick` | Changes theme (Graphite, Daylight, Nord, Forest, and the Harbour, Lantern, Signal, Ledger, Atlas and Paper families, each dark and light): terminal, editor, menus, tmux, btop, lazygit, Claude Code, the apps and their icons, accent and wallpaper together. Rules in `DESIGN.md` |
| `theme set harbour` | A family in the variant that matches the current macOS appearance (`theme set harbour-light` names one) |
| `theme mode toggle` | The other variant of the current family (Graphite and Daylight pair up too). `toggle dark` switches the macOS appearance, and the variant too while the theme follows macOS |
| `grandline commands` | Lists every command in the package with what it does |
| `migrate --pending` | Lists the one-time changes an update has not run yet (`migrate` runs them) |
| `app install`, `app remove` | Installs or removes an app and updates the Brewfile to match (also in the menu). `grandline publish` shares the change with your other Macs |
| `tidy-downloads` | Sorts Downloads now (`--dry-run` shows the plan, `--log` the recent moves) |
| `default-apps fallback` | LibreOffice and Preview open documents instead of ArtCraft (`primary` switches back). Videos stay in IINA |
| `bash ~/grand-line/setup.sh --only artcraft` | Re-runs one step (`--list` shows them) |
| `bash ~/grand-line/setup.sh --dry-run` | Shows what setup would do, changes nothing |

## The terminal

Ghostty with Omarchy's shell tools, set up in `config/zsh/grand-line.zsh`, `config/tmux/tmux.conf` and `config/starship.toml`.

| Type | Does |
| --- | --- |
| `cd res` | Jumps to the folder you use most that matches "res" (zoxide) |
| `ff` | Finds a file by name with a live preview (fzf) |
| `eff` | Finds a file the same way, then opens it in the editor |
| `n`, `n file` | Opens Neovim on this folder, or on the file |
| `..`, `...` | Goes up one folder, or two |
| `t` | Joins the running tmux session, or starts one |
| `ga name`, `gd` | Starts a branch in its own folder beside this one (a git worktree), and removes it again from inside |
| Ctrl + R | Searches your command history as you type |
| `ls`, `lt`, `lsa` | Lists files with icons, as a tree, or including hidden files (eza) |
| `rg word`, `fd name` | Searches inside files, or for files by name |
| `compress folder`, `decompress file` | Makes a .tar.gz, or opens any archive (.zip, .tar.gz, .7z, .rar) with macOS's own tar |
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

## Building

As in Omarchy: mise for language versions, uv for Python packages, Docker, lazygit, lazydocker and btop, with Neovim and LazyVim as the editor and Claude Code or Codex beside it (`tdl`).

| Type | Does |
| --- | --- |
| Caps menu, Toggle, Docker | Starts or stops Docker (a Colima VM: 6 cores, 12 GB memory, Rosetta for Intel images). Nothing runs until you start it |
| `mise use node@22` | Pins a language version for the current project |
| `uv init`, `uv add pandas` | Starts a Python project and adds packages |
| `n` | Neovim (LazyVim). Space Space finds a file, Space / searches text, Space g g opens lazygit, Space e the file tree |
| `cx`, `codex` | Claude Code or Codex in the current folder |
| `ccusage`, `ccusage blocks --live` | Claude Code token use by day, and the current usage window as it runs |
| Caps menu, Transcode, To text | Turns selected PDFs and Word files into plain text before giving them to an AI, which costs far fewer tokens than PDF pages |
| `bat file`, `tldr command` | Shows a file with syntax colours, or short examples for a command |
| `duckdb` | SQL straight over CSV or Parquet files: `duckdb -c "select count(*) from 'export.csv'"` |
| Caps menu, Toggle, Local AI | Starts or stops Ollama for local models (`ollama run llama3.2`). Nothing runs until you start it |
| `lzg`, `lzd`, `btop` | Git, containers, and system load in the terminal |
| `nx` | Opens this folder in Nexus (`nx ~/Drive` for another). `lp` still works for now |
| `g`, `gcm "message"`, `gcam`, `gcad` | git, commit, commit all, amend |

For the homelab: Tailscale joins this Mac to a private network with your NAS and servers. `nmap`, `mtr`, `iperf3` and `wakeonlan` find, trace, speed-test and wake machines. `fip server 8080` forwards a server's port to this Mac, `dip 8080` stops it, and `lip` lists them. `iso2sd image.iso disk4` writes an image to an SD card or USB stick, and refuses internal disks.

Setup builds the package's own apps with Apple's command line tools. Xcode (about 15 GB, from the App Store) is needed only to run their tests on this Mac or to use its editor.

## Downloads

New files are sorted as they arrive, by the rules in `config/grand-line/downloads-rules.tsv`. Files from Claude, ChatGPT and Gemini go to `Downloads/AI/<app>`, papers from journal and PubMed sites to `Downloads/Papers`, and everything else by type (Documents, Data, Slides, Images, Video, Installers and so on). Installers go to the Trash a week after they arrived, and anything left loose moves to `Downloads/Archive/<year-month>` 30 days after it arrived. Age is when the file arrived in its folder (as macOS records it, or else the inode's change time), never its modification time, which travels with a file unpacked from a zip or sent by AirDrop. A file the sorter is seeing for the first time is never moved by age, unfinished downloads (including the empty placeholder Firefox and Zen keep beside a `.part` file) are left alone, a move never replaces a file, and only one sort runs at a time. Nothing is deleted, and every move is logged. The first time it runs, macOS asks whether downloads-agent (the sorter's own small launcher) may use Downloads. Allow it. No other program gets that access.

## Text shortcuts

Espanso replaces short triggers as you type, in any app: `;date` (October 31, 2026), `;iso` (2026-10-31), `;time` (14:05), `;sig` (your signature), `;br`, `;ty`, `;ci`, `;sd`. Add your own in `config/espanso/match/grand-line.yml`.

**Your details.** The first setup asks for your name, email, sign-off, signature and town. They are saved on this Mac only, in `~/.config/grand-line/personal.env`, and never go in the repo, so the repo can be public. Git, `;br`, `;sig` and the weather notice read them. To change one, edit that file and run `grandline update`.

## The Caps Lock layer

Hold Caps Lock where Omarchy uses the Super key. Tap it alone for Escape. Caps + K lists every shortcut and runs the one you pick. The table is generated from `tools/bindings.py` (workspaces 2 to 8 follow the same pattern as 1 and 9).

<!-- shortcuts:start (generated by tools/bindings.py) -->

| Keys | Action |
| --- | --- |
| Caps + Space | Search (Sight, or Spotlight if switched back) |
| Caps + Option + Space | Main menu |
| Caps + K | Shortcut list (type to filter, Return runs it) |
| Caps + Escape | System menu (lock, sleep, restart, shut down) |
| Caps + W | Close window |
| Caps + Q | Quit app |
| Caps + Ctrl + L | Lock screen |
| Caps + T | Toggle tiling and floating |
| Caps + J | Toggle split direction |
| Caps + F | Full screen |
| Caps + G | Toggle grouping (stacked windows) |
| Caps + = | Grow window |
| Caps + - | Shrink window |
| Caps + Left | Focus window left |
| Caps + Shift + Left | Swap window left |
| Caps + Ctrl + Shift + Left | Move window to the monitor left |
| Caps + Down | Focus window down |
| Caps + Shift + Down | Swap window down |
| Caps + Ctrl + Shift + Down | Move window to the monitor down |
| Caps + Up | Focus window up |
| Caps + Shift + Up | Swap window up |
| Caps + Ctrl + Shift + Up | Move window to the monitor up |
| Caps + Right | Focus window right |
| Caps + Shift + Right | Swap window right |
| Caps + Ctrl + Shift + Right | Move window to the monitor right |
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
| Caps + ` | Quick terminal (drops down from the top) |
| Caps + Option + Return | Terminal in a tmux session |
| Caps + Shift + Return | Browser (Zen) |
| Caps + Option + Shift + B | Private browser window |
| Caps + Shift + F | Files (Nexus, or Finder if switched back) |
| Caps + Shift + D | Google Drive folder |
| Caps + Shift + A | Claude |
| Caps + Option + Shift + A | ChatGPT |
| Caps + Ctrl + Shift + A | Gemini |
| Caps + Shift + N | Notion |
| Caps + Ctrl + Option + N | Open or close the notch panel (Iceberg) |
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
| Caps + Ctrl + Option + V | Volume for each app (FineTune) |
| Caps + Ctrl + B | Bluetooth menu |
| Caps + Ctrl + W | Wi-Fi settings |
| Caps + Ctrl + S | Share with AirDrop |
| Caps + Ctrl + T | What is using the Mac (btop) |
| Caps + Ctrl + H | Hardware menu |
| Caps + Ctrl + O | Toggle menu |
| Caps + Ctrl + C | Capture menu |
| Caps + Ctrl + Shift + X | Copy text from a screen area |
| Caps + Ctrl + P | Colour picker |
| Caps + Ctrl + . | Transcode menu (video, images, PDF) |
| Caps + A | Select all |
| Caps + C | Copy |
| Caps + X | Cut |
| Caps + V | Paste |
| Caps + Option + V | Paste as plain text (no formatting) |
| Caps + Ctrl + V | Clipboard history (Maccy) |
| Caps + Ctrl + E | Emoji and symbols |
| Caps + Ctrl + X | Dictate: hold, speak, release (Handy) |
| Caps + Ctrl + Option + M | Record and transcribe a meeting (Meetily) |
| Caps + Ctrl + I | Keep the Mac awake |
| Caps + Ctrl + N | Dark and light mode |
| Caps + Shift + Space | Hide or show the menu bar |
| Caps + Ctrl + Shift + M | Mute or unmute the microphone |
| Caps + Ctrl + R | Set a reminder |
| Caps + Ctrl + Option + R | Reminders due today |
| Caps + Ctrl + Option + T | Show the time |
| Caps + Ctrl + Option + B | Show the battery |
| Caps + Ctrl + Option + W | Show the weather |
| Caps + Ctrl + Shift + Space | Pick a theme |
| Caps + Ctrl + Space | Next background |

<!-- shortcuts:end -->

## The package's own apps

Nexus (files), Sight (search) and Iceberg (the notch) are built on this Mac from `apps/`, by the native-tools step, and installed in `/Applications`. Each app folder is a Swift package with an `apps.tsv` that names what it makes (product, app name, bundle id, and whether it lives in the menu bar only). Setup rebuilds an app only when its sources change (or the shared `apps/icons` package does), and the old copy goes to the Trash.

Nexus, Sight and Iceberg were formerly Log Pose, Byakugan and Den Den. The first `update` after the rename carries their settings, index and state over (`migrations/1793472900-rename-apps.sh`), and the old apps go to the Trash.

### Signing and permissions

Setup makes one code-signing identity on this Mac, "Grand Line Local Signing" (`lib/signing.sh`), and signs every app with it, with hardened runtime. macOS ties Accessibility, Calendars and Automation to the certificate rather than to one build, so a rebuilt app keeps its permissions. The first build signed this way asks for each permission once more. The apps ask for nothing beyond hardened runtime except what they use: Apple events (all three) and Calendars (Iceberg), in `apps/*/Entitlements/`. Iceberg's Now Playing adapter is loaded by Apple's own `/usr/bin/perl`, not by Iceberg, so library validation stays on.

Because the key is what keeps the permissions, it is guarded: it lives in its own keychain (`~/Library/Keychains/grand-line-signing.keychain-db`, locked after each use and after 5 minutes), it cannot be exported, only Apple's `codesign` may use it, the keychain's random password is kept only in your login keychain, and passwords never appear on a command line. The certificate is for code signing only and is trusted for that by you alone. A program already running as you could still ask `codesign` to sign, which is why the unattended update builds only signature-checked commits from a clean tree. If the identity cannot be made, or macOS will not sign with it (its certificate is not trusted for code signing, as on a test machine), the apps and helpers are signed ad hoc and setup says so once per run. An installed copy signed with the identity is never replaced by an ad hoc one: it is kept until the identity signs again.

Grand Line Index is the shared file index Nexus and Sight search through. It runs in the background: its launch agent is inside the app (sealed by its signature) and the app registers it itself (`GrandLineIndex --register`), as you, never with sudo. It needs Full Disk Access (or Files and Folders for Desktop, Documents, Downloads and Google Drive); the checklist says where.

Each app draws its icon in the theme's colours when it starts and whenever the theme changes (the `ICON_*` keys in `DESIGN.md`), for the Dock and for Finder. The bundles also carry a fixed `AppIcon.icns` in Graphite's colours, drawn by `python3 tools/make-icons.py` from the same glyph table (`apps/icons/Sources/AppIcon/Glyphs.swift`), so an app has an icon before it first runs. `theme set` and `theme mode` then put icons in the new theme's colours into the installed apps in the background (`theme icons`; `make-icons.py --out DIR`), and sign them again with the same identity, so Finder matches the theme and the permissions stay. Without the identity this is skipped, since an ad-hoc signature would cost the permissions. After changing a glyph, run the script and commit the `.icns` files; `tests/run-all.sh` checks they are sound.

Once installed, Nexus opens folders and every "Show in Finder", and Sight answers Command + Space (so Caps + Space too). Both switch back from the Toggle menu, or with `toggle files` and `toggle search`, and the choice is kept across updates.

### Changing settings from Sight

Typing a setting changes it, rather than opening System Settings. The row shows the state it read when the window opened ("Wi-Fi: On, Return turns it off"), Return makes the change, and the row then shows the state read back from the Mac, so a second Return undoes it. Command + Return opens the setting's pane instead. If a change fails, the row says why, and when macOS needs a permission, Return opens that part of Privacy & Security. The window stays open after a change; `defaults write com.grandline.sight CloseAfterSettingChange -bool true` closes it instead.

| Type | Does |
| --- | --- |
| `dark`, `dark mode on`, `light mode` | Dark mode: the macOS appearance (while the theme follows macOS, its variant switches too) |
| `wifi`, `turn off wifi`, `bt off`, `bluetooth` | Wi-Fi and Bluetooth |
| `dnd`, `do not disturb`, `focus off` | Do Not Disturb (needs the two shortcuts below) |
| `mute`, `unmute`, `volume 30`, `volume up`, `louder` | Sound. Volume steps by 10 |
| `mute mic` | Microphone muted |
| `hidden files`, `show hidden files` | Hidden files in Finder |
| `hide dock`, `dock autohide`, `hide menu bar`, `desktop icons` | Dock and menu bar hiding, desktop icons |
| `caffeinate`, `keep awake` | Keeps the Mac awake until switched off |
| `lock`, `display off` | Locks the screen, or sleeps the display |
| `sleep`, `restart`, `shut down`, `log out` | Ask first: press Return twice. Apps can still ask to save their work |
| `screenshot`, `record screen`, `ocr` | The Capture menu's tools |
| `night shift`, `low power`, `brightness` | Open their pane: macOS has no command for Night Shift, Low Power Mode needs an administrator password, and no brightness tool is installed |

These run `toggle` and `power`, the same commands as the Toggle and System menus, so both always agree. The first time, macOS asks to let Sight control System Events (dark mode, menu bar hiding, log out, restart, shut down) and, for Lock, to allow Accessibility.

Typing "nexus settings", "sight settings" or "iceberg settings" opens that app's Settings window (Cmd+, works in each too).

**Do Not Disturb.** macOS has no command for Focus, so it runs two shortcuts you make once in the Shortcuts app. Make a shortcut named `Do Not Disturb On` with the action Set Focus, Turn Do Not Disturb On, Until Turned Off, and one named `Do Not Disturb Off` with Turn Do Not Disturb Off. Other names work too, set as `GRAND_LINE_DND_ON` and `GRAND_LINE_DND_OFF`. Until they exist, the row says which one is missing.

## How to add things

| To add | Do this |
| --- | --- |
| An app | Add a `cask "name"` line to `Brewfile`, then `bash ~/grand-line/setup.sh --only apps` |
| An ArtCraft app | Add a line to `config/grand-line/artcraft.tsv` (its Team ID, or `-` until the first install prints it), then `--only artcraft` |
| A default app for a file type | Add a line to `config/grand-line/default-apps.tsv`, then `--only default-apps` |
| A shortcut | Add a line to `BINDINGS` in `tools/bindings.py`, run `python3 tools/bindings.py`, then `--only dotfiles` |
| A menu entry | Add a line to `config/grand-line/menu.tsv`. It works at once. A third column `?test` shows it only when the test succeeds, a fourth `✓test` gives it a check mark (helpers in `lib/toggle-state.sh`) |
| A command | Add an executable script to `bin/` with a `# grandline:summary=` line under the first. It is on the PATH at once, and `grandline commands` and Sight list it. Arguments Sight should ask for go in `# grandline:arg1=` lines (up to three), as `{"type":"text"\|"dropdown","placeholder":"…","data":[…],"optional":true}` |
| A theme | Add `config/themes/name.theme` (copy an existing one), its image to `backgrounds/`, and a `Style/` line to `config/grand-line/menu.tsv` with `✓theme_is name`. For a dark and light pair, name the files `name-dark.theme` and `name-light.theme` with `FAMILY=name` in both |
| An app that takes theme colours | Add `config/themed/<file>.tpl` with `{{ KEY }}` placeholders, then have `bin/theme` put the rendered file where the app reads it |
| A one-time change for Macs already set up | Add `migrations/<unix time>-<what>.sh` (`date +%s` gives the time). `update` runs it once on each Mac. Mark it `# grandline:unattended` on a line of its own when it needs no password and asks nothing, so the daily update can run it too. The daily update runs them strictly in order and stops at the first one not marked |
| An R package | Add a line to `config/grand-line/r-packages.txt`, then `--only r-packages` |
| A native helper | Add `tools/name.swift`. Setup builds it into `~/.grand-line/.build` |
| A setup step | Add `steps/NN-name.sh` with a function `step_name`. Steps run in file-name order |

## Your own additions

Keep personal changes in `~/.config/grand-line/`, outside the package, so an update from GitHub never clashes with them.

| File | Does |
| --- | --- |
| `bindings.local.tsv` | Your own Caps Lock shortcuts, in the same four columns as `config/grand-line/keybindings.tsv` (keys, group, description, command). The same keys replace a shipped shortcut, and `unbind<TAB>Caps + X` removes one. Merged into Karabiner's copy by `bash ~/grand-line/setup.sh --only dotfiles`, and shown in Caps + K at once |
| `menu.local.tsv` | Your own menu entries, in the same columns as `menu.tsv`. The same path replaces a shipped entry, and `Path<TAB>-` removes it. Works at once |
| `themed/<file>.tpl` | Your version of a theme template in `config/themed/`, used in its place from the next theme change |
| `hooks/post-update`, `hooks/theme-set` | Scripts that run after every update, and after every theme change (with the theme's name). Several can go in `hooks/<name>.d/`. Setup copies examples there as `*.sample` files, which never run |

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

   Karabiner's keyboard driver cannot load inside a virtual machine, so try the Caps Lock layer on the real Mac.

After setup on any Mac, `bash ~/grand-line/tests/verify-install.sh` checks every app, link, default app and setting.

## Updates

`update` and the daily unattended run both fetch GitHub's copy and check every new commit before anything runs:

1. `git fetch`. If GitHub's history was rewritten (force-pushed), so that the last commit this Mac applied from it is gone, nothing is applied and you are told. That commit is remembered in `~/.local/state/grand-line/upstream-applied`, so a fetch made by anything else first (lazygit, `grandline publish`, `git pull`) cannot hide a rewrite.
2. Each new commit must carry an SSH signature from a key in `~/.config/grand-line/allowed_signers`. That file is outside the package, so a change cannot add its own key. Setup writes it once from your git signing key (`gpg.format ssh` and `user.signingkey`; the checklist shows how to set one up). GPG signatures are not accepted, since gpg would trust any key in your keyring.
3. All signed by a listed key: they are applied by fast-forward. When this Mac has commits of its own not yet on GitHub, `update` replays them on top of GitHub's (signed again as you sign). The unattended run never does: rebasing rewrites your commits and may ask for your signing key, so it applies nothing and tells you once. Unsigned commits: `update` shows them and what they change and asks, and the unattended run stops and posts one notification.
4. Then, in `update`: Homebrew, the setup steps, one-time changes, Neovim plugins, mise and your hook, as before. Nothing is committed or sent to GitHub.

The unattended run (`update --unattended`, launch agent `com.grandline.update`, daily at 3:47 and three minutes after login, at most every 12 hours, niced with low-priority disk access, logged to `~/Library/Logs/grand-line/update.log`) never asks for a password: it runs only the steps that need none (`folders`, `dotfiles`, `native-tools`, `downloads`), the migrations marked `# grandline:unattended` (still oldest first: it stops at the first one not marked, so a later one never runs before one it may rely on), and the theme templates (the tools and apps reload only when the rendered theme changed). It rebuilds only the apps whose sources changed, and only when those sources are exactly GitHub's signed copy (no edits or commits made on this Mac). A package with no GitHub copy is said once and left for an `update` you run. It moves the old copies to the Trash and starts again the ones that were running. When an old copy cannot be moved, it is kept as it is and the new one waits for the next run. Anything that needs the password (Homebrew, ArtCraft, the firewall) waits for an `update` you run. It posts one notification only when something changed or needs you. Turn it off with `update auto off` or from the Update menu.

## What runs in the background

Kept deliberately small: Karabiner-Elements (keyboard), AeroSpace (windows), Maccy (clipboard), Espanso (text shortcuts), Handy (waits for the dictation key), FineTune (per-app volume), Iceberg (music, calendar, reminders and your own widgets in the notch) and Google Drive. Docker, local AI (Ollama) and the VPNs run only while you turn them on. Shortcut commands start, act and exit, and long jobs (video compression, keep-awake, app installs) run on their own so they never block the keyboard. The Downloads sorter is not a running process: macOS starts it at low priority when Downloads changes, and once an hour for the age rules. The daily update runs at a quiet hour and exits. Grand Line Index keeps the shared file index current for Nexus and Sight. The checklist shows how to stop other apps opening at login.

## Security

Every run checks that the firewall (in stealth mode) and automatic security updates are on, reads them back after turning them on (a firewall your organisation manages, or a failed sudo, fails the step with a warning instead of passing), and warns if FileVault is off. Nothing turns off Gatekeeper or System Integrity Protection. Updates from GitHub apply by themselves only when signed by a key you listed (see "Updates"), and nothing is ever sent to GitHub except by `grandline publish`. The package's apps are signed with hardened runtime by a local identity whose key cannot leave this Mac (see "Signing and permissions"). Homebrew's installer runs from a fixed commit checked against its SHA-256. ArtCraft apps are installed only when signed by a developer, intact, notarized by Apple and signed by the Team ID pinned in `config/grand-line/artcraft.tsv` (fourth column; until it is filled in, the Team ID of the first notarized install is remembered and printed, and later releases must match it). A release that fails these checks is a warning, not a failed step, and is not downloaded again until a newer one comes out. The file indexes, Sight's history and the apps' caches are kept out of Time Machine. `capture text` and `capture url` say how many characters they copied, never what, since notifications stay in Notification Center. Maccy's ignore list is checked on every run; it matches apps only, so the web versions of Citrix and Horizon are not covered (use the apps). Universal Clipboard is left as you set it; the checklist shows how to turn it off. sudo is used only by the steps that need it, then closed. The Downloads permission belongs to the sorter's own launcher, not to bash, and the helpers are signed with the local identity under fixed names, so a rebuild keeps that permission. Clipboard history ignores Citrix and Horizon, so patient information is not kept. Neovim plugins are pinned, and the GitHub test runs can only read the repository. Nothing is ever deleted: removed apps, old installers and replaced files go to the Trash, and removing an app keeps its data. Apps that Apple has not notarized keep macOS's first-open check, even when their installer removes it (the apps a run installed are found by the list of apps before and after it and by when macOS recorded each as added, never by modification time, which installers keep from the build). No service listens on the network: Ollama and Docker answer only on this Mac.

## Changing, saving and going back

Everything is in git, so every change can be undone. Changes stay on this Mac until you send them with `grandline publish`, which shows every line, checks them for keys and tokens, and asks first. The `grandline` command (or `gl` for short) looks after it, as `omarchy` does in Omarchy:

| Command | Does |
| --- | --- |
| `grandline history` | The last changes, newest first |
| `grandline undo` | Undoes the last change and applies the result (run it twice to undo the undo) |
| `grandline save "before notch work"` | Marks this moment as a version worth keeping |
| `grandline versions`, `grandline restore` | Lists saved versions, or goes back to one (itself undoable) |
| `grandline try start notch`, `grandline try keep`, `grandline try drop` | Tries a change on the side, then keeps or discards it, back on the branch it started from |
| `grandline publish` | Sends your saved changes to GitHub, after showing them and asking. Edits to files the package tracks are saved first; new files are never added by themselves (`git add` one on purpose) |
| `grandline check` | Checks every app, link and setting |
| `grandline edit` | Opens the package in Neovim |

Edits made by hand, by an editor or tool in `~/grand-line`, or from the Install and Remove menus stay as edits until a `grandline` command saves them. Every change sent to GitHub runs the quick checks there, including the security checks (`tests/security-checks.sh`: keys and tokens, actions pinned to a commit, nothing downloaded piped into a shell, the apps' entitlements, and hardened runtime on every app built), and the full install test runs every Monday.

## Running setup again

Setup only fills in what is missing, so it is safe to run any time, and `update` runs it for you. Settings you change yourself are kept: system settings, the Dock and the checklist are applied on the first run only. To apply one again, name its step, for example `bash ~/grand-line/setup.sh --only macos-defaults`.

## Layout

```
setup.sh            entry point (runs steps/ in order)
Brewfile            apps and tools
steps/              one file per setup step
bin/                commands behind the menus and shortcuts
lib/                shared helpers and paths
config/             aerospace, karabiner, ghostty, tmux, zsh, starship, nvim, git,
                    espanso, themes, themed (templates filled in by the theme),
                    and grand-line (menus, rules, data files, hook samples)
backgrounds/        theme wallpapers
migrations/         one-time changes for Macs already set up (bin/migrate)
tools/              shortcut generator, app icon drawer and native helpers (Swift)
DESIGN.md           the type, colour and layout rules every part follows
tests/              checks, dry run, VM rehearsal, post-install verification
.github/workflows/  the GitHub test runs
publish.sh          first upload of this package to GitHub
```

## Credits

Much of how this package works is adapted from [Omarchy](https://github.com/basecamp/omarchy) by David Heinemeier Hansson and contributors, under the MIT License. It is rebuilt here for macOS, in bash 3.2, with Apple's fonts and colours. The pieces and the Omarchy files each is based on:

| Here | Based on, in Omarchy |
| --- | --- |
| Caps Lock layer (Super key layout) and the Caps + K shortcut list | `default/hypr/bindings/tiling.lua`, `default/hypr/bindings/utilities.lua`, `bin/omarchy-menu-keybindings` |
| The menu (`bin/menu`, `menu.tsv`) and its Toggle and Style groups | `bin/omarchy-menu` |
| Toggle states read from flag files (`lib/toggle-state.sh`) | `bin/omarchy-state`, `bin/omarchy-toggle-*` |
| Theme files, templates and the swap of the rendered folder (`bin/theme`, `lib/templates.sh`, `config/themed/`) | `bin/omarchy-theme-set`, `bin/omarchy-theme-set-templates`, `default/themed/*.tpl` |
| tmux, btop, lazygit and Claude Code colours | `default/themed/btop.theme.tpl`, `default/themed/claude.json.tpl`, `bin/omarchy-theme-set-tmux`, `bin/omarchy-theme-set-claude` |
| Next background | `bin/omarchy-theme-bg-next` |
| Migrations (`bin/migrate`, `migrations/`) | `bin/omarchy-migrate`, `bin/omarchy-dev-add-migration`, `migrations/` |
| Hooks (`bin/hook`, hook samples) | `bin/omarchy-hook`, `config/omarchy/hooks/` |
| The update run (lock, staying awake, restart note) | `bin/omarchy-update`, `bin/omarchy-update-lock`, `bin/omarchy-update-stay-awake`, `bin/omarchy-update-restart` |
| A window that waits for a key when a job ends (`bin/in-window`) | `bin/omarchy-show-done` |
| Focus an open window before opening another (`bin/focus-or-open`, `bin/webapp`) | `bin/omarchy-launch-or-focus`, `bin/omarchy-launch-or-focus-webapp`, `bin/omarchy-launch-webapp` |
| Install and Remove menus (`bin/app`) | `bin/omarchy-pkg-install`, `bin/omarchy-pkg-remove` |
| The `grandline` command and `# grandline:summary=` lines | `bin/omarchy` and its `# omarchy:summary=` lines |
| Shell aliases and the `ga`, `gd` worktree functions | `default/bash/aliases`, `default/bash/fns/worktrees` |
| Git settings | `config/git/config` |
