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

### Theme keys

Every theme file holds the keys below (the tests check them). A key marked optional may be left out, and the apps then use what it falls back to, so a theme written before a key existed still works.

| Key | Meaning |
| --- | --- |
| `LABEL`, `MODE` | The name shown in menus, and `dark` or `light` |
| `FAMILY` | Optional. The family a dark and light pair belongs to, in files named `FAMILY-dark.theme` and `FAMILY-light.theme`. `theme set FAMILY` picks the variant for the current macOS appearance, and `theme mode toggle` switches between them (Graphite and Daylight pair up without it) |
| `ACCENT` | The macOS accent colour number (-1 graphite, 0 red, 1 orange, 2 yellow, 3 green, 4 blue, 5 purple, 6 pink) |
| `BACKGROUND`, `NVIM` | The wallpaper in `backgrounds/` and the Neovim scheme |
| `TERM_BG`, `TERM_FG`, `TERM_SELECTION`, `TERM_CURSOR` | Surface, text, selected row and cursor, for every surface |
| `PALETTE` | The 16 terminal colours |
| `ACCENT_HEX`, `HIGHLIGHT`, `MUTED` | The accent as a colour, matches and the focused item, secondary text |
| `BG_LIGHTER`, `BG_DARKER` | Raised surfaces (cards, chips) and sunken ones (the desk behind windows) |
| `SIDEBAR`, `FIELD`, `LINE` | Optional. The sidebar, text fields and dividers. Missing: `BG_LIGHTER`, then colours mixed from the surface and text |
| `NOTCH_PANEL`, `NOTCH_CARD`, `NOTCH_LINE` | Optional. Den Den's open panel, its chips and its column dividers. Missing: `TERM_BG`, then `FIELD` or `BG_LIGHTER`, then `LINE`. The part of the panel under the camera, and the closed notch, are always black so they meet the hardware |
| `KIND_STYLE` | How Log Pose and Byakugan mark a file's kind: `tag` (a tinted tag with the extension), `dot`, `solid` (a filled tag) or `text` (the kind's name in its colour) |
| `KIND_FOLDER`, `KIND_DOCUMENT`, `KIND_PDF`, `KIND_PRESENTATION`, `KIND_SPREADSHEET`, `KIND_IMAGE`, `KIND_VIDEO`, `KIND_CODE`, `KIND_ARCHIVE`, `KIND_TEXT` | The colour of each kind. Missing: the accent and terminal colours |
| `ICON_STYLE` | The app icons: `line` (a dark tile, a light glyph and the app's colour as its hot point), `solid` (the app's colour as the tile, a dark glyph) or `mono` (a black tile, the glyph in the app's colour). Missing: `line` |
| `ICON_TILE`, `ICON_INK` | Optional. The tile (line and mono) and the glyph (line and solid). Missing: a dark tile (the theme's surface when it is dark) and light ink; mono is black, solid ink is near black |
| `ICON_ACCENT`, `ICON_SOFT` | Optional. Every app's colour, and the quiet fills (the sea, the iceberg under water). Missing: `ACCENT_HEX`, then `HIGHLIGHT`; soft is the tile with a quarter of the accent |
| `ICON_FILES`, `ICON_SEARCH`, `ICON_NOTCH` | Optional. One app's own colour: the file browser (Log Pose), search (Byakugan, also the warm tone of its eye) and the notch app (Den Den). Missing: `ICON_ACCENT` |

The icons are original, generic glyphs drawn from one table (`apps/icons`): a sailing ship for the file browser, the back of an eye (optic disc, vessels arching around the macula) for search, and an iceberg for the notch app. They sit on Apple's icon grid (an 824 point tile on a 1024 canvas, corners of 185), use no gradients or shadows, and leave fine detail out at 16 and 32 pixels.

## Shape and density

- Dense and calm, like the search window: compact rows, hairline dividers, no gradients, no drop shadows beyond the window's own, no emoji.
- Corner radius 10 on windows, 5 on chips and keys.
- Every action has a keyboard shortcut, shown in a footer or the Caps + K list.

## Adding a theme

Copy an existing `.theme` file, fill in every field (the tests check all of them, and that every colour is a six-digit hex value), add its wallpaper to `backgrounds/`, and add its Neovim scheme to `config/nvim/lua/plugins/theme.lua` if it is not one already there (vscode.nvim covers both a dark and a light theme, through `MODE`). `theme pick` then restyles the terminal, editor, menus, wallpaper, accent colour and the package's own apps together.
