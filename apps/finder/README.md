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

File operations and the facts Log Pose shows about files.

- `FileOperations`: copy, move, cut and paste, duplicate, rename, new folder and move to Trash, each undoable by reversing it. Conflicts keep both (`name 2`), replace or skip. Nothing is deleted outright: a replaced item and an undone copy go to the Trash. Progress comes through `progress`, an `AsyncStream`. The Trash is injected, so tests use a folder of their own.
- `FolderSize`: folder sizes, cached until `invalidate(_:)` receives watcher changes.
- `VolumeInfo`: mounted volumes with capacity (available includes purgeable space), removable, ejectable and network flags, and `eject`.
- `SelectionSummary`: total size, kinds, oldest and newest dates, common tags and common parent of a selection.
- `Clutter`: finds `.DS_Store` and `._` files and moves them to the Trash in one undoable step.
- `Recents`: Log Pose's own list of opened items in Application Support, newest first, one entry per path.
- `VersionStack`: groups `v01`, `v02`, `final`, `final2`, `copy`, `(1)` and dated versions of a document under the newest.
- `GoogleDrive`: finds `~/Library/CloudStorage/GoogleDrive-*` accounts. Dragging out of a drive copies by default.

## ArchiveKit

Archives open like folders (R26). `Archive.list` reads .zip, .7z, .rar and .tar (also .gz, .bz2 and .xz) with `/usr/bin/bsdtar` into a tree of `ArchiveItem`s. `Archive.extract` copies chosen files or folders out under their own names, and `Archive.preview` extracts one item to a temporary folder for Quick Look. Entries with an absolute path or a `..` part are listed in `rejected` and never extracted.

## ThemeKit

Reads the active theme (`~/.local/state/grand-line/theme` and `~/.grand-line/config/themes/<name>.theme`) into a `Theme` of semantic colours: background, panel, field, line, hairline, text, strong, dim, faint, selection, selectionText, accent, highlight and chip. Keys a file leaves out are derived, and text and dim text are lifted to 4.5:1 contrast where a theme falls short. Graphite and Daylight are built in as fallbacks. `ThemeWatcher` publishes the theme again when it changes. `Color(_:)` and `NSColor(_:)` convert colours for SwiftUI and AppKit.

## LaunchKit

How macOS hands work to the apps. `FileViewerRequest` reads the open-documents and reveal (`misc`/`mvis`) Apple events that Log Pose receives as the default file viewer. `HotkeySetting` says whether Byakugan should register Command+Space (the `TakesCommandSpace` default).

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
