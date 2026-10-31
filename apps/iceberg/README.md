# Iceberg

The notch app of Grand Line. Hover over the MacBook's camera notch and it opens into a panel with what you chose to show: the date, what is playing, today's calendar, reminders due today, the battery, and small widgets you add. Move the pointer away and it closes back into the notch. A new install shows the date, Now Playing and Today; turn the rest on in Settings.

- **Now Playing** for any player macOS knows about (Spotify, Music, browsers), with artwork and previous, play or pause, next. While music plays, the closed notch grows a small wing each side, one notch height wide: the cover on the left (a rounded square) and playing bars on the right, tinted with the cover's strongest colour (the theme's accent for a grey cover). The bars rest low for a short while after a pause, then the notch goes back to its own width. With Reduce Motion the bars stay still and nothing springs.
- **Today**: what is left of today in every calendar macOS Calendar has. Google calendars appear once they are added in System Settings, Internet Accounts. Hidden while Calendars access is turned down; Settings says how to allow it.
- **Reminders** due today or overdue. Tick one to complete it. Hidden while Reminders access is turned down.
- **Date** and **Battery** in the top band.
- **Your widgets**: a title, an SF Symbol and a shell command, in a small file. No code.

It follows the theme (`theme pick`) as it changes, uses SF Pro and SF Symbols, and takes every colour from the theme file, as `DESIGN.md` asks: the open panel, its chips and the lines between its columns (`NOTCH_PANEL`, `NOTCH_CARD`, `NOTCH_LINE`, which fall back to the theme's own surfaces). The closed notch, and the part of the open panel under the camera, are black so they match the camera housing. Its app icon, an iceberg, is drawn in the theme's colours too. It shows on the built-in display. With `external_displays = "pill"` other displays get a small pill at the top centre, and with the lid closed the main display gets one.

Iceberg's menu bar item (and a right-click on the panel) has Settings, Reload, the widgets folder, the log and Quit. `open -g iceberg://toggle` opens or closes it from a shortcut (also `open`, `close`, `reload` and `settings`). Command + Comma opens Settings from the menu bar item's menu or while the Settings window is in front; the panel itself never takes the keyboard, so it does not see the shortcut.

## Settings window

Lists every built-in item and every widget file with a switch, a line on what it is, and arrows (or drag) to set the order. Below are buttons for the widgets folder, iceberg.toml and the log, the general options (open on hover or click, which displays, artwork beside the closed notch, the menu bar item, open at login), and a Problems list naming any file Iceberg could not fully read. The panel itself never shows problems.

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

The command's first line of output is shown. A bare setup note such as `Set LOCATION` shows as "Needs setup", with the note in the tooltip. To set the symbol or colour from the command, print JSON instead:

```sh
echo '{"text": "3 new", "icon": "tray.full", "color": "highlight"}'
```

| Key | Meaning |
| --- | --- |
| `title` | The label. Defaults to the file name |
| `icon` | An SF Symbol name |
| `command` | Run with `/bin/sh` in the widgets folder, so `./script.sh` works |
| `refresh` | How often it runs while the panel is open (5 seconds at the fastest), or `"on open"` (the default) |
| `click` | Run when the widget is clicked, then the widget refreshes |
| `timeout` | Seconds before a stuck command is stopped (default 10, 1 to 120) |
| `order` | Only for files from before `panel`: the position, lowest first |
| `enabled` | `false` keeps it off, whatever Settings says |

The same keys work in a `.json` file. Colours are theme names, so they follow the theme: `foreground`, `muted`, `highlight`, `accent`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`. Commands get `GRAND_LINE_ICEBERG_WIDGET`, `GRAND_LINE_ICEBERG_WIDGETS_DIR`, `GRAND_LINE_ICEBERG_THEME` and `GRAND_LINE_ICEBERG_MODE`, and a PATH with Homebrew and `~/.grand-line/bin`.

A file with a mistake is skipped and named at the bottom of the panel and in `~/Library/Logs/grand-line/iceberg.log`, with its line number. The other widgets keep working.

Two examples are copied into the folder the first time Iceberg runs (from `Resources/Iceberg/examples/widgets/`). They start turned off:

- **Weather** from Open-Meteo, for `LOCATION="lat lon Place"` in `~/.config/grand-line/personal.env`.
- **Services**: whether Docker and local AI are running, from the package's toggles. Click it for the Toggle menu.

## Settings

All optional, in `~/.config/grand-line/iceberg/iceberg.toml`:

```toml
external_displays = "none"   # "pill" adds a pill to every display without a notch
open_on = "hover"            # or "click"
hover_delay = 0.12           # seconds
close_delay = 0.35
live_activity = true         # artwork beside the closed notch while music plays
launch_at_login = true
menu_bar_icon = true         # Iceberg's item in the menu bar
panel = ["date", "now-playing", "today"]   # what shows, in order: built-in items and widget file names
```

`panel` is the one list of what the panel shows. The built-in names are `date`, `now-playing`, `today`, `reminders` and `battery`; anything else is a widget's file name without `.toml`. Without `panel`, a file from before it keeps its `builtin = [...]` list (plus the date), and a new install shows `date`, `now-playing` and `today`. The Settings window writes `panel` and then drops the old `builtin` line.

## Resource use

Nothing polls. Now Playing, the calendars, reminders and the battery are pushed by macOS. Widget commands run only while the panel is open (or as it opens), four at a time at most, each with a time limit after which it and anything it started are stopped. One timer is set for the next widget due, and none while the panel is closed. The playback bar redraws once a second, only while the panel is open and something plays.

## Build and test

Setup builds and installs Iceberg with the package's other apps (`apps.tsv`, `lib/native-apps.sh`). To build it by hand on a Mac with Xcode:

```
cd apps/iceberg
bash build.sh            # build/Iceberg.app, signed for this Mac
bash build.sh --open     # the same, then opened
bash build.sh --test     # or: swift test
```

The tests cover widget and settings parsing (TOML and JSON), what shows and in what order, writing iceberg.toml without losing comments, the cover tint, command output parsing, the command runner (time limits, killed process groups, capped output), refresh scheduling, theme parsing (every shipped theme), panel sizes and placement, the Now Playing stream, battery and agenda logic, and stress cases: 50 widgets, hung commands, malformed and binary files, random input.

## Layout

```
Package.swift
apps.tsv                     how setup builds and names the app
Info/Iceberg.plist           extra Info.plist keys (permissions, URL scheme)
Resources/Iceberg/           copied into the app: adapter script, example widgets, licence, AppIcon.icns
Sources/IcebergKit/          everything testable: Config, Commands, Scheduling, Theme, Layout, Media, Agenda, Battery, Panel
Sources/Iceberg/Settings/    the Settings window
Sources/Iceberg/App/         start-up, displays, URL commands
Sources/Iceberg/Notch/       the panel window, its shape, open and close
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
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) (GPL-3.0): script-driven items with an update interval and a time limit on scripts. Read as a reference only.
