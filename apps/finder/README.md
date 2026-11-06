# Finder

Sight, a keyboard-first replacement for Spotlight, with the libraries it is built on and Grand Line Index, the background agent it searches file names through.

## QueryKit

QueryKit turns a typed query into three things:

1. A parsed tree (`QueryParser.parse`), with a list of issues (message and character range) for the search field to underline. A bad filter never discards the rest of the query.
2. Plain-language chips (`QueryChips.describe`), such as "Word or PDF" or "changed in the last 30 days".
3. An `NSPredicate`, search scopes, a path post-filter and a sort key for `NSMetadataQuery` (`SpotlightCompiler.compile`). Dates are resolved against an injected `now` and `Calendar`, and `@name` saved searches are expanded through a closure.

```swift
let parsed = QueryParser.parse(#"(glauc OR cornea) kind:doc,pdf in:"01 Research" modified:<30d -draft"#)
let query = SpotlightCompiler.compile(parsed, savedSearch: { savedSearches[$0] })
metadataQuery.predicate = query.predicate
metadataQuery.searchScopes = query.scopes.isEmpty ? [NSMetadataQueryUserHomeScope] : query.scopes
// keep results whose path passes query.postFilter
```

Spotlight does not index paths, so folder names (`in:Downloads`) and exclusions (`-in:Archive`) run as the post-filter. Absolute folders, `drive:` and `local:` also narrow the search scopes. Folder filters apply to the whole query, so they cannot share an OR group with other terms.

## IndexKit

An in-memory index of file and folder names, for search as you type. `FileIndex` is an actor built from root folders. It keeps each entry as a name and a parent in flat arrays, and rebuilds paths only for the results it returns.

```swift
let index = (try? FileIndex.load(from: snapshot)) ?? FileIndex(roots: [NSHomeDirectory()])
if await index.count == 0 { await index.build() }
await index.startWatching()            // FSEvents, replaying changes since the snapshot
let matches = await index.search("gl rev", limit: 20)
await index.noteOpened(matches[0].path)
try await index.save(to: snapshot)
```

- Ranking: exact (also without the extension), then prefix, word start (after a space, `_`, `-`, `.`, a letter to digit change or a camelCase hump), substring, and fuzzy. A fuzzy match is tight: letters in order, the first at a word start, at most three letters skipped inside a word, a new word entered only at its first letter and only after the start of the word before, at most two words skipped, and never a letter from the file's extension, so "gl rev" finds "Glaucoma Review" but "conj" does not find prisma_config.json or "combined_Li_J". Ties go to the more used path (`noteOpened`), then the shallower one.
- Matching ignores case and accents. Highlights come back as UTF-16 ranges of the name.
- `IndexExclusions.standard` skips `.DS_Store`, `._*`, `.git`, `node_modules`, `.build`, caches and similar, and indexes app bundles as one item.
- `FolderWatcher` publishes coalesced `FolderChange`s. `apply(_:)` rescans only the changed folders.
- Search runs one task per core over the arrays, behind a character bitmask that rejects most names at once.
- Names are composed (NFC) before folding, so a decomposed name on disk matches a composed query and the other way round.

## Grand Line Index (the shared index service)

Sight keeps no index of its own. `Grand Line Index.app` (product `GrandLineIndex`, bundle id `com.grandline.index`) is a background-only agent that launchd runs at login from `Contents/Library/LaunchAgents/com.grandline.index.plist` (registered with `SMAppService.agent` by `GrandLineIndex --register`). It owns one `FileIndex` of the home folder, without `~/Library` except `~/Library/CloudStorage`, and serves it over the XPC Mach service `com.grandline.index`.

