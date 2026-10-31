# shellcheck shell=bash
# Your own shortcuts on top of the package's, kept out of the package so a
# GitHub update never clashes with them. Sourced by the dotfiles step.
#
# ~/.config/grand-line/bindings.local.tsv, one shortcut per line, the same
# columns as config/grand-line/keybindings.tsv:
#   Caps + Shift + Z<TAB>Apps<TAB>Zotero<TAB>open -a Zotero
#   unbind<TAB>Caps + X
# A line for keys the package already uses replaces that shortcut.

# shellcheck disable=SC2034  # read by steps/08-dotfiles.sh
BINDINGS_LOCAL="$HOME/.config/grand-line/bindings.local.tsv"

# karabiner_with_overlay KARABINER_JSON LOCAL_TSV: prints the merged file.
# Lines whose keys do not start with "Caps" are skipped.
karabiner_with_overlay() {
  jq --rawfile tsv "$2" '
    def keycode: {"Space": "spacebar", "Escape": "escape", "Return": "return_or_enter",
      "Tab": "tab", "Backspace": "delete_or_backspace", "=": "equal_sign", "-": "hyphen",
      ".": "period", "/": "slash", ",": "comma", ";": "semicolon", "'"'"'": "quote",
      "[": "open_bracket", "]": "close_bracket", "\\": "backslash", "`": "grave_accent_and_tilde",
      "Left": "left_arrow", "Right": "right_arrow", "Up": "up_arrow", "Down": "down_arrow"}[.]
      // ascii_downcase;
    def mods: map({"Ctrl": "control", "Option": "option", "Shift": "shift", "Cmd": "command"}[.]);
    def parse: split(" + ") | select(.[0] == "Caps" and length >= 2)
      | {key: (.[-1] | keycode), mods: (.[1:-1] | mods | sort)};
    def same($o): .from.key_code == $o.key and ((.from.modifiers.mandatory // []) | sort) == $o.mods;
    def manipulator($o): {type: "basic",
      conditions: [{type: "variable_if", name: "caps_layer", value: 1}],
      from: ({key_code: $o.key} + (if ($o.mods | length) > 0 then {modifiers: {mandatory: $o.mods}} else {} end)),
      to: [{shell_command: $o.cmd}]};
    [ $tsv | split("\n")[] | select(length > 0 and (startswith("#") | not)) | split("\t")
      | if .[0] == "unbind" then (.[1] // "" | parse) + {cmd: null}
        else (.[0] | parse) + {cmd: (.[3] // "")} end
      | select(.cmd != "") ] as $ops
    | (.profiles[].complex_modifications.rules[]
       | select(.description | startswith("Shortcuts on the Caps Lock layer")) | .manipulators) |=
      reduce $ops[] as $o (.; map(select(same($o) | not))
        | if $o.cmd then [manipulator($o)] + . else . end)
  ' "$1"
}
