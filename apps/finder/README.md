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
- Names are composed (NFC) before folding, so a decomposed name on disk matches a composed query and the other way round.

## Grand Line Index (the shared index service)

Nexus and Sight keep no index of their own. `Grand Line Index.app` (product `GrandLineIndex`, bundle id `com.grandline.index`) is a background-only agent that launchd runs at login from `Contents/Library/LaunchAgents/com.grandline.index.plist` (registered with `SMAppService.agent` by `GrandLineIndex --register`). It owns one `FileIndex` of the home folder, without `~/Library` except `~/Library/CloudStorage`, and serves it over the XPC Mach service `com.grandline.index`.

- Start: the snapshot in `~/Library/Application Support/Grand Line Index/names.index` loads at once. On the first start the agent adopts the best of Sight's `names.index` and Nexus's `name-index.snapshot` (finished before unfinished, then newer), so nothing is walked again.
- Freshness: the snapshot stores the last FSEvents event and each root's volume UUID. `IndexRecovery.startup` resumes from the event, or walks again (while the old index answers) when the snapshot was unfinished, the volume UUID changed or the event counter is behind. `IndexRecovery.event` maps MustScanSubDirs and RootChanged to a rescan of that folder, dropped events to every root (walked in the background) and a wrapped counter to a full walk. A quiet full sweep runs weekly. The index is saved every five minutes when it changed, and on SIGTERM.
- Clients: `SharedIndexClient` (IndexService) sends `search(text, limit, scope)` and gets one `MatchCodec` buffer back. Each connection has its own narrowing cache. When the agent cannot be reached the client runs `open -g -j -b com.grandline.index` and answers from a copy read from the agent's snapshot (never written), which follows FSEvents if the agent stays away. Apps connect at launch, before their first search, and keep the connection open. A search gives the agent a head start of 0.15 s, then races it against the copy and shows whichever answers first. When the copy wins, the agent's answer is still awaited and `onLateAnswer` lets the app search again, so a file only the agent knows about appears a moment later. Only a failed connection, not a slow one, sends searches to the copy for a while.
- Security: only processes of the same user can look up the Mach service, and each side checks the other's code signature (`setCodeSigningRequirement`): the same Apple team, else the same leaf certificate (the local signing identity), else, for ad-hoc builds, the bundle identifier only.
- The agent is the app that needs Full Disk Access (or Files and Folders); for name search, Nexus and Sight no longer do.

## FileKit

File operations and the facts Nexus shows about files.

- `FileOperations`: copy, move, cut and paste, duplicate, rename, new folder and move to Trash, each undoable by reversing it and redoable after an undo (a new operation ends what Redo can do). Conflicts keep both (`name 2`), replace or skip. Nothing is deleted outright: a replaced item and an undone copy go to the Trash. Progress comes through `progress`, an `AsyncStream`. The Trash is injected, so tests use a folder of their own.
- `FileTaskQueue`: the task engine. Every copy, move, Trash, duplicate, rename, compress and extract runs as a task, one after another, and `events` reports each task as queued, running, finished, failed or cancelled. A cancelled task stops between files, keeps what it did undoable and moves a half-copied item to the Trash. `ConflictResolution` answers taken names per name or for all (`FileOperations.conflicts` lists them before the task starts), `renameItems` renames several items as one undo (names may swap), `putBack` returns items from the Trash in one step, `recordCreated` makes an archive or extracted items undoable, and `history` lists what Undo can reverse.
- `FolderSize`: folder sizes, cached until `invalidate(_:)` receives watcher changes. A measurement stays on the folder's volume, stops when its task is cancelled and keeps to `FolderSizeLimits` (depth, items, seconds); network volumes and cloud folders are left out unless asked for.
- `VolumeInfo`: mounted volumes with capacity (available includes purgeable space), removable, ejectable and network flags, and `eject`.
- `SelectionSummary`: total size, kinds, oldest and newest dates, common tags and common parent of a selection.
- `Clutter`: finds `.DS_Store` and `._` files and moves them to the Trash in one undoable step.
- `Recents`: Nexus's own list of opened items in Application Support, newest first, one entry per path.
- `VersionStack`: groups `v01`, `v02`, `final`, `final2`, `copy`, `(1)` and dated versions of a document under the newest.
- `GoogleDrive`: finds `~/Library/CloudStorage/GoogleDrive-*` accounts. Dragging out of a drive copies by default.

