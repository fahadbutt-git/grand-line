# Den Den

The notch app of Grand Line. Hover over the MacBook's camera notch and it opens into a panel with what is playing, today's calendar, reminders due today, the battery, and any small widgets you add. Move the pointer away and it closes back into the notch.

- **Now Playing** for any player macOS knows about (Spotify, Music, browsers), with artwork and previous, play or pause, next. While music plays, the closed notch shows the artwork beside the camera.
- **Today**: what is left of today in every calendar macOS Calendar has. Google calendars appear once they are added in System Settings, Internet Accounts.
- **Reminders** due today or overdue. Tick one to complete it.
- **Battery** in the top band.
- **Your widgets**: a title, an SF Symbol and a shell command, in a small file. No code.

It follows the theme (`theme pick`) as it changes, uses SF Pro and SF Symbols, and takes every colour from the theme file, as `DESIGN.md` asks. The closed notch is black so it matches the camera housing. It shows on the built-in display. With `external_displays = "pill"` other displays get a small pill at the top centre, and with the lid closed the main display gets one.

Right-click the panel for Reload, the widgets folder, the log and Quit. `open -g denden://toggle` opens or closes it from a shortcut (also `open`, `close` and `reload`).

## Adding a widget

Put a file in `~/.config/grand-line/denden/widgets/`. It shows up as soon as you save it.

```toml
# ~/.config/grand-line/denden/widgets/disk.toml
title = "Disk"
icon = "internaldrive"                      # any SF Symbol name
command = "df -h / | awk 'NR==2 {print $4}'"
refresh = "5m"                              # seconds, "30s", "5m", "1h", or "on open"
click = "open -a 'Disk Utility'"            # optional
```

The command's first line of output is shown. To set the symbol or colour from the command, print JSON instead:

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
| `order` | Position, lowest first. Ties go by file name |
| `enabled` | `false` hides it |

The same keys work in a `.json` file. Colours are theme names, so they follow the theme: `foreground`, `muted`, `highlight`, `accent`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`. Commands get `GRAND_LINE_DENDEN_WIDGET`, `GRAND_LINE_DENDEN_WIDGETS_DIR`, `GRAND_LINE_DENDEN_THEME` and `GRAND_LINE_DENDEN_MODE`, and a PATH with Homebrew and `~/.grand-line/bin`.

A file with a mistake is skipped and named at the bottom of the panel and in `~/Library/Logs/grand-line/denden.log`, with its line number. The other widgets keep working.

Two examples are copied into the folder the first time Den Den runs (from `Resources/DenDen/examples/widgets/`):

- **Weather** from Open-Meteo, for `LOCATION="lat lon Place"` in `~/.config/grand-line/personal.env`.
- **Services**: whether Docker and local AI are running, from the package's toggles. Click it for the Toggle menu.

## Settings

All optional, in `~/.config/grand-line/denden/denden.toml`:

```toml
external_displays = "none"   # "pill" adds a pill to every display without a notch
open_on = "hover"            # or "click"
hover_delay = 0.12           # seconds
close_delay = 0.35
live_activity = true         # artwork beside the closed notch while music plays
launch_at_login = true
builtin = ["now-playing", "today", "reminders", "battery"]   # which, and in what order
```

## Resource use

Nothing polls. Now Playing, the calendars, reminders and the battery are pushed by macOS. Widget commands run only while the panel is open (or as it opens), four at a time at most, each with a time limit after which it and anything it started are stopped. One timer is set for the next widget due, and none while the panel is closed. The playback bar redraws once a second, only while the panel is open and something plays.

## Build and test

Setup builds and installs Den Den with the package's other apps (`apps.tsv`, `lib/native-apps.sh`). To build it by hand on a Mac with Xcode:

```
cd apps/denden
bash build.sh            # build/Den Den.app, signed for this Mac
bash build.sh --open     # the same, then opened
bash build.sh --test     # or: swift test
```

The tests cover widget and settings parsing (TOML and JSON), command output parsing, the command runner (time limits, killed process groups, capped output), refresh scheduling, theme parsing (every shipped theme), panel sizes and placement, the Now Playing stream, battery and agenda logic, and stress cases: 50 widgets, hung commands, malformed and binary files, random input.

## Layout

```
Package.swift
apps.tsv                     how setup builds and names the app
Info/DenDen.plist            extra Info.plist keys (permissions, URL scheme)
Resources/DenDen/            copied into the app: adapter script, example widgets, licence
Sources/DenDenKit/           everything testable: Config, Commands, Scheduling, Theme, Layout, Media, Agenda, Battery
Sources/DenDen/App/          start-up, displays, URL commands
Sources/DenDen/Notch/        the panel window, its shape, open and close
Sources/DenDen/Widgets/      one folder per built-in widget, plus User for your widgets
Vendor/mediaremote-adapter/  the Now Playing helper (BSD-3), unchanged
Tests/DenDenKitTests/
```

A new built-in widget is one file in `Sources/DenDen/Widgets/<Name>/` conforming to `NotchWidget`, one line in `WidgetRegistry.swift`, and its name in `DenDenSettings.builtinWidgets`.

## Credits and licence

Den Den is MIT licensed (`LICENSE`). It was written fresh, using techniques learned from reading these projects:

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT): how to measure the notch from the menu bar areas either side of it, and the notch outline, which `NotchShape.swift` adapts with credit.
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3): the Now Playing workaround for macOS 15.4 and later, included unchanged in `Vendor/`.
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) and [Atoll](https://github.com/Ebullioscopic/Atoll) (GPL-3.0): how a notch panel window is set up and how media commands are sent. Read as references only. No code is copied, so Den Den is not GPL.
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) (GPL-3.0): script-driven items with an update interval and a time limit on scripts. Read as a reference only.
