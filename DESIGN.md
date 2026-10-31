# Design rules

Everything in this package, and every app built for it, follows these rules so the Mac looks like one system. A tool that looks out of place gets used less, so a new piece is not finished until it follows them.

## Type

- **Interface text: SF Pro**, the macOS system font, in every window, menu, panel and notice. Apps use the system font API (SwiftUI `.body`, `.callout` and so on), never a hard-coded family. The pop-up menus use it by name (`SFProText-Regular`, installed by the `font-sf-pro` cask).
- **Code and terminal: JetBrains Mono Nerd Font**, and nowhere else. File paths in app windows are interface text, so they use SF Pro too.
- One size scale: 11 (labels, shortcuts), 13 (rows), 15 to 17 (inputs and titles). Numbers that line up in columns use tabular figures.

## Colour

- Every colour comes from the active theme file in `config/themes/<name>.theme`. Nothing has a colour of its own.
- `TERM_BG`, `TERM_FG` and `TERM_SELECTION` are the background, text and selected-row colours for every surface, not only the terminal.
- `HIGHLIGHT` marks matches and the focused item. `PALETTE` holds the 16 terminal colours, which terminal tools use.
- Apps built for the package read the theme from `~/.local/state/mac-setup/theme` (the theme's name) and the theme file, and follow light or dark mode from it.
- Text keeps at least 4.5:1 contrast against its background in every theme, including Paper.

## Shape and density

- Dense and calm, like the search window: compact rows, hairline dividers, no gradients, no drop shadows beyond the window's own, no emoji.
- Corner radius 10 on windows, 5 on chips and keys.
- Every action has a keyboard shortcut, shown in a footer or the Caps + K list.

## Adding a theme

Copy an existing `.theme` file, fill in every field (the tests check all of them), add its wallpaper to `backgrounds/`, and add its Neovim scheme to `config/nvim/lua/plugins/theme.lua`. `theme pick` then restyles the terminal, editor, menus, wallpaper, accent colour and the package's own apps together.