## ArchiveKit

Archives open like folders (R26). `Archive.list` reads .zip, .7z, .rar and .tar (also .gz, .bz2 and .xz) with `/usr/bin/bsdtar` into a tree of `ArchiveItem`s. `Archive.extract` copies chosen files or folders out under their own names, and `Archive.preview` extracts one item to a temporary folder for Quick Look. Entries with an absolute path or a `..` part are listed in `rejected` and never extracted.

Extracted items and previews take the archive's quarantine flag (`Quarantine`), so Gatekeeper still checks what came in a downloaded zip. Previews go to folders of their own in $TMPDIR (`Archive.TemporaryFolder`): Quick Look's `Archive Preview` is emptied when its panel closes and at launch, the preview pane's at launch, and items opened in an app (`Archive Open`) at launch once they are a day old.

## ThemeKit

Reads the active theme (`~/.local/state/grand-line/theme` and `~/.grand-line/config/themes/<name>.theme`) into a `Theme` of semantic colours: background, panel, field, line, hairline, text, strong, dim, faint, selection, selectionText, accent, highlight and chip. Keys a file leaves out are derived, and text and dim text are lifted to 4.5:1 contrast where a theme falls short. Graphite and Daylight are built in as fallbacks. `ThemeWatcher` publishes the theme again when it changes. `Color(_:)` and `NSColor(_:)` convert colours for SwiftUI and AppKit.

`ThemeCatalog` lists the theme files as families (a FAMILY= pair, Graphite and Daylight, or a theme on its own) for the Appearance pane. While `~/.local/state/grand-line/theme-follows-macos` exists, the theme follows macOS: `ThemeWatcher` shows the variant for the system's appearance as soon as it changes (`AppleInterfaceThemeChangedNotification`), and the first app to take `theme-follow.lock` runs `theme mode dark|light` so the terminal and menus follow too. Iceberg does the same in its own `ThemeStore`. `Density` is a theme's optional UI_DENSITY, else each app's `Density` default.

## Settings windows

Nexus and Sight share one Settings window (`SettingsKit`): panes in a sidebar on the left, in the theme's colours, every entry with the accessibility identifier `nexus.settings.<pane>` or `sight.settings.<pane>`. It opens with Cmd+, (in Sight, while the search window is in front), from Sight's menu bar item, from `nexus://settings` and `sight://settings` (a pane can follow: `nexus://settings/search`), and from the main menu's Settings group, which Sight finds as "nexus settings", "sight settings" and "iceberg settings". Every change is saved at once and applies to open windows.