- Start: the snapshot in `~/Library/Application Support/Grand Line Index/names.index` loads at once. On the first start the agent adopts Sight's older `names.index` when it has one, so nothing is walked again.
- Freshness: the snapshot stores the last FSEvents event and each root's volume UUID. `IndexRecovery.startup` resumes from the event, or walks again (while the old index answers) when the snapshot was unfinished, the volume UUID changed or the event counter is behind. `IndexRecovery.event` maps MustScanSubDirs and RootChanged to a rescan of that folder, dropped events to every root (walked in the background) and a wrapped counter to a full walk. A quiet full sweep runs weekly. The index is saved every five minutes when it changed, and on SIGTERM.
- Clients: `SharedIndexClient` (IndexService) sends `search(text, limit, scope)` and gets one `MatchCodec` buffer back. Each connection has its own narrowing cache. When the agent cannot be reached the client runs `open -g -j -b com.grandline.index` and answers from a copy read from the agent's snapshot (never written), which follows FSEvents if the agent stays away. Apps connect at launch, before their first search, and keep the connection open. A search gives the agent a head start of 0.15 s, then races it against the copy and shows whichever answers first. When the copy wins, the agent's answer is still awaited and `onLateAnswer` lets the app search again, so a file only the agent knows about appears a moment later. Only a failed connection, not a slow one, sends searches to the copy for a while.
- Security: only processes of the same user can look up the Mach service, and each side checks the other's code signature (`setCodeSigningRequirement`): the same Apple team, else the same leaf certificate (the local signing identity), else, for ad-hoc builds, the bundle identifier only.
- The agent is the app that needs Full Disk Access (or Files and Folders); for name search, Sight does not.

## Settings window

Sight's Settings window (`SettingsKit`) is laid out like System Settings: the panes in a translucent sidebar on the left (the sidebar material, the selected pane filled with the accent colour), the chosen pane on the right in grouped cards, all in the system's own colours, so it follows Light and Dark and the accent colour. Every entry has the accessibility identifier `sight.settings.<pane>`. It opens with Cmd+, (while the search window is in front), from Sight's menu bar item, from `sight://settings` (a pane can follow: `sight://settings/search`), and from the main menu's Settings group, which Sight finds as "sight settings" and "iceberg settings". Every change is saved at once and applies to open windows.

