# Finder

A keyboard-first replacement for Finder and Spotlight. Version 1 searches through Spotlight's existing index.

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

- Ranking: exact (also without the extension), then prefix, word start (after a space, `_`, `-`, `.`, a letter to digit change or a camelCase hump), substring, and fuzzy (letters in order, the first at a word start). Ties go to the more used path (`noteOpened`), then the shallower one.
- Matching ignores case and accents. Highlights come back as UTF-16 ranges of the name.
- `IndexExclusions.standard` skips `.DS_Store`, `._*`, `.git`, `node_modules`, `.build`, caches and similar, and indexes app bundles as one item.
- `FolderWatcher` publishes coalesced `FolderChange`s. `apply(_:)` rescans only the changed folders.
- Search runs one task per core over the arrays, behind a character bitmask that rejects most names at once.

## FileKit

File operations and the facts Nexus shows about files.

- `FileOperations`: copy, move, cut and paste, duplicate, rename, new folder and move to Trash, each undoable by reversing it and redoable after an undo (a new operation ends what Redo can do). Conflicts keep both (`name 2`), replace or skip. Nothing is deleted outright: a replaced item and an undone copy go to the Trash. Progress comes through `progress`, an `AsyncStream`. The Trash is injected, so tests use a folder of their own.
- `FolderSize`: folder sizes, cached until `invalidate(_:)` receives watcher changes.
- `VolumeInfo`: mounted volumes with capacity (available includes purgeable space), removable, ejectable and network flags, and `eject`.
- `SelectionSummary`: total size, kinds, oldest and newest dates, common tags and common parent of a selection.
- `Clutter`: finds `.DS_Store` and `._` files and moves them to the Trash in one undoable step.
- `Recents`: Nexus's own list of opened items in Application Support, newest first, one entry per path.
- `VersionStack`: groups `v01`, `v02`, `final`, `final2`, `copy`, `(1)` and dated versions of a document under the newest.
- `GoogleDrive`: finds `~/Library/CloudStorage/GoogleDrive-*` accounts. Dragging out of a drive copies by default.

## ArchiveKit

Archives open like folders (R26). `Archive.list` reads .zip, .7z, .rar and .tar (also .gz, .bz2 and .xz) with `/usr/bin/bsdtar` into a tree of `ArchiveItem`s. `Archive.extract` copies chosen files or folders out under their own names, and `Archive.preview` extracts one item to a temporary folder for Quick Look. Entries with an absolute path or a `..` part are listed in `rejected` and never extracted.

## ThemeKit

Reads the active theme (`~/.local/state/grand-line/theme` and `~/.grand-line/config/themes/<name>.theme`) into a `Theme` of semantic colours: background, panel, field, line, hairline, text, strong, dim, faint, selection, selectionText, accent, highlight and chip. Keys a file leaves out are derived, and text and dim text are lifted to 4.5:1 contrast where a theme falls short. Graphite and Daylight are built in as fallbacks. `ThemeWatcher` publishes the theme again when it changes. `Color(_:)` and `NSColor(_:)` convert colours for SwiftUI and AppKit.

## LaunchKit

How macOS hands work to the apps. `FileViewerRequest` reads the open-documents and reveal (`misc`/`mvis`) Apple events that Nexus receives as the default file viewer. `HotkeySetting` says whether Sight should register Command+Space (the `TakesCommandSpace` default).

## Nexus

The file browser, built on the libraries above. `BrowserKit` holds everything that can be tested without a screen; `Nexus` is the thin AppKit and SwiftUI app on top.

