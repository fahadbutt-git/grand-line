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
- Apps built for the package read the theme from `~/.local/state/grand-line/theme` (the theme's name) and the theme file, and follow light or dark mode from it. With Follow macOS chosen in Settings, Appearance, a theme with a dark and a light variant switches with the system.
- Text keeps at least 4.5:1 contrast against its background in every theme, including Daylight, where every terminal colour reads at 4.5:1 on white (the tests check it).

### Theme format

Theme files are format 1: `KEY=value` lines, `#` comments, values in quotes when they hold a space. Every key below sits in one namespace. A required key must be in the file or its parent. An optional key may be left out and then takes its default, so a theme written before a key existed still works. The checker (`theme check`, run on every load by the shell, Nexus, Sight and Iceberg alike, and by the tests on every shipped theme) fills the defaults, rejects bad values with `FILE:LINE` messages, and warns about weak contrast. A theme with errors is never applied: `theme set` refuses it and the apps show its base theme (Graphite or Daylight) with the errors listed.

**Format and inheritance**

| Key | | Meaning and default |
| --- | --- | --- |
| `FORMAT` | required | `1`, the format the file is written in. A newer number is an error, and a file without it is read as 1 with a warning |
| `EXTENDS` | optional | One parent theme in the same folder. The parent's keys come first and the file's own replace them, so a light variant extends its dark sibling and sets only what differs. Parents may extend in turn (8 deep at most). A loop or a missing parent is an error |
| `LABEL`, `MODE` | required | The name shown in menus, and `dark` or `light` |
| `FAMILY` | optional | The family a dark and light pair belongs to, in files named `FAMILY-dark.theme` and `FAMILY-light.theme`. `theme set FAMILY` picks the variant for the current macOS appearance, and `theme mode toggle` switches between them (Graphite and Daylight pair up without it) |
| `ACCENT` | optional | The macOS accent colour number (-1 graphite, 0 red, 1 orange, 2 yellow, 3 green, 4 blue, 5 purple, 6 pink, or `multicolor`). Default -1 |
| `BACKGROUND`, `NVIM` | optional | The wallpaper in `backgrounds/` (default `graphite.jpg` for dark, `daylight.jpg` for light) and the Neovim scheme (default `vscode`) |

**Colour.** Every colour is six hex digits (`57b4f0`, and a leading `#` is accepted and dropped).

| Key | | Meaning and default |
| --- | --- | --- |
| `TERM_BG`, `TERM_FG` | required | Surface and text, for every surface, not only the terminal |
| `PALETTE` | required | The 16 terminal colours, in order (templates see them as `COLOR0` to `COLOR15`) |
| `ACCENT_HEX` | optional | The accent as a colour. Default `HIGHLIGHT`, else `COLOR4` |
| `HIGHLIGHT` | optional | Matches and the focused item. Default `ACCENT_HEX` |
| `TERM_CURSOR`, `TERM_SELECTION` | optional | Cursor and selected row. Default the accent, and the surface with a quarter of the accent |
| `MUTED` | optional | Secondary text. Default the text 45% of the way to the surface |
| `BG_LIGHTER`, `BG_DARKER` | optional | Raised surfaces (cards, chips) and sunken ones (the desk behind windows). Default the surface with 4% of the text, and the surface 30% toward black (dark) or with 10% of the text (light) |
| `SIDEBAR`, `FIELD`, `LINE` | optional | The sidebar, text fields and dividers. Missing: each app derives them from `BG_LIGHTER`, the surface and the text |
| `NOTCH_PANEL`, `NOTCH_CARD`, `NOTCH_LINE` | optional | Iceberg's open panel, its chips and its column dividers. Missing: `TERM_BG`, then `FIELD` or `BG_LIGHTER`, then `LINE`. The part of the panel under the camera, and the closed notch, are always black so they meet the hardware |
| `COLOR_<NAME>` | optional | Colours of your own, for your own templates |

**Font, radius and spacing.** The design rules below as numbers, so the apps can share them.

| Key | | Meaning and default |
| --- | --- | --- |
| `FONT_UI`, `FONT_MONO` | optional | Interface and code type. Default `SF Pro` and `SF Mono` (the system fonts) |
| `FONT_SIZE` | optional | Row text in points, 9 to 24. Default 13 |
| `RADIUS_WINDOW`, `RADIUS_CHIP` | optional | Corner radius of windows (0 to 32) and of chips and keys (0 to 16). Default 10 and 5 |
| `SPACING_UNIT` | optional | The step paddings are multiples of, 2 to 16 points. Default 4 |

**Density and motion**

| Key | | Meaning and default |
| --- | --- | --- |
| `UI_DENSITY` | optional | `compact`, `regular` or `comfortable` rows in every app. No default: missing, each app keeps its own choice in Settings, Appearance |
| `UI_MOTION` | optional | `full` or `reduced` animation. Default `full` |

**Icon style**

| Key | | Meaning and default |
| --- | --- | --- |
| `ICON_STYLE` | optional | The app icons: `line` (a dark tile, a light glyph and the app's colour as its hot point), `solid` (the app's colour as the tile, a dark glyph) or `mono` (a black tile, the glyph in the app's colour). Default `line`. Shipped themes keep it in every file, since the icon script reads files as written |
| `ICON_TILE`, `ICON_INK` | optional | The tile (line and mono) and the glyph (line and solid). Missing: a dark tile (the theme's surface when it is dark) and light ink, while mono is black and solid ink is near black |
| `ICON_ACCENT`, `ICON_SOFT` | optional | Every app's colour, and the quiet fills (the sea, the iceberg under water). Missing: `ACCENT_HEX`, then `HIGHLIGHT`, and soft is the tile with a quarter of the accent |
| `ICON_FILES`, `ICON_SEARCH`, `ICON_NOTCH` | optional | One app's own colour: the file browser (Nexus), search (Sight, also the warm tone of its eye) and the notch app (Iceberg). Missing: `ICON_ACCENT` |

**Kinds**

| Key | | Meaning and default |
| --- | --- | --- |
| `KIND_STYLE` | optional | How Nexus and Sight mark a file's kind: `tag` (a tinted tag with the extension), `dot`, `solid` (a filled tag) or `text` (the kind's name in its colour). Default `tag` |
| `KIND_FOLDER`, `KIND_DOCUMENT`, `KIND_PDF`, `KIND_PRESENTATION`, `KIND_SPREADSHEET`, `KIND_IMAGE`, `KIND_VIDEO`, `KIND_CODE`, `KIND_ARCHIVE`, `KIND_TEXT` | optional | The colour of each kind. Default the accent, then `COLOR4`, `COLOR1`, `COLOR3`, `COLOR2`, `COLOR5`, `COLOR13`, `COLOR11`, `COLOR9`, and `MUTED` |

**Contrast.** The checker warns when text (`TERM_FG`) falls under 4.5:1, or secondary text (`MUTED`) under 3:1, on the window (`TERM_BG`) or the sidebar (`SIDEBAR`, else `BG_LIGHTER`). It is a warning, not an error, because the apps lift text that falls short. `theme check --strict` fails on it too.

**Templates.** `theme set` renders every `config/themed/*.tpl` with the resolved theme (parent and defaults filled). `{{ KEY }}` takes any key, plus `NAME` (the theme's file name). A colour comes in four forms: `{{ KEY }}` is `#57b4f0`, `{{ KEY.hex }}` is `57b4f0`, `{{ KEY.rgb }}` is `87,180,240` and `{{ KEY.dec }}` is `0.341 0.706 0.941`. A template written as `#{{ KEY }}` still gets one `#`. An unknown key or form stays as written.

**Commands.** `theme check [--strict] [NAME|FILE...]` checks themes (all of them by default). `theme resolve NAME` prints a theme with its parent and defaults filled in. `theme apply` renders every template for the current theme again and reloads each tool: Ghostty and btop by `SIGUSR2` (only from Ghostty 1.2 and btop 1.3.1, which reload on it, while older ones keep their colours until they next start), tmux and its status bar by `source-file`, every running Neovim through its server socket, and the apps. `theme import-base16 FILE.yaml NAME` makes a theme from a base16 scheme (flat or with a `palette:` block): `base00` the surface, `base01` raised surfaces, `base02` the selection, `base04` secondary text, `base05` text and cursor, `base07` the brightest palette entry, `base08` to `base0F` red, orange, yellow, green, cyan, blue, magenta and brown, with `base0D` as the accent. It is dark unless the scheme says it is light, and is kept only if it passes the checker.

**Live switching.** After `theme set`, `theme mode` and `theme apply` the command posts the distributed notification `com.grandline.theme.changed` (with the theme's name), through JavaScript for Automation, so no helper is built and no Apple event is sent. Nexus, Sight and Iceberg reload on it at once. They also watch the state and theme files, which catches edits made by hand.

The icons are original, generic glyphs drawn from one table (`apps/icons`): a sailing ship for the file browser, the back of an eye (optic disc, vessels arching around the macula) for search, and an iceberg for the notch app. They sit on Apple's icon grid (an 824 point tile on a 1024 canvas, corners of 185), use no gradients or shadows, and leave fine detail out at 16 and 32 pixels.

## Shape and density

- Dense and calm, like the search window: compact rows, hairline dividers, no gradients, no drop shadows beyond the window's own, no emoji.
- Corner radius 10 on windows, 5 on chips and keys.
- Every action has a keyboard shortcut, shown in a footer or the Caps + K list.

## Adding a theme

Copy an existing `.theme` file, or start from a base16 scheme with `theme import-base16`. For a light variant of a dark theme, write `EXTENDS=NAME-dark` and only the keys that differ (the shipped families keep `ICON_STYLE` and every colour in both files). Run `theme check NAME` until it passes, add its wallpaper to `backgrounds/`, and add its Neovim scheme to `config/nvim/lua/plugins/theme.lua` if it is not one already there (vscode.nvim covers both a dark and a light theme, through `MODE`). The tests also want every shipped theme to have its own `FORMAT=1` line and every key in the colour and kind tables resolved. `theme pick` then restyles the terminal, editor, menus, wallpaper, accent colour and the package's own apps together.