General (the launcher shortcut, recorded in `LauncherHotkey`; the menu bar item; open at login; `CloseAfterSettingChange`), Sources (turn result sources off and set the order of their sections, with each prefix), Search (what the index covers, the index's state and Rebuild Index through IndexKit's `IndexStatusProviding`, and rows per section), Web (search engines with a keyword and a URL with %s, which of them show as fallbacks, Drive and the assistants), Appearance (a button to System Settings, Appearance, and row density, Sight's own), Advanced (reload sources, logs, reset usage history: usage.json goes to the Trash), Update now. Kept in the `com.grandline.sight` defaults (`SightPreferences`); quicklinks.tsv still adds engines.

## LaunchKit

`HotkeySetting` says whether Sight should register Command+Space (the `TakesCommandSpace` default).

## Sight

The search window that replaces Spotlight and Alfred. `LauncherKit` holds everything that can be tested without a screen; `Sight` is the AppKit and SwiftUI app on top of it.

- Providers answer a `LaunchQuery`. Instant providers (`InstantProvider`) answer on the keystroke; the others run concurrently, are cancelled by the next key, and merge in below without stealing the selection (`ResultList.merge`).
- Matching (`Matching/`): every provider's titles and keywords go through one `TextMatcher`. A 64-bit mask of the letters in each text is checked first, so texts that lack a letter of the query are skipped without matching. The tier (exact, prefix, word start, substring, fuzzy with the first letter at a word start) comes from IndexKit's rules. Inside a tier, `FuzzyScore` gives fzf's score: 16 per letter, a bonus at a word start, after a delimiter or at a camelCase hump or letter-digit change (twice for the first letter), letters in a row keep the bonus of their run, and gaps cost 3 plus 1 per extra letter. The fuzzy tier places the letters where that score is highest, and only counts when they are close together: each word used is entered at its first letter, letters inside a word skip at most three, and at most two words are skipped between the words used, so "vsc" finds Visual Studio Code but "sleep" does not find a title with s, l, e, e, p scattered through it. Below fuzzy is a typo tier: a word of four letters or more one edit (a letter missed, added, changed, or two swapped) from the start of a word, with the right first letter ("calender" finds Calendar). File names from the index keep the index's tier and are scored the same way; the index's fuzzy hits are tight already (IndexKit applies the same limits) and are dropped unless the matcher agrees. A Spotlight hit whose name does not match the words (found only inside the file) ranks below every name match.
- Rank order is fixed: exact alias, alias prefix, exact and prefix titles, the row learned for exactly what was typed, the other title tiers, the keyword tier, then fzf's score blended with frecency (score + 12 × log2(1 + frecency)). Fallbacks always come last. Learning never lifts a row above an exact or prefix title.
- Frecency (`UsageStore`) follows zoxide: a count that halves every 7 days, times ×4 when last picked within the hour, ×2 within the day, ×½ within the week, ×¼ after that. Picks from exactly this query count four times, from a longer query that starts with it twice. Abbreviations follow LaunchBar: the first row picked after typing "xyz" is what "xyz" stands for next time, and picking another row for "xyz" twice in a row takes it over. Both live in `usage.json` (at most 2,000 results, 2,000 queries with 12 rows each, and 2,000 abbreviations, dropping the weakest or oldest first).
- The top row stays put while you type (`TopRowHold`): once a row is on top for "saf", it stays on top for "safa" unless something in a strictly better tier turns up (a better alias, title or keyword tier, or the row learned for that abbreviation). Slower providers merge in below the selection (`ResultList.merge`) and never replace the top hit. Deleting letters starts over.
- Sections: Top hit, Answers, Apps, System, Grand Line, Windows, Files, Bookmarks, Snippets, Symbols, Web, then Other actions. A short word (three letters or fewer) never puts a calculator answer above an app that starts with it.
- Prefixes, shown as a chip at the start of the field once typed: `/` files (QueryKit, while `/` alone lists the prefixes, `/a/b` and existing folders such as `/Users` are paths, `.` still works), `=` maths, `:` clipboard history (below), `>` commands (Grand Line commands, menu entries and script commands that match, and the text as a shell line), `!` windows (`<` still works), `,` settings (settings you can change and System Settings panes), `?` web, `%` Zen bookmarks, `;` snippets, `$` shows Maccy itself (presses its own ⇧⌘C, so Accessibility is needed), `::` symbols, `'` exact, `@` saved searches (`~/.config/grand-line/sight/saved-searches.tsv`, name TAB query). Reminders moved from `!` to the word `remind` ("remind call the lab 20m").
- Clipboard history: `:` lists Maccy's history inside Sight, read only. Maccy has no API, so its store (`~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite`) is copied with its write-ahead log and the copy is read. It lists text entries only, pinned first, then newest. Return pastes, ⇧⌘C copies. Without that file the provider is hidden and `:` lists the symbols as before.
- Command+K (`ActionPanel`) lists every action of the selected row and the ones every row of its kind has: for files, Open, Open with…, Show in Finder, Quick Look, Copy path (⌥⌘C), Copy name (⇧⌘N), Copy file, Add to buffer (⌘B) and Move to Trash, which asks first (a second Return or click) and never deletes. Apps add Show in Finder and Copy path and name, sums add Copy result, bookmarks and links add Open and Copy URL, and commands add Run and Edit (which opens the script in the text editor). Any of these shortcuts works without opening the panel. Escape closes the panel (or cancels its question) and keeps the query. Actions in it can also be clicked.
- File buffer: Command+B puts the selected file in the buffer (again takes it out), shown as chips under the field. While it holds files, Command+K lists actions for all of them (open, show in Finder, Quick Look, copy paths, names or files, move, AirDrop, move to the Trash, clear the buffer), and the buffer empties once one runs.
- `selection` lists the same actions for the files selected in Finder when the window opened, read through AppleScript, as `lib/bin-common.sh` `finder_selection` reads it. More words narrow them ("selection trash").
- When nothing matches, the bottom of the list offers the web engines marked as fallbacks in Settings, Web, then Calculate (when there is a digit), Create file "<words>" in Downloads (an empty file, never over an existing one, shown in Finder) and Run "<words>" in Terminal, which only runs on a second Return.
- File names come from the shared Grand Line Index service: an IndexKit index of the home folder, without `~/Library` (Google Drive in `~/Library/CloudStorage` stays) and with IndexKit's standard exclusions (`.git`, `node_modules`, `.build`, caches, the Trash). Contents and filters go to Spotlight.
- Grand Line sources: `menu.tsv` and `menu.local.tsv` (guards and checks run in one bash process), `bin/*` summaries and arguments ("reminder buy milk, 30"), `keybindings.tsv` and `bindings.local.tsv`, Espanso match files, apps through `focus-or-open`.
- Settings actions (`Providers/System/SettingsActions*.swift`): phrases such as "wifi off" or "volume 30" become rows that run `bin/toggle` or `bin/power` with an argument list, through a `CommandRunning` (tests pass a fake). State comes from `toggle status`, read on each window opening and again by name after each change; a change that did not take is a failure. When macOS refused a permission, the row says which ("Automation not allowed", "Accessibility not allowed") and offers its Privacy & Security pane, otherwise it says "Failed". Rows keep stable ids (`setting.wifi`), which are also their accessibility identifiers, with the state as the accessibility value. `ResultList.update` redraws them in place.
- Settings in `~/.config/grand-line/sight/`: `aliases.tsv` (alias TAB result id, URL or path), `quicklinks.tsv` (keyword TAB title TAB URL with %s), `providers.tsv` (keyword TAB title TAB command TAB global yes/no; the command prints JSON lines). State in `~/Library/Application Support/Sight/`.
- Look and feel (`Views/Style.swift`), as Spotlight: the window is Liquid Glass (`NSGlassEffectView`) on macOS 26 and later, and a behind-window popover material before that, kept active while Sight is not the active app. Every colour is the system's own: label colours for text, the separator colour for lines, `selectedContentBackgroundColor` (the accent) with white text for the selected row, the accent colour for symbols, the scope token and what a held modifier does, matched letters in a heavier weight. So the window follows Light and Dark, the accent and highlight colours and Increase Contrast as macOS sets them, and redraws at once when they change; Reduce Transparency is handled by the material. Corners are continuous: 24 on glass and 14 before it, with a 10 (or 6) point selection inset 6 points from the edge, and the action panel is a menu surface. It materialises from its top edge, fading in while it scales up from 97% and sharpens from a 3 pt blur with a critically damped spring (response 0.26 s), and goes away along the same path, ordering out when the fade ends. An action that types, pastes or presses a menu item in the app in front ends the fade at once. Under Reduce Motion both are short cross-fades. Rows highlight on mouse down and run on mouse up inside them, with a hover fill. The arrow keys glide the highlight with a 0.18 s critically damped spring. The list itself never animates as the query changes. Type comes from system text styles: Title 1 for the query (as Spotlight's), Body for rows, Subheadline for details, key caps and the footer, with monospaced digits where numbers change. Every row, heading and the field start on one 16 pt column.
- Recents and favourites whose app is gone (a URL scheme or bundle id nothing answers, or a program no longer there) are forgotten when Sight starts (`StaleTargets`), so Recent never offers a row that does nothing.
- Actions in the app in front (paste, type, press keys, menu items) run as soon as that app is active: at once when it already is, else on `NSWorkspace.didActivateApplicationNotification`, with a 0.5 s safety limit (`FrontAppWait`).
- Keys: Return, Command+Return (the second action: Show in Finder for files), Option+Return (a copy: the path, URL, answer or name), Command+K actions, Right arrow at the end of the field (into a folder as a path, else the actions), Command+B buffer, Command+1…9, Tab completes, Command+Y preview, Up on an empty field brings back earlier queries, Escape closes the action panel, then clears, then closes. Holding Command or Option shows on the selected row and in the footer what Return does with it. The footer names each key beside a key cap: Open ↵, Show in Finder ⌘↵, Actions ⌘K. Reopening within 90 seconds keeps the last query selected; after that the field is empty and its placeholder shows a different example each time. Quitting a process, moving to the Trash, running typed text and the power rows (whose subtitle says so) ask for a second Return.

