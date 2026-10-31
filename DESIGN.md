# Design rules

Everything in this package, and every app built for it, follows these rules so the Mac looks like one system. A tool that looks out of place gets used less, so a new piece is not finished until it follows them.

## Type

Apple's own type for every letter and number. The one exception is a few terminal icons, below.

- **Interface text: SF Pro**, the macOS system font, in every window, menu, panel and notice. Apps use the system font API (SwiftUI `.body`, `.callout` and so on), never a hard-coded family. The pop-up menus use it by name (`SFProText-Regular`, installed by the `font-sf-pro` cask).
- **Code and terminal: SF Mono** (the `font-sf-mono` cask), and nowhere else. File paths in app windows are interface text, so they use SF Pro too. The one exception: the terminal falls back to Symbols Nerd Font Mono (the `font-symbols-only-nerd-font` cask) for the file and git icons eza and starship draw, which SF Mono does not have. That font holds icons only, no letters, so every word on screen is still SF.
- **Icons: SF Symbols** for every interface icon (buttons, sidebar, menus, chips). No icon fonts. The apps and files themselves keep the icons and thumbnails macOS draws for them, as in Finder and Spotlight, because that is how you recognise them.
- One size scale: 11 (labels, shortcuts), 13 (rows), 15 to 17 (inputs and titles). Numbers that line up in columns use tabular figures.

## Colour

- Every colour comes from the active theme file in `config/themes/<name>.theme`. Nothing has a colour of its own.
- Themes are built from Apple's system colours (the Human Interface Guidelines palette for light and dark appearance), so the package matches macOS. Daylight, the light theme, is Finder's neutral white with Apple's light system colours.
- `TERM_BG`, `TERM_FG` and `TERM_SELECTION` are the background, text and selected-row colours for every surface, not only the terminal.
- `HIGHLIGHT` marks matches and the focused item. `PALETTE` holds the 16 terminal colours, which terminal tools use.
- The semantic keys name a role, not a hue: `ACCENT_HEX` (the accent as a colour, beside `ACCENT`, the macOS accent number), `MUTED` (secondary text), `BG_LIGHTER` and `BG_DARKER` (raised and sunken surfaces). Templates use these, so a new theme only fills them in.
- Each app's colours come from a template in `config/themed/`. `theme set` fills it in with the theme's values into `~/.local/state/grand-line/current/theme/`, all at once.
- Apps built for the package read the theme from `~/.local/state/grand-line/theme` (the theme's name) and the theme file, and follow light or dark mode from it.
- Text keeps at least 4.5:1 contrast against its background in every theme, including Daylight, where every terminal colour reads at 4.5:1 on white (the tests check it).

## Shape and density

- Dense and calm, like the search window: compact rows, hairline dividers, no gradients, no drop shadows beyond the window's own, no emoji.
- Corner radius 10 on windows, 5 on chips and keys.
- Every action has a keyboard shortcut, shown in a footer or the Caps + K list.

## Adding a theme

Copy an existing `.theme` file, fill in every field (the tests check all of them), add its wallpaper to `backgrounds/`, and add its Neovim scheme to `config/nvim/lua/plugins/theme.lua` if it is not one already there (vscode.nvim covers both a dark and a light theme, through `MODE`). `theme pick` then restyles the terminal, editor, menus, wallpaper, accent colour and the package's own apps together.
