# Design rules

Everything in this package, and every app built for it, follows these rules so the Mac looks like one system. A tool that looks out of place gets used less, so a new piece is not finished until it follows them.

## Type

Apple's own type for every letter and number.

- **Interface text: SF Pro**, the macOS system font, in every window, menu, panel and notice of Sight and Iceberg. Apps use the system font API (SwiftUI `.body`, `.callout` and so on), never a hard-coded family.
- **Code: SF Mono** (the `font-sf-mono` cask) inside Sight and Iceberg. The package sets no font in Terminal, Neovim or any other app.
- **Icons: SF Symbols** for every interface icon (buttons, sidebar, menus, chips). No icon fonts. The apps and files themselves keep the icons and thumbnails macOS draws for them, as in Finder and Spotlight, because that is how you recognise them.
- One size scale, from the system text styles so they follow the text size you set: Subheadline 11 (labels, shortcuts), Body 13 (rows), Title 2 17 (titles) and Title 1 22 (Sight's query, as Spotlight's). Emphasis comes from weight, not size. Numbers that change or line up in columns use tabular figures.

## Colour and appearance

Sight and Iceberg look like Apple's own apps, and the package never changes how macOS or any other app looks.

- **Every colour is the system's.** Text uses the label colours (primary, secondary, tertiary), lines the separator colour, the selected row the system's selection colour (the accent), focus and matches the accent colour, and states the system red, orange, yellow, green and blue. These are dynamic, so they follow Light and Dark, the accent and highlight colours and Increase Contrast as you set them in System Settings, Appearance and Accessibility, with nothing to restart. No app reads a colour from a file, and there are no themes.
- **Surfaces are system materials.** Sight is Liquid Glass on macOS 26 and later (`NSGlassEffectView`), as Spotlight is, and a behind-window popover material before that. Its action panel is a menu surface. Iceberg's drop basket is the popover material. Settings windows use the sidebar material and the window background. Reduce Transparency and Increase Contrast are handled by the materials themselves.
- **The notch is black.** Iceberg's panel grows out of the camera housing, so like the Dynamic Island it stays black in Light and Dark, with the label colours and the accent colour drawn for a dark appearance in that view only. Its Settings window, the drop basket and the menus follow macOS.
- **macOS and other apps keep their own look.** The package sets no appearance, accent colour, highlight colour, wallpaper, Dock, desktop or font, and writes no colours into Terminal, Neovim, tmux, starship, btop, lazygit, Claude Code or any other app. The Dark mode setting in Sight changes macOS's appearance only when you choose it.
- Text keeps at least 4.5:1 contrast against its background, which the system colours give in both appearances.

The icons are original, generic glyphs drawn from one table (`apps/icons`): the back of an eye (optic disc, vessels arching around the macula) for search, and an iceberg for the notch app. They sit on Apple's icon grid (an 824 point tile on a 1024 canvas, corners of 185), use no gradients or shadows, and leave fine detail out at 16 and 32 pixels.

## Shape, motion and density

- Dense and calm, like Spotlight: compact rows, hairline separators, no gradients, no drop shadows beyond the window's and the menu's own, no emoji.
- Standard corner radii: Sight's window 24 on Liquid Glass and 14 before it, its selection highlight 10 and 6 (concentric with the window at a 6 point inset), menus and the action panel 14 and 8, Settings cards 10, key caps 5.
- Rows highlight on mouse-down and run on mouse-up inside them. Motion uses critically damped springs, and every spring becomes a short cross-fade with Reduce Motion.
- Every action has a keyboard shortcut, shown as a key cap beside its name in a footer or the Caps + K list, in the secondary label colour, as Spotlight and menus show them.
