# Iceberg

The notch app of Grand Line. Hover over the MacBook's camera notch and it opens into a panel with what you chose to show: the date, what is playing, today's calendar, reminders due today, the battery, a shelf for files, and small widgets you add. Move the pointer away and it closes back into the notch. A new install shows the date, Now Playing and Today; turn the rest on in Settings.

- **Now Playing** for any player macOS knows about (Spotify, Music, browsers), with artwork and previous, play or pause, next. While music plays, the closed notch grows a small wing each side, one notch height wide: the cover on the left (a rounded square) and playing bars on the right, tinted with the cover's strongest colour (the theme's accent for a grey cover). The bars rest low for a short while after a pause, then the notch goes back to its own width. With Reduce Motion the bars stay still and nothing springs.
- **Today**: what is left of today in every calendar macOS Calendar has. Google calendars appear once they are added in System Settings, Internet Accounts. Hidden while Calendars access is turned down; Settings says how to allow it.
- **Reminders** due today or overdue. Tick one to complete it. Hidden while Reminders access is turned down.
- **Date** and **Battery** in the top band.
- **Shelf**: drag files onto the notch (it opens as a file comes near) to park them, then drag them out again to any app. The shelf keeps a bookmark to each file, never a copy, so it follows a file that is renamed or moved, and it is the same after a restart (`~/.local/state/grand-line/iceberg/shelf.json`). Taking a file off the shelf, or clearing it, never touches the file, and dragging one out gives the other app a copy (Finder copies rather than moves it). Double-click a file to open it; its menu (right-click, or the … button) has Open, Show in Finder and the quick actions.
- **Quick actions** on shelved files (`shelf_quick_actions`): Compress to Zip (as Finder's Compress does, with `ditto`), Make a Smaller Copy of an image (JPEG and HEIC stay in their format at 70% quality; other images become JPEG), Convert an image to PNG, JPEG, HEIC or TIFF (`sips`), and Remove Background (Vision, on this Mac, as a PNG with a transparent background). Each makes a new file beside the original, named so it never clashes (`photo-compressed.jpg`, then `photo-compressed 2.jpg`), and puts it on the shelf too. No action overwrites, moves or deletes the original.
- **Drop basket** (`drag_basket`): while dragging a file, shake the pointer left and right and a small basket appears under it. What you drop in goes on the shelf and stays listed in the basket, from where you can drag it out again. The basket goes when the drag ends with nothing dropped, on a click outside it, or with its close button.
- **HUDs in the notch**: the volume, the display brightness, the battery (power connected or removed, and falling to 20% and 10%) and headphones connecting (AirPods and other Bluetooth headphones, with their battery when they report it) show beside the closed notch for a moment, in wings like the music's. Each is turned on in Settings and starts off. Volume and battery need no permission. Brightness needs Accessibility (to see the brightness keys), headphones need Bluetooth access (macOS asks the first time). With `hud_replace_system` (Accessibility) Iceberg changes the volume and brightness itself, on macOS's own steps, so macOS's HUD does not show; without it macOS shows its own too.
- **Your widgets**: a title, an SF Symbol and a shell command, in a small file. No code.

It follows the theme (`theme pick`) as it changes (and, with Follow macOS chosen in Nexus or Sight Settings, Appearance, the dark or light variant macOS shows), uses SF Pro and SF Symbols, and takes every colour from the theme file, as `DESIGN.md` asks: the open panel, its chips and the lines between its columns (`NOTCH_PANEL`, `NOTCH_CARD`, `NOTCH_LINE`, which fall back to the theme's own surfaces). The closed notch, and the part of the open panel under the camera, are black so they match the camera housing. Its app icon, an iceberg, is drawn in the theme's colours too. It shows on the built-in display. With `external_displays = "pill"` other displays get a small pill at the top centre, and with the lid closed the main display gets one. On a display without a notch, `no_notch_style` draws that shape as an island (the pill, flat on the top edge and round below, the default) or as a notch (a black tab with the camera notch's corners). While closed, only the notch itself (or the pill) takes the pointer: the wings, and the menu bar and status items either side, get their clicks as if Iceberg were not there. In a full-screen app, whose menu bar is hidden, the pill is not drawn; resting the pointer at the top centre still opens the panel.

Iceberg's menu bar item (and a right-click on the panel) has Settings, Reload, the widgets folder, the log and Quit. Control + Option + Command + N opens or closes the panel from any app (`toggle_shortcut`; the Caps Lock layer's Caps + Control + Option + N does the same through Karabiner). `open -g iceberg://toggle` does it from a script (also `open`, `close`, `reload`, `settings` and `trigger/NAME`), as does the `iceberg` command below. Command + Comma opens Settings from the menu bar item's menu or while the Settings window is in front; the panel itself never takes the keyboard, so it does not see the shortcut. The open panel closes when the pointer leaves it, on a click anywhere outside it, and on Escape (held only while it is open). Opened from the keyboard, a script or the menu bar item while the pointer is elsewhere, it stays until the pointer moves on.

Saving iceberg.toml, a widget file or a script beside it applies at once, with no restart (hot reload).

## Settings window

Lists every built-in item and every widget file with a switch, a line on what it is, and arrows (or drag) to set the order. Below are:

- buttons for the widgets folder, iceberg.toml and the log;
- **General**: open on hover or click, the hover delay, the keyboard shortcut (click it and press new keys; Reset and Turn off beside it), which displays, the island or notch look on displays without a notch, artwork beside the closed notch, the menu bar item, open at login;
- **Shelf and drag**: quick actions on shelved files, and the drop basket (the Shelf itself is turned on in the list above);
- **HUDs in the notch**: volume, brightness, battery, headphones, and hiding macOS's own HUD, each with what it needs; when Accessibility or Bluetooth is turned down, a line says so with a button to the right pane of System Settings;
- **Now Playing**: where what is playing comes from (see below), with Check again;
- **Diagnostics**: for each widget in the panel, how many times it ran, its average and last run time, what it last printed and its last error, whether it is paused or waiting after failures, and Run now;
- **Problems**: each file Iceberg could not fully read, as `file:line`, what is wrong, and the fix in plain words. The panel itself never shows problems.

Every change applies at once and is written to `iceberg.toml`: only the line for that setting changes, so your comments and the rest of the file stay as you wrote them. A file with a mistake in it is left alone, and the window says so.

## Adding a widget

Put a file in `~/.config/grand-line/iceberg/widgets/`. It appears in Settings as soon as you save it; turn it on there (or add its file name to `panel` in iceberg.toml) and it shows in the panel.

```toml
# ~/.config/grand-line/iceberg/widgets/disk.toml
title = "Disk"
icon = "internaldrive"                      # any SF Symbol name
command = "df -h / | awk 'NR==2 {print $4}'"
refresh = "5m"                              # seconds, "30s", "5m", "1h", or "on open"
click = "open -a 'Disk Utility'"            # optional
```

### What a command prints

The contract is Waybar's custom module, so its scripts work unchanged. The command prints one line of text, or one line of JSON:

```sh
echo '{"text": "3 new", "tooltip": "From: …", "class": "warning", "percentage": 60, "icon": "tray.full"}'
```

| Field | Meaning |
| --- | --- |
| `text` | What the chip shows (a number is shown as written) |
| `tooltip` | Shown when the pointer rests on the chip |
| `class` | One name or a list. A name that is a theme colour (`warning`, `critical`, `red` …) colours the text |
| `percentage` | 0 to 100, drawn as a thin bar along the chip |
| `alt` | A second word for the state; kept for Waybar scripts |
| `icon` | Iceberg's own: an SF Symbol name for this run |
| `color` | Iceberg's own: a theme colour name, which wins over `class` |

Plain text shows its first line. A bare setup note such as `Set LOCATION` shows as "Needs setup", with the note in the tooltip. Colour codes are removed. Colours are theme names, so they follow the theme: `foreground`, `muted`, `highlight`, `accent`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`.

### Three kinds of widget

- **Interval** (the default): runs on its `refresh` schedule while the panel is open, and as it opens when its value is older than that.
- **Signal** (`signal = true`): runs when asked, with `iceberg trigger NAME` from any script or hook (or `open -g iceberg://trigger/NAME`), and once as the panel opens. Use it for things that change on an event, such as mail arriving or a VPN connecting, instead of polling. With `refresh` set as well it also runs on that schedule.
- **Stream** (`stream = true`): the command keeps running and prints one line per update (Waybar's continuous mode). Iceberg shows each new line, at most ten a second; it stops the script when the panel closes (unless `updates = "always"`) and starts it again, waiting longer each time, if it ends by itself. Print with line buffering (`stdbuf -oL`, `fflush()` in awk, `python3 -u`); a buffered script looks frozen.

```toml
# widgets/vpn.toml: refreshed by a hook calling `iceberg trigger vpn`
title = "VPN"
icon = "lock.shield"
command = "./vpn-status.sh"
signal = true
```

```toml
# widgets/log.toml: the newest line of a log, while the panel is open
title = "Build"
icon = "hammer"
command = "tail -n 1 -F ~/build.log"
stream = true
```

### Keys

| Key | Meaning |
| --- | --- |
| `title` | The label. Defaults to the file name |
| `icon` | An SF Symbol name |
| `command` | Run with `/bin/sh` in the widgets folder, so `./script.sh` works (also `exec` or `script`) |
| `refresh` | How often it runs while the panel is open (5 seconds at the fastest), or `"on open"` (the default) |
| `signal` | `true`: runs when `iceberg trigger NAME` asks, and as the panel opens |
| `stream` | `true`: the command keeps running and prints a line per update |
| `updates` | `"when_shown"` (the default): only while the panel is open, plus once as it opens. `"always"`: also while it is closed, so the value is current when it opens |
| `always` | `true`: keeps running during Low Power Mode and around sleep |
| `click` | Run when the widget is clicked, then the widget refreshes (also `on-click`) |
| `timeout` | Seconds before a stuck command and everything it started are stopped (default 10, 1 to 120; not for streams) |
| `order` | Only for files from before `panel`: the position, lowest first |
| `enabled` | `false` keeps it off, whatever Settings says |

The same keys work in a `.json` file. Commands get `GRAND_LINE_ICEBERG_WIDGET`, `GRAND_LINE_ICEBERG_WIDGETS_DIR`, `GRAND_LINE_ICEBERG_THEME` and `GRAND_LINE_ICEBERG_MODE`, and a PATH with Homebrew and `~/.grand-line/bin`.

A file with a mistake is named in Settings, Problems, with its line and how to fix it, and in `~/Library/Logs/grand-line/iceberg.log`. A widget that was working keeps its last good version until the file is fixed; the other widgets keep working. Unknown keys are warned about, with the nearest known key when there is one.

Two examples are copied into the folder the first time Iceberg runs (from `Resources/Iceberg/examples/widgets/`). They start turned off:

- **Weather** from Open-Meteo, for `LOCATION="lat lon Place"` in `~/.config/grand-line/personal.env`.
- **Services**: whether Docker and local AI are running, from the package's toggles. Click it for the Toggle menu.

## The iceberg command

```
iceberg trigger NAME...   run widgets now (by file name, without .toml); a stream widget restarts
iceberg toggle | open | close | reload | settings
iceberg schema            where iceberg.schema.json is, for editors
```

A trigger reaches a running Iceberg as a distributed notification, so nothing comes forward. While the panel is closed the widget runs as the panel next opens (at once with `updates = "always"`), and during Low Power Mode once it ends (at once with `always = true`). When Iceberg is not running, `iceberg trigger` starts it with `iceberg://trigger/NAME`.

## Settings

All optional, in `~/.config/grand-line/iceberg/iceberg.toml`:

```toml
external_displays = "none"   # "pill" adds a pill to every display without a notch
open_on = "hover"            # or "click"
hover_delay = 0.12           # seconds, 0 to 3
close_delay = 0.35           # seconds, 0 to 3
toggle_shortcut = "ctrl+option+cmd+n"   # "" for none
live_activity = true         # artwork beside the closed notch while music plays
launch_at_login = true
menu_bar_icon = true         # Iceberg's item in the menu bar
max_concurrent = 4           # widget commands at once (and streams), 1 to 16
panel = ["date", "now-playing", "today"]   # what shows, in order: built-in items and widget file names
no_notch_style = "island"    # displays without a notch: "island" (a pill) or "notch" (a tab like the notch)
shelf_quick_actions = true   # zip, smaller copy, convert, remove background on shelved files
drag_basket = false          # shake while dragging a file to show a drop basket
hud_volume = false           # HUDs in the notch, each off until turned on
hud_brightness = false       # needs Accessibility
hud_battery = false
hud_bluetooth = false        # headphones connecting; needs Bluetooth access
hud_replace_system = false   # Iceberg takes the volume and brightness keys, so macOS's HUD does not show (Accessibility)
```

`panel` is the one list of what the panel shows. The built-in names are `date`, `now-playing`, `today`, `reminders`, `battery` and `shelf`; anything else is a widget's file name without `.toml`. Without `panel`, a file from before it keeps its `builtin = [...]` list (plus the date), and a new install shows `date`, `now-playing` and `today`. The Settings window writes `panel` and then drops the old `builtin` line.

`toggle_shortcut` is modifier names and a key joined with `+`: `ctrl`, `option`, `cmd`, `shift` (at least one besides `shift`), then a letter, digit, `space`, `return`, `escape`, an arrow, or `f1` to `f15`. It needs no Accessibility permission. If another app holds the same keys, Settings says so.

### Schema

`Resources/Iceberg/iceberg.schema.json` (also inside the app, and printed by `iceberg schema`) is a JSON Schema for iceberg.toml, with widget files under `#/$defs/widget`. It gives every key's type, allowed values, range, default and a description. Iceberg checks both kinds of file against the same rules on every load (`ConfigSchema` in IcebergKit; a test keeps the two the same), so an editor that reads JSON Schema for TOML (Taplo, or VS Code with Even Better TOML) flags the same mistakes as you type. Point it at the file with a first line such as this, with your home folder in place of `/Users/me`:

```toml
#:schema /Users/me/.grand-line/apps/iceberg/Resources/Iceberg/iceberg.schema.json
```

What the checks do with a mistake: a wrong type, or a value outside its range or list, is named with its line and a fix, and the default is used (`timeout` and `max_concurrent` are brought into range instead); an unknown key is warned about and ignored; a widget file without `command`, or with a syntax error, is not loaded (a widget that was working keeps its last good version). iceberg.toml with a syntax error, or caught half-saved (empty or missing for a moment), keeps the settings in use until it is fixed, and a key turned down by the checks keeps its value from before (the defaults stand in only when Iceberg starts with a broken file); Login Items change only when `launch_at_login` itself changes.

## Now Playing

Since macOS 15.4 only Apple's own programs may read what is playing, so Iceberg uses mediaremote-adapter, which runs through Apple's `/usr/bin/perl`. A macOS update can break that, so Iceberg checks it as it starts and every five minutes (the adapter's own `test`). When the check fails, or the adapter keeps stopping, Iceberg asks Music and Spotify directly with AppleScript (only when they are running, so it never opens them) and follows their change notices: Music and Spotify keep working, without artwork; other players do not show. The first time, macOS asks to let Iceberg control Music or Spotify. Settings, Now Playing says which of the two is in use, and when neither works, why and what to do (usually allowing Iceberg in Privacy & Security, Automation). A later check that passes switches back by itself, or click Check again.

## Resource use

Nothing polls. Now Playing, the calendars, reminders and the battery are pushed by macOS. Widget commands:

- run only while the panel is open, plus once as it opens (`updates = "when_shown"`, the default); `updates = "always"` lets one keep running while it is closed;
- run at most `max_concurrent` at a time (4), each with a time limit (`timeout`) after which it and everything it started (its process group) are stopped. When a command ends by itself, anything it left running in the background (`helper &`) is stopped too, so refreshes cannot pile up stray processes; a helper meant to keep running belongs in a stream widget, or is started with `open` or launchd;
- do not run during sleep (from macOS's will-sleep notice to the wake) or in Low Power Mode, unless the widget says `always = true`; what was missed runs once afterwards;
- wait longer after repeated failures: one failure changes nothing, then 10 s, 20 s, 40 s … up to 30 minutes on top of the schedule, and one success clears it (a click or Run now runs it at once).

One timer is set for the next widget due, and none while nothing is due.

The shelf, the basket and the HUDs add nothing while idle. The shelf and the basket listen to the left mouse button (down, dragged, up) only while one of them is turned on; a drag that carries no files is settled after a few events, and only a file drag feeds the shake detector. The HUDs are pushed by macOS: a CoreAudio listener for the volume, IOKit's power notice for the battery, IOBluetooth's connect notice for headphones, and a keyboard event tap that hears only the volume, mute and brightness keys (only while a HUD that needs it is on). A HUD's one-shot timer runs only while it shows. The shelf reads its file at start and writes it when it changes; quick actions run only when chosen. The playback bar redraws once a second, only while the panel is open and something plays. Settings, Diagnostics shows what each widget costs.

## Build and test

Setup builds and installs Iceberg with the package's other apps (`apps.tsv`, `lib/native-apps.sh`). To build it by hand on a Mac with Xcode:

```
cd apps/iceberg
bash build.sh            # build/Iceberg.app, signed for this Mac
bash build.sh --open     # the same, then opened
bash build.sh --test     # or: swift test
```

The tests cover widget and settings parsing (TOML and JSON), the schema checks and that `iceberg.schema.json` and this README match them, what shows and in what order, writing iceberg.toml without losing comments, the cover tint, the widget output contract (Waybar's fields), the three widget kinds, the command runner and stream runner (time limits, killed process groups, capped and thinned output), refresh scheduling with backoff, sleep and Low Power Mode, hot reload (a broken save keeps the last good widget, saved scripts re-run their widgets), the diagnostics, the keyboard shortcut, the Now Playing stream, its health check and AppleScript fallback, theme parsing (every shipped theme), panel sizes and placement, battery and agenda logic, the shelf (its list, its file, bookmarks that follow a renamed file, quick-action names that never clash and commands that write only a new file), the shake and drag detectors, what each HUD shows and when (volume, brightness, battery, headphones, the media keys and their steps), and stress cases: 50 widgets, hung commands, malformed and binary files, random input.

The user journeys (`tests/journeys`, on a Mac) also drive a signal widget through `bin/iceberg trigger` and `iceberg://trigger/NAME`, and save widget files and iceberg.toml while the panel is open.

## Layout

```
Package.swift
apps.tsv                     how setup builds and names the app
Info/Iceberg.plist           extra Info.plist keys (permissions, URL scheme)
Resources/Iceberg/           copied into the app: adapter script, iceberg.schema.json, example widgets, licence, AppIcon.icns
Sources/IcebergKit/          everything testable: Config (and its schema), Commands, Scheduling, Diagnostics, Theme, Layout, Media, Agenda, Battery, Panel, Shelf (the list, its file, output names, quick-action commands, the shake and drag detectors), HUD (what each HUD shows and when)
Sources/Iceberg/Settings/    the Settings window
Sources/Iceberg/App/         start-up, displays, URL commands
Sources/Iceberg/Notch/       the panel window, its shape, open and close, HUDs beside the notch
Sources/Iceberg/Shelf/       the shelf's files, dragging in and out, the drop basket, background removal
Sources/Iceberg/HUD/         the HUDs' sources (CoreAudio, IOKit, IOBluetooth, the key tap) and their view
Sources/Iceberg/Widgets/     one folder per built-in widget, plus User for your widgets
Vendor/mediaremote-adapter/  the Now Playing helper (BSD-3), unchanged
Tests/IcebergKitTests/
```

A new built-in widget is one file in `Sources/Iceberg/Widgets/<Name>/` conforming to `NotchWidget`, one line in `WidgetRegistry.swift`, and an entry in `PanelCatalog.builtins` (its title and description for Settings).

The icon code is shared with Nexus and Sight in `apps/icons`.

## Credits and licence

Iceberg is MIT licensed (`LICENSE`). It was written fresh, using techniques learned from reading these projects:

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT): how to measure the notch from the menu bar areas either side of it, and the notch outline, which `NotchShape.swift` adapts with credit.
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3): the Now Playing workaround for macOS 15.4 and later, included unchanged in `Vendor/`.
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) and [Atoll](https://github.com/Ebullioscopic/Atoll) (GPL-3.0): how a notch panel window is set up and how media commands are sent. Read as references only. No code is copied, so Iceberg is not GPL.
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) (GPL-3.0): script-driven items with an update interval, `updates = when_shown`, no runs during sleep, and a time limit on scripts. Read as a reference only.
- Droppy, a notch shelf app for macOS: the ideas of a file shelf in the notch, a basket summoned by shaking the pointer during a drag, quick actions on shelved files, and HUDs in the notch. Read for ideas only; no code is copied.
- [Waybar](https://github.com/Alexays/Waybar) (MIT): the custom module's script contract (one JSON line with text, alt, tooltip, class and percentage; interval, signal and continuous modes), which Iceberg's widgets follow so its scripts carry over. No code is copied.