- Five views per window (Cmd+1 to Cmd+5): icons, list, columns, gallery and panes (1 to 4, Option+Cmd+1 to 4). Tab moves between panes, F5 copies and F6 moves to the next one; from an archive both extract.
- One view setting everywhere. View > Remember View for This Folder (Ctrl+Cmd+J) stores an exception in `~/Library/Application Support/Nexus/view-settings.json`, never in `.DS_Store`. Dragging rows sets a manual order for that folder.
- Every Finder shortcut keeps its Finder meaning (Cmd+T new tab, Cmd+L make alias, the Go menu on Shift+Cmd, Cmd+Shift+Z redo and the rest); Nexus adds keys only where Finder has none. Return opens, F2 renames, Space is Quick Look, Cmd+Up goes up, and Shift+Cmd+G opens the editable path bar (Tab completes; a bare name finds folders in the name index). Every command is in the menu bar with its shortcut, and the footer shows the keys for where you are. While you type in a field, Cut, Copy, Paste, Select All, Undo and Redo act on the text.
- Cmd+X then Cmd+V moves. Operations run in order through FileKit, with progress in the footer, Undo and Redo. Move to Trash records where items came from, so Put Back (Cmd+Delete in the Trash) works across launches.
- Search starts in the current folder; chips widen it to home, Drive and the whole Mac. Name matches come from IndexKit at once, content matches from Spotlight. Saved searches live in `~/.config/grand-line/nexus/saved-searches.tsv` (name TAB query) and show in the sidebar.
- The sidebar lists Places, Active projects, Saved searches and Locations: every mounted volume with its free space and an eject button, each Google Drive, and the Trash. AirDrop sits under Places: clicking it opens the AirDrop window and dropping files on it sends them. File > Add to Sidebar (Ctrl+Cmd+T) adds a folder to Places. Right-click > Remove from Sidebar takes out a place (from `settings.json`); saved searches, built-in items and whole sections are hidden instead (a hidden saved search still works as `@name`), in `~/Library/Application Support/Nexus/sidebar-hidden.json`, and File > Show All in Sidebar (Ctrl+Option+Cmd+S) brings them back. `~/.config/grand-line/nexus/settings.json` sets `places`, `projectFolders` (whose subfolders are the projects) and `projects`.
- Open With lists the apps from `default-apps.tsv` first. Nexus's own tools sit on Control+Option, which Finder leaves free: Ctrl+Option+T opens Ghostty in the folder, Ctrl+Option+A opens Claude Code there, and Ctrl+Option+1 to 5 run `~/.grand-line/bin/transcode` (Tools > Transcode).
- While Nexus is frontmost its selection is in `~/.local/state/grand-line/nexus-selection`, one path per line.

Empty Trash asks Finder to empty it, after a confirmation (Opt+Shift+Cmd+Delete skips the question, as in Finder); Nexus itself never deletes a file.
Finder's Delete Immediately (Opt+Cmd+Delete) is left out on purpose: nothing in Nexus deletes a file without the Trash.
Sort By also has Date Last Opened (Spotlight's last-used date), Date Added and Tags, on Finder's Ctrl+Option+Cmd+3, 4 and 8, and Ctrl+Cmd+Up opens the enclosing folder in a new window.
These keys replace two choices in the original requirements: the editable path bar is on Shift+Cmd+G, not Cmd+L (R5), and Ghostty and Claude Code are on Ctrl+Option+T and A, not Cmd+T and Shift+Cmd+A (R31), so that Finder's own keys keep their meaning.

## Sight

The search window that replaces Spotlight and Alfred. `LauncherKit` holds everything that can be tested without a screen; `Sight` is the AppKit and SwiftUI app on top of it.

- Providers answer a `LaunchQuery`. Instant providers (`InstantProvider`) answer on the keystroke; the others run concurrently, are cancelled by the next key, and merge in below without stealing the selection (`ResultList.merge`).
- Rank order is fixed: exact alias, alias prefix, title tier, keyword tier, then learned frecency (`UsageStore`: per query and overall, halving every 7 days). Fallbacks always come last. Sections: Top hit, Answers, Apps, Grand Line, Windows, System, Bookmarks, Snippets, Symbols, Files, Web.
- Prefixes: `.` files (QueryKit), `=` calculator, `?` web, `%` Zen bookmarks, `<` windows, `!` reminder, `>` shell, `;` snippets, `$` Maccy (presses its own ⇧⌘C, so Accessibility is needed), `:` symbols, `/` prefix list (`~/…` and `/a/b` are paths), `'` exact, `@` saved searches (Nexus's `saved-searches.tsv`).
- File names come from an IndexKit index of the home folder, without `~/Library` (Google Drive in `~/Library/CloudStorage` stays) and with IndexKit's standard exclusions (`.git`, `node_modules`, `.build`, caches, the Trash). Contents and filters go to Spotlight.
- Grand Line sources: `menu.tsv` and `menu.local.tsv` (guards and checks run in one bash process), `bin/*` summaries and arguments ("reminder buy milk, 30"), `keybindings.tsv` and `bindings.local.tsv`, Espanso match files, apps through `focus-or-open`.
- Settings actions (`Providers/System/SettingsActions*.swift`): phrases such as "wifi off" or "volume 30" become rows that run `bin/toggle` or `bin/power` with an argument list, through a `CommandRunning` (tests pass a fake). State comes from `toggle status`, read on each window opening and again by name after each change; a change that did not take is a failure. Rows keep stable ids (`setting.wifi`), which are also their accessibility identifiers, with the state as the accessibility value. `ResultList.update` redraws them in place.
- Settings in `~/.config/grand-line/sight/`: `aliases.tsv` (alias TAB result id, URL or path), `quicklinks.tsv` (keyword TAB title TAB URL with %s), `providers.tsv` (keyword TAB title TAB command TAB global yes/no; the command prints JSON lines). State in `~/Library/Application Support/Sight/`.
- Keys: Return, Command+Return, Command+K actions, Command+1…9, Tab completes, Command+Y preview, Escape clears and then closes. Quitting a process asks for a second Return.

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
