#!/usr/bin/env python3
"""The Super key (Right Command): every shortcut is defined once, in BINDINGS below.

To add or change a shortcut, edit BINDINGS, then run:
    python3 tools/bindings.py

That writes three things, which must not be edited by hand:
  config/karabiner/karabiner.json      the keyboard layer (Karabiner-Elements)
  config/mac-setup/keybindings.tsv     the searchable list (Super + K)
  README.md                            the shortcut table, between its markers

    python3 tools/bindings.py --check  exits 1 if any of them is out of date
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BIN = "$HOME/.mac-setup/bin"          # the package's commands (see lib/paths.sh)
# Omarchy's Super key. Held with a letter, it runs the shortcut below. Any
# Right Command combination not listed here still works as plain Command,
# and Left Command is never touched.
LAYER_KEY = "right_command"
BREW = "/opt/homebrew/bin"            # Homebrew on Apple silicon
AERO = f"{BREW}/aerospace"  # called directly: the fastest path for window keys


def sh(cmd):
    return ("sh", cmd)


def key(code, *mods):
    return ("key", code, list(mods))


def app(name):
    return sh(f"open -a '{name}'")


def cmd(name_and_args):
    return sh(f"{BIN}/{name_and_args}")


def web(url):
    return cmd(f"webapp '{url}'")


def aero(args):
    return sh(f"{AERO} {args}")


ARROWS = [("left_arrow", "left"), ("down_arrow", "down"), ("up_arrow", "up"), ("right_arrow", "right")]

# (key, extra modifiers held with Super, group, description, action)
BINDINGS = [
    # Menus
    ("spacebar", [], "Menus", "Search (Spotlight until the search app ships)", key("spacebar", "command")),
    ("spacebar", ["option"], "Menus", "Main menu", cmd("menu")),
    ("k", [], "Menus", "Shortcut list (type to filter, Return runs it)", cmd("keybindings")),
    ("escape", [], "Menus", "System menu (lock, sleep, restart, shut down)", cmd("menu System")),

    # Windows and workspaces
    ("l", ["control"], "Windows", "Lock screen", key("q", "control", "command")),
    ("t", [], "Windows", "Toggle tiling and floating", aero("layout floating tiling")),
    ("j", [], "Windows", "Toggle split direction", aero("layout horizontal vertical")),
    ("f", [], "Windows", "Full screen", aero("fullscreen")),
    ("g", [], "Windows", "Toggle grouping (stacked windows)", aero("layout accordion tiles")),
    ("equal_sign", [], "Windows", "Grow window", aero("resize smart +50")),
    ("hyphen", [], "Windows", "Shrink window", aero("resize smart -50")),
    ("tab", [], "Workspaces", "Next workspace", aero("workspace --no-stdin --wrap-around next")),
    ("tab", ["shift"], "Workspaces", "Previous workspace", aero("workspace --no-stdin --wrap-around prev")),
    ("tab", ["control"], "Workspaces", "Last used workspace", aero("workspace-back-and-forth")),
    ("tab", ["option"], "Workspaces", "Focus next monitor", aero("focus-monitor --wrap-around next")),
    ("left_arrow", ["shift", "option"], "Workspaces", "Move workspace to previous monitor",
     aero("move-workspace-to-monitor --wrap-around prev")),
    ("right_arrow", ["shift", "option"], "Workspaces", "Move workspace to next monitor",
     aero("move-workspace-to-monitor --wrap-around next")),
]

for code, direction in ARROWS:
    BINDINGS.append((code, [], "Windows", f"Focus window {direction}", aero(f"focus {direction}")))
    BINDINGS.append((code, ["shift"], "Windows", f"Swap window {direction}", aero(f"move {direction}")))

for n in range(1, 10):
    BINDINGS.append((str(n), [], "Workspaces", f"Go to workspace {n}", aero(f"workspace {n}")))
    BINDINGS.append((str(n), ["shift"], "Workspaces", f"Move window to workspace {n} and follow",
                     aero(f"move-node-to-workspace --focus-follows-window {n}")))
    BINDINGS.append((str(n), ["shift", "option"], "Workspaces", f"Move window to workspace {n}, stay here",
                     aero(f"move-node-to-workspace {n}")))

BINDINGS += [
    # Apps
    ("return_or_enter", [], "Apps", "Terminal (Ghostty)", app("Ghostty")),
    ("return_or_enter", ["option"], "Apps", "Terminal in a tmux session", sh(f"open -na Ghostty --args -e {BREW}/tmux new-session -A -s main")),
    ("return_or_enter", ["shift"], "Apps", "Browser (Chrome)", app("Google Chrome")),
    ("b", ["shift", "option"], "Apps", "Private browser window", sh("open -na 'Google Chrome' --args --incognito")),
    ("f", ["shift"], "Apps", "Finder", sh("open \"$HOME\"")),
    ("d", ["shift"], "Apps", "Google Drive folder", cmd("open-drive")),
    ("a", ["shift"], "Apps", "Claude", app("Claude")),
    ("a", ["shift", "option"], "Apps", "ChatGPT", app("ChatGPT")),
    ("a", ["shift", "control"], "Apps", "Gemini", app("Gemini")),
    ("n", ["shift"], "Apps", "Notion", app("Notion")),
    ("t", ["shift"], "Apps", "Reminders (tasks)", app("Reminders")),
    ("g", ["shift"], "Apps", "WhatsApp", app("WhatsApp")),
    ("m", ["shift"], "Apps", "Spotify", app("Spotify")),
    ("r", ["shift"], "Apps", "RStudio", app("RStudio")),
    ("w", ["shift"], "Apps", "WordCraft (documents)", app("WordCraft")),
    ("s", ["shift"], "Apps", "GridCraft (spreadsheets)", app("GridCraft")),
    ("k", ["shift"], "Apps", "DeckCraft (presentations)", app("DeckCraft")),
    ("o", ["shift"], "Apps", "PdfCraft (PDFs)", app("PdfCraft")),
    ("v", ["shift"], "Apps", "FilmCraft (video)", app("FilmCraft")),
    ("slash", ["shift"], "Apps", "Passwords", app("Passwords")),
    ("e", ["shift"], "Web apps", "Gmail", web("https://mail.google.com")),
    ("c", ["shift"], "Web apps", "Google Calendar", web("https://calendar.google.com")),
    ("p", ["shift"], "Web apps", "PubMed", web("https://pubmed.ncbi.nlm.nih.gov")),
    ("y", ["shift"], "Web apps", "YouTube", web("https://www.youtube.com")),

    # System controls
    ("a", ["control"], "System", "Audio output menu", cmd("audio")),
    ("m", ["control"], "System", "Next audio output", cmd("audio next")),
    ("b", ["control"], "System", "Bluetooth menu", cmd("bluetooth")),
    ("w", ["control"], "System", "Wi-Fi settings", sh("open 'x-apple.systempreferences:com.apple.wifi-settings-extension'")),
    ("s", ["control"], "System", "Share with AirDrop", sh("open -a AirDrop")),
    ("t", ["control"], "System", "What is using the Mac (btop)", sh(f"open -na Ghostty --args -e {BREW}/btop")),
    ("h", ["control"], "System", "Hardware menu", cmd("menu Hardware")),
    ("o", ["control"], "System", "Toggle menu", cmd("menu Toggle")),
    ("c", ["control"], "Capture", "Capture menu", cmd("menu Capture")),
    ("x", ["control", "shift"], "Capture", "Copy text from a screen area", cmd("capture text")),
    ("period", ["control"], "Capture", "Transcode menu (video, images, PDF)", cmd("menu Transcode")),
    # Copy, cut, paste and close are Super + C, X, V, W as in Omarchy: Right Command
    # is Command, so these are the Mac's own and work in the terminal too.
    ("v", ["option"], "Clipboard", "Paste as plain text (no formatting)", key("v", "command", "option", "shift")),
    ("v", ["control"], "Clipboard", "Clipboard history (Maccy)", key("c", "command", "shift")),
    ("e", ["control"], "Clipboard", "Emoji and symbols", key("spacebar", "control", "command")),

    # Voice, as Voxtype in Omarchy. Handy listens for F18, which this sends while held.
    ("x", ["control"], "Voice", "Dictate: hold, speak, release (Handy)", key("f18")),
    ("m", ["control", "option"], "Voice", "Record and transcribe a meeting (Meetily)", app("Meetily")),
    ("i", ["control"], "Toggles", "Keep the Mac awake", cmd("toggle awake")),
    ("n", ["control"], "Toggles", "Dark and light mode", cmd("toggle dark")),
    ("spacebar", ["shift"], "Toggles", "Hide or show the menu bar", cmd("toggle menubar")),
    ("m", ["control", "shift"], "Toggles", "Mute or unmute the microphone", cmd("toggle mic")),
    ("r", ["control"], "Reminders", "Set a reminder", cmd("reminder")),
    ("t", ["control", "option"], "Notices", "Show the time", cmd("notice time")),
    ("b", ["control", "option"], "Notices", "Show the battery", cmd("notice battery")),
    ("w", ["control", "option"], "Notices", "Show the weather", cmd("notice weather")),

    # Style
    ("spacebar", ["control", "shift"], "Style", "Pick a theme", cmd("theme pick")),
    ("spacebar", ["control"], "Style", "Next background", cmd("theme next-background")),
]

KEY_LABEL = {
    "spacebar": "Space", "escape": "Escape", "return_or_enter": "Return", "tab": "Tab",
    "equal_sign": "=", "hyphen": "-", "period": ".", "slash": "/", "comma": ",",
    "left_arrow": "Left", "right_arrow": "Right", "up_arrow": "Up", "down_arrow": "Down",
}
MOD_LABEL = {"control": "Ctrl", "option": "Option", "shift": "Shift", "command": "Cmd"}
MOD_ORDER = ["control", "option", "shift", "command"]
README_START = "<!-- shortcuts:start (generated by tools/bindings.py) -->"
README_END = "<!-- shortcuts:end -->"


def label(code, mods):
    parts = ["Super"] + [MOD_LABEL[m] for m in MOD_ORDER if m in mods]
    parts.append(KEY_LABEL.get(code, code.upper()))
    return " + ".join(parts)


def manipulator(code, mods, action):
    frm = {"key_code": code}
    frm["modifiers"] = {"mandatory": [LAYER_KEY] + mods}
    if action[0] == "sh":
        to = [{"shell_command": action[1]}]
    else:
        to = [{"key_code": action[1]}]
        if action[2]:
            to[0]["modifiers"] = action[2]
    return {
        "type": "basic",
        "from": frm,
        "to": to,
    }


def check_duplicates():
    seen = {}
    for code, mods, _, desc, _ in BINDINGS:
        sig = (code, tuple(sorted(mods)))
        if sig in seen:
            sys.exit(f"Duplicate shortcut {label(code, mods)}: '{seen[sig]}' and '{desc}'")
        seen[sig] = desc


def karabiner_json():
    ordered = sorted(BINDINGS, key=lambda b: -len(b[1]))  # most specific first
    config = {
        "global": {"show_in_menu_bar": False},
        "profiles": [{
            "name": "Default",
            "selected": True,
            "virtual_hid_keyboard": {"keyboard_type_v2": "ansi"},
            "complex_modifications": {
                "parameters": {"basic.to_if_alone_timeout_milliseconds": 250},
                "rules": [
                    {"description": "Shortcuts on Right Command, Omarchy's Super key. "
                                    "Generated by tools/bindings.py, do not edit.",
                     "manipulators": [manipulator(c, m, a) for c, m, _, _, a in ordered]},
                ],
            },
        }],
    }
    return json.dumps(config, indent=1) + "\n"


def keybindings_tsv():
    lines = ["# Generated by tools/bindings.py, do not edit. Keys\tGroup\tWhat it does\tCommand"]
    for code, mods, group, desc, action in BINDINGS:
        lines.append(f"{label(code, mods)}\t{group}\t{desc}\t{action[1] if action[0] == 'sh' else ''}")
    return "\n".join(lines) + "\n"


def readme(current):
    rows = ["| Keys | Action |", "| --- | --- |"]
    groups = {}
    for code, mods, group, desc, _ in BINDINGS:
        groups.setdefault(group, []).append((label(code, mods), desc))
    for group, items in groups.items():
        if group == "Workspaces":
            items = [i for i in items if not any(f"+ {n}" in i[0] for n in "2345678")]
        for keys, desc in items:
            rows.append(f"| {keys} | {desc} |")
    table = "\n".join(rows)
    start, end = current.index(README_START), current.index(README_END)
    return current[:start] + README_START + "\n\n" + table + "\n\n" + current[end:]


def outputs():
    readme_path = ROOT / "README.md"
    return {
        ROOT / "config" / "karabiner" / "karabiner.json": karabiner_json(),
        ROOT / "config" / "mac-setup" / "keybindings.tsv": keybindings_tsv(),
        readme_path: readme(readme_path.read_text()),
    }


def main():
    check_duplicates()
    stale = []
    for path, text in outputs().items():
        if "--check" in sys.argv:
            if not path.exists() or path.read_text() != text:
                stale.append(path.relative_to(ROOT))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    if stale:
        sys.exit("Out of date, run python3 tools/bindings.py: " + ", ".join(map(str, stale)))
    if "--check" not in sys.argv:
        print(f"{len(BINDINGS)} shortcuts written")


if __name__ == "__main__":
    main()