### Script commands

Executables in `~/.config/grand-line/sight/scripts/` become commands named after the file, without its extension and in lowercase (one word). The protocol follows rofi's script mode:

1. Typing the name lists the command (also under `>`). Return types "name " and Sight runs the script with no arguments.
2. The script prints one JSON object per line: `{"title": "…", "subtitle": "…", "icon": "SF Symbol name", "value": "…", "keywords": ["…"]}`. Only `title` is required. `value` defaults to the title, and `keywords` are hidden words the row is also found by. Lines that are not JSON objects with a title are skipped. Words typed after the name narrow the rows.
3. Choosing a row runs the script again with the row's value as its only argument. Sight never builds a shell line: the script is run directly with an argument list, from the home folder, with the Grand Line commands on the PATH.
4. The script answers with rows again, which replace the list (the next step), or with a line `{"close": true}`, which closes the window. No rows, a non-zero exit or more than 10 seconds (the script is then stopped) show a message instead.

The rows of the current step are kept until you search for something else. `config/grand-line/sight-scripts/downloads.sh` is an example in two steps (the newest files in Downloads, then Open, Show in Finder or Copy path). It does nothing where it is, so copy it to use it:

```
mkdir -p ~/.config/grand-line/sight/scripts
cp ~/.grand-line/config/grand-line/sight-scripts/downloads.sh ~/.config/grand-line/sight/scripts/
```

