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

## Tests

```
cd apps/finder
swift test
```

Requires Xcode 16 or later (Swift 6) on macOS 15 or later.

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