- **Appearance** (both): a card per theme family drawn in its own colours (a Nexus row with a kind tag, a Sight row, Iceberg's pill), dark, light or Follow macOS (`theme set <family>` and `theme mode`, run with argument lists), the icon style the theme sets, and density.
- **Nexus**: General (where new windows open, folders in tabs, what Return does, path and status bars), Sidebar (show, hide and order sections and items; hidden items stay in `sidebar-hidden.json`), Tags (tags in the sidebar, favourite tags as chips in the inspector), Views (the defaults in `view-settings.json`, kind colours), Search (where searches start, content matches, the index's state and Rebuild Index through IndexKit's `IndexStatusProviding`), Advanced (hidden files, extensions, warnings, the configuration folder, Update now: `grandline update --apps-only --notify`). Kept in the `com.grandline.nexus` defaults (`NexusPreferences`).
- **Sight**: General (the launcher shortcut, recorded in `LauncherHotkey`; the menu bar item; open at login; `CloseAfterSettingChange`), Sources (turn result sources off and set the order of their sections, with each prefix), Search (what the index covers, read only, and rows per section), Web (search engines with a keyword and a URL with %s, which of them show as fallbacks, Drive and the assistants), Advanced (reload sources, logs, reset usage history: usage.json goes to the Trash), Update now. Kept in the `com.grandline.sight` defaults (`SightPreferences`); quicklinks.tsv still adds engines.

## LaunchKit

How macOS hands work to the apps. `FileViewerRequest` reads the open-documents and reveal (`misc`/`mvis`) Apple events that Nexus receives as the default file viewer. `HotkeySetting` says whether Sight should register Command+Space (the `TakesCommandSpace` default).

## Nexus

The file browser, built on the libraries above. `BrowserKit` holds everything that can be tested without a screen; `Nexus` is the thin AppKit and SwiftUI app on top.

- Five views per window (Cmd+1 to Cmd+5): icons, list, columns, gallery and panes (1 to 4, Option+Cmd+1 to 4). Tab moves between panes (with one pane it selects the next item by name, as in Finder), F5 copies and F6 moves to the next one; from an archive both extract.
- One view setting everywhere. View > Remember View for This Folder (Ctrl+Cmd+J) stores an exception in `~/Library/Application Support/Nexus/view-settings.json`, never in `.DS_Store`. Dragging rows sets a manual order for that folder.
- Every Finder shortcut keeps its Finder meaning (Cmd+T new tab, Cmd+L make alias, the Go menu on Shift+Cmd, Cmd+Shift+Z redo and the rest); Nexus adds keys only where Finder has none. Return opens, F2 renames, Space is Quick Look, Cmd+Up goes up, and Shift+Cmd+G opens the editable path bar (Tab completes; a bare name finds folders in the name index). Every command is in the menu bar with its shortcut, and the footer shows the keys for where you are. While you type in a field, Cut, Copy, Paste, Select All, Undo and Redo act on the text.
- Cmd+X then Cmd+V moves. Every file operation runs as a task in FileKit's task engine: the toolbar's tasks button (Shift+Cmd+J) lists them with progress and a Stop button, then the undo history, where an older step can be undone with everything after it. A copy or move asks once about each taken name before it starts (Keep Both, Replace, Skip or Stop, with Apply to all), never in the middle. Nothing is deleted: Replace moves the old item to the Trash, a move to another volume sends the original to the Trash once the copy is complete, and a stopped copy, Compress or Extract sends its half-made item there. Every item Nexus sends to the Trash is recorded as it goes, so Put Back (Cmd+Delete in the Trash) works across launches, for a stopped task and after Redo too; items Finder trashed are put back from Finder's own record. Folder sizes (Settings, Advanced) are measured for the folders on screen, on their own disk, and on network or cloud drives only when chosen.
- Search starts in the current folder; chips widen it to home, Drive and the whole Mac. Name matches come from IndexKit at once, content matches from Spotlight. Saved searches live in `~/.config/grand-line/nexus/saved-searches.tsv`, one per line: name, query, scope (`home`, `drive`, `mac` or `folder:/path`), columns (`name,path,modified`), sort (`modified:desc`, `+folders` for Keep Folders on Top) and grouping (`kind`), separated by tabs. Empty fields use the window's own. Files with only name and query are written again in this form, each with the home folder it always searched. They show in the sidebar and run with their own scope, columns and sort.
- The path bar's field is one keyboard target (the omnibar). Shift+Cmd+G opens it as Finder's Go to Folder: a path (Tab completes, the matching child folders list under it) or a folder name from the index. Option+Cmd+G opens it as a filter: plain text narrows the current folder as you type, with a Filter bar under the toolbar until Esc clears it. In either, `?words` searches with the search field's scopes and `>words` runs any menu command. The field's badge reads Go, Filter, Search or Command, so a filter never looks like a search. Cmd+F is still the search field.
- View > Show Contents of Subfolders (Control+Option+Cmd+F, since Finder's Shift+Cmd+F is Recents and Control+Cmd+F is Enter Full Screen) lists the folder and everything below it, with a Where column, from the shared index scoped to the folder (folders the index skips are read from disk), leaving out what Backstage leaves out. It is a scope of the pane, never stored with the folder's view.
- Rename with several items selected (F2 or File > Rename N Items) opens Finder's sheet: Replace Text, Add Text and Format, plus a regular expression and case, with every new name previewed and clashes refused before anything changes. One Undo puts every name back.
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
- Matching (`Matching/`): every provider's titles and keywords go through one `TextMatcher`. A 64-bit mask of the letters in each text is checked first, so texts that lack a letter of the query are skipped without matching. The tier (exact, prefix, word start, substring, fuzzy with the first letter at a word start) comes from IndexKit's rules. Inside a tier, `FuzzyScore` gives fzf's score: 16 per letter, a bonus at a word start, after a delimiter or at a camelCase hump or letter-digit change (twice for the first letter), letters in a row keep the bonus of their run, and gaps cost 3 plus 1 per extra letter. The fuzzy tier places the letters where that score is highest, and only counts when they are close together: each word used is entered at its first letter, letters inside a word skip at most three, and at most two words are skipped between the words used, so "vsc" finds Visual Studio Code but "sleep" does not find a title with s, l, e, e, p scattered through it. Below fuzzy is a typo tier: a word of four letters or more one edit (a letter missed, added, changed, or two swapped) from the start of a word, with the right first letter ("calender" finds Calendar). File names from the index keep the index's tier and are scored the same way; the index's own loose fuzzy hits are dropped unless the matcher finds them tight.
- Rank order is fixed: exact alias, alias prefix, exact and prefix titles, the row learned for exactly what was typed, the other title tiers, the keyword tier, then fzf's score blended with frecency (score + 12 × log2(1 + frecency)). Fallbacks always come last. Learning never lifts a row above an exact or prefix title.
- Frecency (`UsageStore`) follows zoxide: a count that halves every 7 days, times ×4 when last picked within the hour, ×2 within the day, ×½ within the week, ×¼ after that. Picks from exactly this query count four times, from a longer query that starts with it twice. Abbreviations follow LaunchBar: the first row picked after typing "xyz" is what "xyz" stands for next time, and picking another row for "xyz" twice in a row takes it over. Both live in `usage.json` (at most 2,000 results, 2,000 queries with 12 rows each, and 2,000 abbreviations, dropping the weakest or oldest first).
- The top row stays put while you type (`TopRowHold`): once a row is on top for "saf", it stays on top for "safa" unless something in a strictly better tier turns up (a better alias, title or keyword tier, or the row learned for that abbreviation). Slower providers merge in below the selection (`ResultList.merge`) and never replace the top hit. Deleting letters starts over.
- Sections: Top hit, Answers, Apps, System, Grand Line, Windows, Files, Bookmarks, Snippets, Symbols, Web, then Other actions. A short word (three letters or fewer) never puts a calculator answer above an app that starts with it.
- Prefixes, shown as a chip at the start of the field once typed: `/` files (QueryKit, while `/` alone lists the prefixes, `/a/b` and existing folders such as `/Users` are paths, `.` still works), `=` maths, `:` clipboard history (below), `>` commands (Grand Line commands, menu entries and script commands that match, and the text as a shell line), `!` windows (`<` still works), `,` settings (settings you can change and System Settings panes), `?` web, `%` Zen bookmarks, `;` snippets, `$` shows Maccy itself (presses its own ⇧⌘C, so Accessibility is needed), `::` symbols, `'` exact, `@` saved searches (Nexus's `saved-searches.tsv`). Reminders moved from `!` to the word `remind` ("remind call the lab 20m").
- Clipboard history: `:` lists Maccy's history inside Sight, read only. Maccy has no API, so its store (`~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite`) is copied with its write-ahead log and the copy is read. It lists text entries only, pinned first, then newest. Return pastes, ⇧⌘C copies. Without that file the provider is hidden and `:` lists the symbols as before.
- Command+K (`ActionPanel`) lists every action of the selected row and the ones every row of its kind has: for files, Open, Open with…, Show in Nexus, Quick Look, Copy path (⌥⌘C), Copy name (⇧⌘N), Copy file, Add to buffer (⌘B) and Move to Trash, which asks first (a second Return or click) and never deletes. Apps add Show in Nexus and Copy path and name, sums add Copy result, bookmarks and links add Open and Copy URL, and commands add Run and Edit (which opens the script in the text editor). Any of these shortcuts works without opening the panel. Escape closes the panel (or cancels its question) and keeps the query. Actions in it can also be clicked.
- File buffer: Command+B puts the selected file in the buffer (again takes it out), shown as chips under the field. While it holds files, Command+K lists actions for all of them (open, show in Nexus, Quick Look, copy paths, names or files, move, AirDrop, move to the Trash, clear the buffer), and the buffer empties once one runs.
- `selection` lists the same actions for the files selected when the window opened: Nexus's `~/.local/state/grand-line/nexus-selection` when Nexus was in front, else Finder's selection through AppleScript, as `lib/bin-common.sh` `finder_selection` reads it. More words narrow them ("selection trash").
- When nothing matches, the bottom of the list offers the web engines marked as fallbacks in Settings, Web, then Calculate (when there is a digit), Create file "<words>" in Downloads (an empty file, never over an existing one, shown in Nexus) and Run "<words>" in Terminal, which only runs on a second Return.
- File names come from the shared Grand Line Index service: an IndexKit index of the home folder, without `~/Library` (Google Drive in `~/Library/CloudStorage` stays) and with IndexKit's standard exclusions (`.git`, `node_modules`, `.build`, caches, the Trash). Contents and filters go to Spotlight.
- Grand Line sources: `menu.tsv` and `menu.local.tsv` (guards and checks run in one bash process), `bin/*` summaries and arguments ("reminder buy milk, 30"), `keybindings.tsv` and `bindings.local.tsv`, Espanso match files, apps through `focus-or-open`.
- Settings actions (`Providers/System/SettingsActions*.swift`): phrases such as "wifi off" or "volume 30" become rows that run `bin/toggle` or `bin/power` with an argument list, through a `CommandRunning` (tests pass a fake). State comes from `toggle status`, read on each window opening and again by name after each change; a change that did not take is a failure. When macOS refused a permission, the row says which ("Automation not allowed", "Accessibility not allowed") and offers its Privacy & Security pane, otherwise it says "Failed". Rows keep stable ids (`setting.wifi`), which are also their accessibility identifiers, with the state as the accessibility value. `ResultList.update` redraws them in place.
- Settings in `~/.config/grand-line/sight/`: `aliases.tsv` (alias TAB result id, URL or path), `quicklinks.tsv` (keyword TAB title TAB URL with %s), `providers.tsv` (keyword TAB title TAB command TAB global yes/no; the command prints JSON lines). State in `~/Library/Application Support/Sight/`.
- Keys: Return, Command+Return (the second action: Show in Nexus for files), Option+Return (a copy: the path, URL, answer or name), Command+K actions, Right arrow at the end of the field (into a folder as a path, else the actions), Command+B buffer, Command+1…9, Tab completes, Command+Y preview, Up on an empty field brings back earlier queries, Escape closes the action panel, then clears, then closes. Holding Command or Option shows on the selected row and in the footer what Return does with it. The footer reads like "Open ↵ · Show in Nexus ⌘↵ · Actions ⌘K". Reopening within 90 seconds keeps the last query selected; after that the field is empty and its placeholder shows a different example each time. Quitting a process, moving to the Trash, running typed text and the power rows (whose subtitle says so) ask for a second Return.

### Script commands

Executables in `~/.config/grand-line/sight/scripts/` become commands named after the file, without its extension and in lowercase (one word). The protocol follows rofi's script mode:

1. Typing the name lists the command (also under `>`). Return types "name " and Sight runs the script with no arguments.
2. The script prints one JSON object per line: `{"title": "…", "subtitle": "…", "icon": "SF Symbol name", "value": "…", "keywords": ["…"]}`. Only `title` is required. `value` defaults to the title, and `keywords` are hidden words the row is also found by. Lines that are not JSON objects with a title are skipped. Words typed after the name narrow the rows.
3. Choosing a row runs the script again with the row's value as its only argument. Sight never builds a shell line: the script is run directly with an argument list, from the home folder, with the Grand Line commands on the PATH.
4. The script answers with rows again, which replace the list (the next step), or with a line `{"close": true}`, which closes the window. No rows, a non-zero exit or more than 10 seconds (the script is then stopped) show a message instead.

The rows of the current step are kept until you search for something else. `config/grand-line/sight-scripts/downloads.sh` is an example in two steps (the newest files in Downloads, then Open, Show in Nexus or Copy path). It does nothing where it is, so copy it to use it:

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