## Tests

```
cd apps/finder
swift test
```

Requires Xcode 16 or later (Swift 6) on macOS 15 or later. The stress tests check their time limits fully in a release build:

```
swift test -c release -Xswiftc -enable-testing --filter StressTests
```

## Query language

Terms are combined with AND. Precedence is NOT, then AND, then OR. Keywords are case-insensitive.

| Syntax | Meaning |
| --- | --- |
| `glauc cornea` | Both words, each in the file name or the text |
| `a OR b`, `a \| b` | Either |
| `-draft`, `NOT draft` | Not |
| `(a OR b) c` | Grouping, nested to any depth |
| `"anterior chamber"` | Exact phrase (straight or curly quotes) |
| `endo*` | Prefix |
| `name:x` | File name only |
| `text:x` | Text content only |
| `kind:pdf` | pdf, doc, sheet, slides, image, video, audio, folder, app, code, archive, data, text, markdown, email |
| `ext:docx` | File extension |
| `in:Downloads`, `in:~/Documents` | Folder name anywhere in the path, or an absolute folder |
| `from:trinetx.com` | Downloaded from a host |
| `tag:Urgent`, `author:Smith` | Finder tag, document author |
| `modified:`, `created:`, `opened:` | Dates (below) |
| `size:>5mb` | Size in b, kb, mb or gb (1000-based, like Finder) |
| `pages:<15` | Page count |
| `sort:modified` | Sort by modified, size or name |
| `@weekly` | A saved search |
| `pdf:`, `docx:` | Same as `kind:pdf`, `ext:docx` (a value after the colon is also searched) |
| `drive:`, `local:` | Google Drive only, or the home folder without cloud storage |
| `proj:x` | Same as `in:x` |

Values may be quoted, and `kind:doc,pdf` means any of them.

Comparisons: `>`, `<`, `>=`, `<=`, `=`, or a range `a..b`.

| Date value | Meaning |
| --- | --- |
| `today`, `yesterday` | That day |
| `week`, `month`, `year` | The last 7, 30 or 365 days |
| `30d` | 30 days ago: `<30d` is within the last 30 days, `>30d` is older |
| `2026`, `2026-05`, `2026-05-03` | That year, month or day. `>2026` is after it, `<2026` before it |

## Credits

These projects were read as references. No GPL code was copied.

- [FSearch](https://github.com/cboxdoerfer/fsearch) (GPL-2.0): the idea of an index that stores a name and a parent per entry and searches it in parallel.
- [Nimble Commander](https://github.com/mikekazakov/nimble-commander) (GPL-3.0): fast folder listing with readdir, one operation queue, conflict choices, archives as folders.
- [FuzzyMatch](https://github.com/ordo-one/FuzzyMatch) (Apache-2.0): the character bitmask prefilter and word boundary rules, adapted in `IndexKit/NameFold.swift`.
- [SwiftFileSystemEvents](https://github.com/jgvanwyk/SwiftFileSystemEvents) (CC0 1.0): the FSEvents stream setup, adapted in `IndexKit/FolderWatcher.swift`.
- [Omarchy](https://github.com/basecamp/omarchy) (MIT), `shell/services/AppSearch.js`: ranking in tiers (exact, prefix, word, substring, fuzzy).
- [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher) (MIT): a result with a title, subtitle, score and context actions. [Albert](https://github.com/albertlauncher/albert), [Ulauncher](https://github.com/Ulauncher/Ulauncher) and [Elephant](https://github.com/abenz1267/elephant) (GPL): the ideas of keyword-triggered providers, fallbacks and a provider list. No code was copied.
- Nimble Commander, Double Commander and the Marta and ForkLift manuals: the two-pane keys (Tab, F5, F6) and archives browsed in a pane. Ideas only; no code was copied.
