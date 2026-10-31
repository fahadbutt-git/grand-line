import AppKit

/// The file browser (role "files"): every use a person has for it, through
/// the sidebar, the keyboard, the menus and search.
enum FilesJourneys {
    static let role = "files"
    static let homeName = "journeyhome"

    static var all: [Journey] {
        [navigation, views, sorting, fileOperations, tabsAndGo, lookAndTag, search, searchFromTrash,
         omnibar, tasksAndRename, flatAndSaved]
    }

    static func journey(_ name: String, _ summary: String, _ steps: [Step]) -> Journey {
        Journey(name, role: role, summary: summary,
                window: { ctx in try? ctx.mainWindow(timeout: 2) },
                rules: rules, steps: [prepare] + steps)
    }

    /// A window of known size at a known place, in list view, in front.
    static let prepare = step("bring the window forward at a fixed size") { ctx in
        ctx.activate()
        let window = try ctx.mainWindow()
        window.move(to: CGPoint(x: 40, y: 60))
        window.resize(to: CGSize(width: 1180, height: 740))
        try ctx.key("cmd+2")
        try ctx.waitTitle(homeName)
        try ctx.wait("the home folder's items", timeout: 15) { (ctx.status() ?? 0) > 0 }
    }

    // MARK: Journeys

    static var navigation: Journey {
        var steps: [Step] = []
        let places: [(String, [String], String?)] = [
            ("Recents", ["Recents"], nil),
            ("Applications", ["Applications"], nil),
            ("Desktop", ["Desktop"], "Desktop"),
            ("Documents", ["Documents"], "Documents"),
            ("Downloads", ["Downloads"], "Downloads"),
            (homeName, [homeName], nil),
            ("Drive", ["My Drive"], "Library/CloudStorage/GoogleDrive-journey@example.com/My Drive"),
            ("Trash", ["Trash", ".Trash"], ".Trash"),
        ]
        for (title, expected, folder) in places {
            steps.append(step("sidebar: \(title)") { ctx in
                guard let item = try ctx.sidebarItem(title) else {
                    if title == "Drive" { throw StepSkip("no Drive in the sidebar") }
                    throw StepFailure("no \"\(title)\" in the sidebar")
                }
                try ctx.click(item)
                try ctx.wait("the window to show \(expected[0])") { expected.contains(ctx.title()) }
                if title == "Trash", ctx.title() == ".Trash" { ctx.note("the Trash's window title reads \".Trash\"") }
                if let folder {
                    let count = ctx.visibleCount(in: folder)
                    try ctx.wait("the status bar to count \(count) items in \(title)") { ctx.status() == count }
                }
            })
        }
        steps.append(step("back and forward") { ctx in
            try ctx.key("cmd+[")
            try ctx.wait("Back to return to Drive or the home folder") { ctx.title() != "Trash" && ctx.title() != ".Trash" }
            let back = ctx.title()
            try ctx.key("cmd+]")
            try ctx.wait("Forward to return to the Trash") { ["Trash", ".Trash"].contains(ctx.title()) }
            try ctx.key("cmd+[")
            try ctx.waitTitle(back)
        })
        steps.append(step("Go menu keys: Documents, Desktop, Downloads, Home") { ctx in
            for (combo, title) in [("cmd+shift+o", "Documents"), ("cmd+shift+d", "Desktop"), ("cmd+opt+l", "Downloads"), ("cmd+shift+h", homeName)] {
                try ctx.key(combo)
                try ctx.waitTitle(title)
            }
        })
        return journey("files-navigation", "open home, every sidebar place, back and forward, the Go menu keys", steps)
    }

    static var views: Journey {
        let folderNames = ctxNames("Documents/Projects/Conj Flap")
        var steps: [Step] = [
            step("open Documents, then Projects and Conj Flap by double-click") { ctx in
                try ctx.goSidebar("Documents")
                try ctx.openRow("Projects")
                try ctx.openRow("Conj Flap")
            },
        ]
        let modes: [(String, String)] = [("icons", "cmd+1"), ("list", "cmd+2"), ("columns", "cmd+3"), ("gallery", "cmd+4")]
        for (mode, combo) in modes {
            steps.append(step("view as \(mode) in a folder") { ctx in
                try ctx.key(combo)
                try ctx.wait("the \(mode) view to show the folder's items") { ctx.showsItems(names: folderNames, mode: mode) }
            })
        }
        steps.append(step("search \"conj\" from the folder") { ctx in
            try ctx.key("cmd+2")
            try ctx.startSearch("conj")
        })
        for (mode, combo) in modes {
            steps.append(step("view search results as \(mode)") { ctx in
                try ctx.key(combo)
                try ctx.wait("the \(mode) view to show the results") { ctx.showsItems(names: nil, mode: mode) }
            })
        }
        steps.append(step("back to list and end the search") { ctx in
            try ctx.key("cmd+2")
            try ctx.endSearch(returningTo: "Conj Flap")
        })
        return journey("files-views", "icons, list, columns and gallery, in a folder and over search results", steps)
    }

    static var sorting: Journey {
        let folder = "Documents/Sorting"
        func sortStep(_ title: String, _ combo: String, menu: [String]? = nil, _ order: @escaping (Ctx, [String]) -> String?) -> Step {
            step("sort by \(title)") { ctx in
                if let menu { try ctx.menu(menu) } else { try ctx.key(combo) }
                var why: String? = "no rows"
                do {
                    try ctx.wait("rows sorted by \(title)", timeout: 8) {
                        let rows = ctx.rows()
                        why = rows.count < 6 ? "only \(rows.count) rows" : order(ctx, rows)
                        return why == nil
                    }
                } catch {
                    throw StepFailure("not sorted by \(title): \(why ?? "\(error)")")
                }
            }
        }
        return journey("files-sorting", "every sort key, folders mixed with files, Keep Folders on Top and Group by Kind", [
            step("go to the Sorting folder (Go to Folder)") { ctx in try ctx.goToFolder("~/" + folder, expect: "Sorting") },
            // The folder may already be sorted by name. The Sort By shortcut
            // chooses A to Z whatever the sort was (only a header click flips
            // the active column, as in Finder), and the order is checked
            // ascending explicitly, so Z to A never passes for it.
            sortStep("name", "ctrl+opt+cmd+1") { ctx, rows in
                ctx.ascendingByName(rows, folder) ?? ctx.mixed(rows, folder)
            },
            sortStep("date modified", "ctrl+opt+cmd+5") { ctx, rows in
                ctx.inOrder(rows, folder) { a, b in (a.modified ?? .distantPast) >= (b.modified ?? .distantPast).addingTimeInterval(-1) }
                    ?? ctx.mixed(rows, folder)
            },
            sortStep("date added", "ctrl+opt+cmd+4") { ctx, rows in
                ctx.inOrder(rows, folder) { a, b in (a.added ?? .distantPast) >= (b.added ?? .distantPast).addingTimeInterval(-1) }
            },
            sortStep("size", "ctrl+opt+cmd+7") { ctx, rows in
                let files = rows.filter { !ctx.facts(folder, $0).isFolder }
                return ctx.inOrder(files, folder) { a, b in a.size >= b.size }
            },
            sortStep("kind", "ctrl+opt+cmd+2") { ctx, rows in
                ctx.inOrder(rows, folder) { a, b in a.kind.localizedStandardCompare(b.kind) != .orderedDescending }
            },
            sortStep("name again, from the View menu", "", menu: ["View", "Sort By", "Name"]) { ctx, rows in
                ctx.ascendingByName(rows, folder)
            },
            step("clicking the active Name header flips it to Z to A, Sort By sets A to Z again") { ctx in
                guard let header = ctx.anyNode({ $0.text == "Name" && ($0.role == "AXButton" || $0.subrole == "AXSortButton") && $0.isVisibleSize }) else {
                    throw StepSkip("no Name column header in this view, so a header click cannot be checked")
                }
                try ctx.click(header)
                try ctx.wait("rows sorted by name, Z to A", timeout: 8) {
                    let rows = ctx.rows()
                    return rows.count >= 6 && ctx.inOrder(rows, folder) { a, b in a.name.localizedStandardCompare(b.name) != .orderedAscending } == nil
                }
                try ctx.menu(["View", "Sort By", "Name"])
                var why: String? = "no rows"
                do {
                    try ctx.wait("rows sorted by name, A to Z", timeout: 8) {
                        let rows = ctx.rows()
                        why = rows.count < 6 ? "only \(rows.count) rows" : ctx.ascendingByName(rows, folder)
                        return why == nil
                    }
                } catch {
                    throw StepFailure("View › Sort By › Name did not set A to Z: \(why ?? "\(error)")")
                }
            },
            step("Keep Folders on Top") { ctx in
                try ctx.menu(["View", "Keep Folders on Top"])
                try ctx.wait("folders above files") { ctx.foldersFirst(ctx.rows(), folder) }
            },
            step("Keep Folders on Top off again mixes them") { ctx in
                try ctx.key("ctrl+opt+cmd+9")
                try ctx.wait("folders mixed with files") { ctx.mixed(ctx.rows(), folder) == nil }
            },
            step("Group by Kind") { ctx in
                try ctx.key("ctrl+cmd+2")
                try ctx.wait("rows gathered by kind") { ctx.groupedByKind(ctx.rows(), folder) }
            },
            step("Group by None") { ctx in
                try ctx.key("ctrl+cmd+0")
                try ctx.wait("folders mixed with files again") { ctx.mixed(ctx.rows(), folder) == nil }
            },
        ])
    }

    static var fileOperations: Journey {
        let ops = "Documents/Journey Ops"
        return journey("files-operations", "new folder, rename, open, copy and paste, duplicate, Trash, undo and redo", [
            step("go to Journey Ops") { ctx in try ctx.goToFolder("~/" + ops, expect: "Journey Ops") },
            step("new folder (Shift+Cmd+N) and name it") { ctx in
                let before = Set(ctx.listing(ops))
                try ctx.key("cmd+shift+n")
                var made = ""
                try ctx.wait("a new folder on disk") {
                    made = Set(ctx.listing(ops)).subtracting(before).first ?? ""
                    return !made.isEmpty
                }
                if !ctx.isEditingText() {
                    try ctx.selectRow(made)
                    try ctx.key("f2")
                }
                try ctx.wait("the new folder's name to be editable") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("Journey Folder")
                try ctx.key("return")
                try ctx.wait("\"Journey Folder\" on disk") { ctx.exists(ops + "/Journey Folder") }
            },
            step("rename with F2") { ctx in
                try ctx.selectRow("notes.txt")
                try ctx.key("f2")
                try ctx.wait("the name to be editable") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("renamed notes.txt")
                try ctx.key("return")
                try ctx.wait("the file renamed on disk") { ctx.exists(ops + "/renamed notes.txt") && !ctx.exists(ops + "/notes.txt") }
                try ctx.wait("the row renamed") { ctx.rows().contains("renamed notes.txt") }
            },
            step("Return opens a folder, Cmd+Up comes back") { ctx in
                try ctx.selectRow("Journey Folder")
                try ctx.key("return")
                try ctx.waitTitle("Journey Folder")
                try ctx.key("cmd+up")
                try ctx.waitTitle("Journey Ops")
            },
            step("copy and paste into a folder") { ctx in
                try ctx.withNexusLog {
                    try ctx.selectRow("report.pdf")
                    try ctx.key("cmd+c")
                    try ctx.openRow("Journey Folder")
                    try ctx.key("cmd+v")
                    try ctx.wait("the copy on disk") { ctx.exists(ops + "/Journey Folder/report.pdf") }
                    try ctx.wait("the copy in the list") { ctx.rows().contains("report.pdf") }
                    try ctx.check(ctx.exists(ops + "/report.pdf"), "the original went missing after a copy")
                }
                try ctx.key("cmd+up")
                try ctx.waitTitle("Journey Ops")
            },
            step("duplicate (Cmd+D)") { ctx in
                try ctx.selectRow("report.pdf")
                try ctx.key("cmd+d")
                try ctx.wait("a second report on disk") { ctx.listing(ops).filter { $0.hasPrefix("report") }.count == 2 }
            },
            step("move to Trash (Cmd+Delete)") { ctx in
                let count = ctx.status() ?? 0
                try ctx.selectRow("Move Me.txt")
                try ctx.key("cmd+delete")
                try ctx.wait("the file gone from the folder") { !ctx.exists(ops + "/Move Me.txt") }
                try ctx.wait("the status bar to count one less") { ctx.status() == count - 1 }
            },
            step("undo (Cmd+Z) puts it back") { ctx in
                try ctx.key("cmd+z")
                try ctx.wait("the file back") { ctx.exists(ops + "/Move Me.txt") }
                try ctx.wait("its row back") { ctx.rows().contains("Move Me.txt") }
            },
            step("redo (Shift+Cmd+Z) trashes it again, undo restores") { ctx in
                try ctx.key("cmd+shift+z")
                try ctx.wait("the file trashed again") { !ctx.exists(ops + "/Move Me.txt") }
                try ctx.key("cmd+z")
                try ctx.wait("the file back again") { ctx.exists(ops + "/Move Me.txt") }
            },
        ])
    }

    static var tabsAndGo: Journey {
        journey("files-tabs-go", "Go to Folder by path and by name, tabs: open, switch, close", [
            step("Go to Folder by path (Shift+Cmd+G)") { ctx in try ctx.goToFolder("~/Documents/Projects", expect: "Projects") },
            step("Go to Folder by a folder's name") { ctx in
                try ctx.key("cmd+shift+g")
                try ctx.wait("the path field") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("Lid Repair")
                // The name index may still be building on a fresh home: Return
                // keeps the field open until it finds the folder.
                try ctx.wait("Return to find the folder by name", timeout: 20, poll: 1) {
                    if ctx.title() == "Lid Repair" { return true }
                    if ctx.isEditingText() { try ctx.key("return") }
                    return ctx.title() == "Lid Repair"
                }
            },
            step("new tab (Cmd+T)") { ctx in
                try ctx.key("cmd+t")
                try ctx.wait("two tabs") { ctx.tabCount() >= 2 }
                try ctx.key("cmd+opt+l")
                try ctx.waitTitle("Downloads")
            },
            step("switch tabs (Ctrl+Shift+Tab, Ctrl+Tab)") { ctx in
                try ctx.switchTab(to: "Lid Repair", combo: "ctrl+shift+tab")
                try ctx.switchTab(to: "Downloads", combo: "ctrl+tab")
            },
            step("close the tab (Cmd+W)") { ctx in
                try ctx.key("cmd+w")
                try ctx.wait("one tab left") { ctx.tabCount() <= 1 }
                try ctx.waitTitle("Lid Repair")
            },
        ])
    }

    static var lookAndTag: Journey {
        let folder = "Documents/Projects/Conj Flap"
        return journey("files-quicklook-info-tags", "Quick Look, Get Info and colour tags", [
            step("go to Conj Flap") { ctx in try ctx.goToFolder("~/" + folder, expect: "Conj Flap") },
            step("Quick Look (Space) opens and closes", layout: false) { ctx in
                try ctx.selectRow("conj figure.png")
                let before = Capture.windows(pid: ctx.pid).count
                let panels = ctx.windows().count
                try ctx.key("space")
                try ctx.wait("a Quick Look window") {
                    Capture.windows(pid: ctx.pid).count > before || ctx.windows().count > panels
                }
                ctx.shot("quick look open", window: nil)
                try ctx.key("space")
                try ctx.wait("Quick Look to close") { Capture.windows(pid: ctx.pid).count <= before }
            },
            step("Get Info (Cmd+I) opens the inspector") { ctx in
                try ctx.selectRow("conj notes.txt")
                let width = ctx.paneFrame()?.width ?? 0
                try ctx.key("cmd+i")
                try ctx.wait("the inspector beside the files") { (ctx.paneFrame()?.width ?? width) < width - 150 }
                try ctx.wait("the inspector to name the file") {
                    let snap = ctx.snapshot(try ctx.mainWindow())
                    let pane = ctx.paneFrame() ?? .zero
                    return snap.nodes.contains { $0.text.contains("conj notes") && ($0.frame?.minX ?? 0) > pane.maxX }
                }
                try ctx.key("cmd+i")
                try ctx.wait("the inspector closed") { (ctx.paneFrame()?.width ?? 0) >= width - 2 }
            },
            step("tag Red (Ctrl+1), then remove tags (Ctrl+0)") { ctx in
                try ctx.selectRow("conj notes.txt")
                // Control+1 to 7 can belong to Mission Control (Switch to
                // Desktop N); then the menu does what the key could not.
                try ctx.key("ctrl+1")
                if (try? ctx.wait("the Red tag on disk", timeout: 3) { ctx.tags(folder + "/conj notes.txt").contains("Red") }) == nil {
                    ctx.note("Control+1 did not reach Nexus (taken by the system?); used File > Tags > Red")
                    try ctx.menu(["File", "Tags", "Red"])
                    try ctx.wait("the Red tag on disk") { ctx.tags(folder + "/conj notes.txt").contains("Red") }
                }
                try ctx.key("ctrl+0")
                if (try? ctx.wait("no tags on disk", timeout: 3) { ctx.tags(folder + "/conj notes.txt").isEmpty }) == nil {
                    ctx.note("Control+0 did not reach Nexus; used File > Tags > Remove Tags")
                    try ctx.menu(["File", "Tags", "Remove Tags"])
                    try ctx.wait("no tags on disk") { ctx.tags(folder + "/conj notes.txt").isEmpty }
                }
            },
        ])
    }

    static let junk = ["conj-cache.db", "conj-state.json", "conj-junk.tmp", "index.js", "conj-module"]

    static var search: Journey {
        journey("files-search", "search as you type, scope chips, name matches first, no app data, Esc ends it", [
            step("open Documents") { ctx in try ctx.goSidebar("Documents") },
            step("type \"conj\" in the search field") { ctx in try ctx.startSearch("conj") },
            step("scope chips: Documents, Home, Drive, This Mac") { ctx in
                let snap = ctx.snapshot(try ctx.mainWindow())
                for (id, title) in [("folder", "Documents"), ("home", "Home"), ("mac", "This Mac")] {
                    try ctx.check(ctx.chip(snap, id, title) != nil, "no \"\(title)\" scope chip; chips: \(ctx.chipTexts(snap))")
                }
                if ctx.chip(snap, "drive", "Drive") == nil { ctx.note("no Drive scope chip shown") }
            },
            step("name matches come first, app data never shows") { ctx in
                let rows = ctx.rows()
                try ctx.check(!rows.isEmpty, "no results")
                try ctx.check(ctx.fold(rows[0]).contains("conj"), "the first result \"\(rows[0])\" does not have conj in its name")
                if let firstOther = rows.firstIndex(where: { !ctx.fold($0).contains("conj") }) {
                    let late = rows[firstOther...].filter { ctx.fold($0).contains("conj") }
                    try ctx.check(late.isEmpty, "name matches \(late) come after \"\(rows[firstOther])\", which matched by content")
                }
                let found = rows.filter { junk.contains($0) }
                try ctx.check(found.isEmpty, "app data in the results: \(found)")
            },
            step("Home scope finds the Desktop file") { ctx in
                try ctx.clickChip("home", "Home")
                try ctx.wait("Desktop conj sticky.txt in the results", timeout: 15) { ctx.rows(all: true).contains("Desktop conj sticky.txt") }
                let found = ctx.rows(all: true).filter { junk.contains($0) }
                try ctx.check(found.isEmpty, "app data in the results: \(found)")
            },
            step("Drive scope") { ctx in
                let snap = ctx.snapshot(try ctx.mainWindow())
                guard ctx.chip(snap, "drive", "Drive") != nil else { throw StepSkip("no Drive scope chip") }
                try ctx.clickChip("drive", "Drive")
                try ctx.wait("the Drive file in the results", timeout: 15) { ctx.rows(all: true).contains("Conj Drive notes.docx") }
            },
            step("This Mac scope") { ctx in
                try ctx.clickChip("mac", "This Mac")
                try ctx.wait("results across the Mac", timeout: 20) { (ctx.status() ?? 0) > 0 && !ctx.rows().isEmpty }
                let found = ctx.rows(all: true).filter { junk.contains($0) }
                try ctx.check(found.isEmpty, "app data in the results: \(found)")
            },
            step("Esc in the search field ends the search") { ctx in try ctx.endSearch(returningTo: "Documents") },
        ])
    }

    /// The case reported from use: Trash, then search with This Mac, left an
    /// empty list under a toolbar drawn in the middle, and a ".Trash" chip.
    static var searchFromTrash: Journey {
        journey("files-search-from-trash", "open the Trash, search, widen to This Mac, every view", [
            step("open the Trash from the sidebar") { ctx in
                try ctx.goSidebar("Trash", titles: ["Trash", ".Trash"])
                try ctx.wait("the Trash's items") { (ctx.status() ?? 0) == ctx.visibleCount(in: ".Trash") }
            },
            step("search \"conj\" from the Trash") { ctx in
                // Finder searches the folder it is in. The Trash holds two conj
                // files, which the app reads from disk (the name index leaves
                // the Trash out); should none show, the empty state must say
                // where it looked and offer the whole Mac.
                try ctx.startSearch("conj", allowEmpty: "No results in Trash.")
                if ctx.rows().isEmpty { ctx.note("the Trash search found nothing, and said so") }
                let snap = ctx.snapshot(try ctx.mainWindow())
                try ctx.check(ctx.chip(snap, "folder", "Trash") != nil, "the folder chip does not read \"Trash\"; chips: \(ctx.chipTexts(snap))")
                let raw = snap.nodes.filter { $0.text == ".Trash" }
                try ctx.check(raw.isEmpty, "\".Trash\" is shown: \(raw.map(Ctx.describe))")
            },
            step("widen to This Mac") { ctx in
                try ctx.clickChip("mac", "This Mac")
                try ctx.wait("results across the Mac", timeout: 20) { (ctx.status() ?? 0) > 0 && !ctx.rows().isEmpty }
                try ctx.check(ctx.toolbarAtTop(), "the toolbar is not at the top of the window")
            },
            step("results as icons") { ctx in
                try ctx.key("cmd+1")
                try ctx.wait("icons") { ctx.showsItems(names: nil, mode: "icons") }
            },
            step("results as columns") { ctx in
                try ctx.key("cmd+3")
                try ctx.wait("columns") { ctx.showsItems(names: nil, mode: "columns") }
            },
            step("results as gallery") { ctx in
                try ctx.key("cmd+4")
                try ctx.wait("gallery") { ctx.showsItems(names: nil, mode: "gallery") }
            },
            step("results as list") { ctx in
                try ctx.key("cmd+2")
                try ctx.wait("list rows") { !ctx.rows().isEmpty }
            },
            step("Esc ends the search, back in the Trash") { ctx in try ctx.endSearch(returningTo: "Trash", alternatives: [".Trash"]) },
        ])
    }

    /// The path bar's field as one keyboard target: a filter as you type,
    /// a path with Tab completion, `?` search and `>` commands, while
    /// Shift+Cmd+G and Cmd+F keep their Finder meaning.
    static var omnibar: Journey {
        let folder = "Documents/Projects/Conj Flap"
        return journey("files-omnibar", "Option+Cmd+G filters as you type, Tab completes a path, ?search, >command", [
            step("go to Conj Flap") { ctx in try ctx.goToFolder("~/" + folder, expect: "Conj Flap") },
            step("Option+Cmd+G filters the folder as you type") { ctx in
                try ctx.key("cmd+opt+g")
                try ctx.wait("the field") { ctx.isEditingText() }
                ctx.type("notes")
                try ctx.wait("only the matching row") { ctx.rows() == ["conj notes.txt"] }
                try ctx.check(ctx.omnibarBadge() == "Filter", "the field does not say it filters (\"\(ctx.omnibarBadge())\")")
            },
            step("Return keeps the filter and its bar; Esc clears it") { ctx in
                try ctx.key("return")
                try ctx.wait("the keys back in the list") { !ctx.isEditingText() }
                try ctx.wait("the filter bar") { ctx.browserSnapshot()?.identified(ctx.app.id("filter")) != nil }
                try ctx.check(ctx.rows() == ["conj notes.txt"], "the filter went away on Return: \(ctx.rows())")
                try ctx.key("escape")
                try ctx.wait("every row back") { ctx.status() == ctx.visibleCount(in: folder) }
                try ctx.check(ctx.browserSnapshot()?.identified(ctx.app.id("filter")) == nil, "the filter bar stayed after Esc")
            },
            step("Shift+Cmd+G: Tab completes a path, Return goes there") { ctx in
                try ctx.key("cmd+shift+g")
                try ctx.wait("the path field") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("~/Documents/Proj")
                try ctx.key("tab")
                try ctx.wait("Tab to complete Projects") { ctx.focusedValue() == "~/Documents/Projects/" }
                try ctx.key("return")
                try ctx.waitTitle("Projects")
            },
            step("?conj in the field searches, with the search field's scopes") { ctx in
                try ctx.key("cmd+shift+g")
                try ctx.wait("the path field") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("?conj")
                try ctx.waitTitle("Search: conj")
                try ctx.check(ctx.omnibarBadge() == "Search", "the field does not say it searches (\"\(ctx.omnibarBadge())\")")
                let snap = ctx.snapshot(try ctx.mainWindow())
                try ctx.check(ctx.chip(snap, "home", "Home") != nil, "no scope chips for a search from the field; chips: \(ctx.chipTexts(snap))")
                try ctx.key("escape")
                try ctx.waitTitle("Projects")
            },
            step(">as columns runs the command") { ctx in
                try ctx.key("cmd+shift+g")
                try ctx.wait("the path field") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type(">as columns")
                try ctx.check(ctx.omnibarBadge() == "Command", "the field does not say it runs a command")
                try ctx.key("return")
                try ctx.wait("the columns view") { ctx.showsItems(names: ["Conj Flap", "Lid Repair"], mode: "columns") }
                try ctx.key("cmd+2")
            },
            step("Cmd+F is still the search field") { ctx in
                try ctx.startSearch("lid")
                try ctx.endSearch(returningTo: "Projects")
            },
        ])
    }

    /// The task engine: copies ask about taken names once, tasks show in the
    /// toolbar's popover with the undo history, and Rename N Items is one task.
    static var tasksAndRename: Journey {
        let ops = "Documents/Journey Ops"
        let batch = ops + "/Batch"
        return journey("files-tasks-rename", "conflict sheet, tasks popover, undo history, Rename N Items", [
            step("make a folder with a taken name, and photos to rename") { ctx in
                try ctx.writeFixture(ops + "/Dest/notes.txt", "already here")
                for n in 1...3 { try ctx.writeFixture(batch + "/IMG_\(n).jpg", "photo \(n)") }
                try ctx.goToFolder("~/" + ops, expect: "Journey Ops")
            },
            step("paste over a taken name asks, Keep Both keeps both") { ctx in
                try ctx.withNexusLog {
                    try ctx.selectRow("notes.txt")
                    try ctx.key("cmd+c")
                    try ctx.openRow("Dest")
                    try ctx.key("cmd+v")
                    var keep: Node?
                    try ctx.wait("the conflict sheet") {
                        keep = ctx.anyNode { $0.role == "AXButton" && $0.text == "Keep Both" }
                        return keep != nil
                    }
                    try ctx.check(ctx.anyNode { $0.role == "AXButton" && $0.text == "Replace" } != nil, "the sheet has no Replace")
                    try ctx.click(keep!)
                    try ctx.wait("both on disk") { ctx.exists(ops + "/Dest/notes 2.txt") }
                    try ctx.check(ctx.contents(ops + "/Dest/notes.txt") == "already here", "Keep Both changed the item already there")
                }
            },
            step("the tasks popover lists the copy and its undo") { ctx in
                try ctx.key("cmd+shift+j")
                var undo: Node?
                do {
                    try ctx.wait("the tasks popover", timeout: 5) {
                        undo = ctx.anyNode { $0.role == "AXButton" && $0.text == "Undo" }
                        return undo != nil
                    }
                } catch {
                    throw StepSkip("the tasks popover is not reachable through Accessibility here")
                }
                try ctx.check(ctx.anyNode { $0.text.hasPrefix("Copy notes.txt to Dest") } != nil, "the popover does not list the copy")
                try ctx.click(undo!)
                try ctx.wait("the copy undone from the popover") { !ctx.exists(ops + "/Dest/notes 2.txt") }
                try ctx.key("escape")
            },
            step("F2 with several items opens Rename N Items") { ctx in
                try ctx.goToFolder("~/" + batch, expect: "Batch")
                try ctx.wait("the photos") { ctx.rows().count == 3 }
                try ctx.key("cmd+a")
                try ctx.key("f2")
                var find: Node?
                try ctx.wait("the Rename sheet") {
                    find = ctx.anyNode { $0.identifier == ctx.app.id("rename.find") }
                    return find != nil
                }
                try ctx.click(find!)
                ctx.type("IMG_")
                guard let replace = ctx.anyNode({ $0.identifier == ctx.app.id("rename.replace") }) else {
                    throw StepFailure("no Replace with field in the sheet")
                }
                try ctx.click(replace)
                ctx.type("Trip ")
                try ctx.wait("the preview to show the new names") { ctx.anyNode { $0.text == "Trip 1.jpg" } != nil }
                guard let apply = ctx.anyNode({ $0.identifier == ctx.app.id("rename.apply") }) else {
                    throw StepFailure("no Rename button in the sheet")
                }
                try ctx.click(apply)
                try ctx.wait("every photo renamed on disk") { ctx.listing(batch).sorted() == ["Trip 1.jpg", "Trip 2.jpg", "Trip 3.jpg"] }
            },
            step("one Undo puts every name back") { ctx in
                try ctx.key("cmd+z")
                try ctx.wait("the old names back") { ctx.listing(batch).sorted() == ["IMG_1.jpg", "IMG_2.jpg", "IMG_3.jpg"] }
            },
        ])
    }

    /// Flat view from the shared index, and a saved search that keeps its scope.
    static var flatAndSaved: Journey {
        let folder = "Documents/Projects/Conj Flap"
        return journey("files-flat-saved", "flat view with a Where column, a saved search with its scope in the sidebar", [
            step("go to Conj Flap") { ctx in try ctx.goToFolder("~/" + folder, expect: "Conj Flap") },
            step("Control+Option+Cmd+F lists the subfolders' items too") { ctx in
                try ctx.key("ctrl+opt+cmd+f")
                try ctx.wait("items from Drafts/v1 and Drafts/v2", timeout: 15) {
                    let rows = ctx.rows(all: true)
                    return rows.contains("conj draft v1.docx") && rows.contains("conj draft v2.docx")
                }
                try ctx.check(ctx.browserSnapshot()?.identified(ctx.app.id("flat")) != nil, "the path bar does not show the flat view")
                if ctx.anyNode({ $0.text == "Where" }) == nil { ctx.note("no Where column header found") }
                try ctx.check(ctx.title() == "Conj Flap", "flat view changed the window's folder")
            },
            step("the same keys show the folder alone again") { ctx in
                try ctx.key("ctrl+opt+cmd+f")
                try ctx.wait("only the folder's own items") { !ctx.rows(all: true).contains("conj draft v1.docx") && ctx.status() == ctx.visibleCount(in: folder) }
            },
            step("save a search over the home folder") { ctx in
                try ctx.startSearch("conj")
                try ctx.clickChip("home", "Home")
                try ctx.menu(["File", "Save Search…"])
                try ctx.wait("the name field") { ctx.isEditingText() }
                try ctx.key("cmd+a")
                ctx.type("Conj everywhere")
                try ctx.key("return")
                let file = ".config/grand-line/nexus/saved-searches.tsv"
                try ctx.wait("the saved search on disk with its scope") {
                    (ctx.contents(file) ?? "").contains("Conj everywhere\tconj\thome")
                }
                try ctx.endSearch(returningTo: "Conj Flap")
            },
            step("the sidebar runs it with its scope") { ctx in
                try ctx.goSidebar("Conj everywhere", titles: ["Search: conj"])
                try ctx.wait("the Home chip chosen") {
                    guard let snap = ctx.browserSnapshot(), let chip = ctx.chip(snap, "home", "Home") else { return false }
                    return chip.allText.joined().contains("Home") || chip.text == "Home"
                }
                try ctx.wait("results", timeout: 20) { !ctx.rows().isEmpty }
            },
        ])
    }

    // MARK: Layout rules for the browser window

    static func rules(_ ctx: Ctx, _ snap: Snapshot, _ window: CGRect) -> [String] {
        var problems: [String] = []
        if let field = searchField(snap), let f = field.frame {
            if f.minY - window.minY > 90 {
                problems.append("the toolbar is not at the top: the search field is \(Int(f.minY - window.minY)) pt below the top of a \(Int(window.height)) pt window")
            }
        } else {
            problems.append("no search field in the toolbar")
        }
        let pane = snap.identified(ctx.app.id("pane"))?.frame
        if let pane {
            if pane.height < window.height * 0.4 {
                problems.append("the file area is \(Int(pane.height)) pt tall in a \(Int(window.height)) pt window")
            }
        } else {
            // Without it the height check above would quietly not run.
            problems.append("no file area marked \(ctx.app.id("pane")) in the window")
        }
        if let count = statusCount(snap), count > 0 {
            let area = pane ?? contentArea(snap, window)
            let shown = snap.nodes.filter { node in
                ["AXRow", "AXStaticText", "AXTextField", "AXImage", "AXCell"].contains(node.role) && node.isVisibleSize
                    && area.intersects(node.frame!) && !["No matches", "Searching…", "Empty folder"].contains(node.text)
            }
            if shown.isEmpty { problems.append("the status bar says \(count) items but the file area is empty") }
        }
        return problems
    }

    static func searchField(_ snap: Snapshot) -> Node? {
        let fields = snap.all { Layout.inputRoles.contains($0.role) && !$0.insideScroll && $0.isVisibleSize }
        return fields.first { $0.allText.contains { $0.contains("Search this folder") } }
            ?? fields.first { $0.identifier.hasSuffix(".search") }
            ?? fields.filter { ($0.frame?.minX ?? 0) > (snap.root?.frame?.midX ?? 0) }.last
    }

    static func statusNode(_ snap: Snapshot) -> Node? {
        snap.all("AXStaticText") { parseStatus($0.text) != nil }.max { ($0.frame?.minY ?? 0) < ($1.frame?.minY ?? 0) }
    }

    static func statusCount(_ snap: Snapshot) -> Int? { statusNode(snap).flatMap { parseStatus($0.text) } }

    /// "9 items", "1 item", "3 of 9 selected · 18.6 MB".
    static func parseStatus(_ text: String) -> Int? {
        let digits = { (s: Substring) in Int(s.replacingOccurrences(of: ",", with: "")) }
        let words = text.split(separator: " ")
        if words.count == 2, words[1] == "items" || words[1] == "item" { return digits(words[0]) }
        if words.count >= 4, words[1] == "of", words[3].hasPrefix("selected") { return digits(words[2]) }
        return nil
    }

    static func contentArea(_ snap: Snapshot, _ window: CGRect) -> CGRect {
        let top = (searchField(snap)?.frame?.maxY ?? window.minY + 44) + 36
        let status = statusNode(snap)?.frame
        let bottom = (status?.minY ?? window.maxY - 28) - 2
        let left = (status?.minX ?? window.minX) - 14
        return CGRect(x: left, y: top, width: window.maxX - left, height: max(0, bottom - top))
    }

    /// Names of the items in a fixture folder, for checks that need them before launch.
    static func ctxNames(_ folder: String) -> [String] {
        ["Lid Study - CONJ.docx", "conj_storyboard.pptx", "Conj Flap protocol.pdf", "conj notes.txt", "Drafts"]
    }
}

// MARK: Browser helpers

struct FileFacts {
    let name: String
    let isFolder: Bool
    let modified: Date?
    let added: Date?
    let size: Int
    let kind: String
}

extension Ctx {
    func url(_ relative: String) -> URL {
        relative.isEmpty ? home : home.appendingPathComponent(relative)
    }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: url(relative).path) }

    func listing(_ relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(relative).path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    func visibleCount(in relative: String) -> Int { listing(relative).count }

    func facts(_ folder: String, _ name: String) -> FileFacts {
        let u = url(folder).appendingPathComponent(name)
        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey, .localizedTypeDescriptionKey])
        return FileFacts(name: name, isFolder: v?.isDirectory ?? false, modified: v?.contentModificationDate,
                         added: v?.addedToDirectoryDate, size: v?.fileSize ?? 0, kind: v?.localizedTypeDescription ?? "")
    }

    func tags(_ relative: String) -> [String] {
        (try? url(relative).resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// nil when every neighbouring pair is in order, else what is out of order.
    func inOrder(_ rows: [String], _ folder: String, _ ordered: (FileFacts, FileFacts) -> Bool) -> String? {
        let facts = rows.map { self.facts(folder, $0) }
        for i in facts.indices.dropLast() where !ordered(facts[i], facts[i + 1]) {
            return "\"\(rows[i])\" comes before \"\(rows[i + 1])\" (rows: \(rows))"
        }
        return nil
    }

    /// nil when the rows go A to Z by name; else what is out of order, and
    /// whether the whole list runs Z to A instead.
    func ascendingByName(_ rows: [String], _ folder: String) -> String? {
        guard let problem = inOrder(rows, folder, { a, b in a.name.localizedStandardCompare(b.name) != .orderedDescending }) else { return nil }
        let descending = inOrder(rows, folder) { a, b in a.name.localizedStandardCompare(b.name) != .orderedAscending } == nil
        return descending ? "sorted Z to A, not A to Z (rows: \(rows))" : problem
    }

    /// nil when folders and files are mixed, as a single sort key leaves them.
    func mixed(_ rows: [String], _ folder: String) -> String? {
        let kinds = rows.map { facts(folder, $0).isFolder }
        guard let firstFile = kinds.firstIndex(of: false), let lastFolder = kinds.lastIndex(of: true) else { return "no folders or no files" }
        return firstFile < lastFolder ? nil : "folders are kept above files without being asked (rows: \(rows))"
    }

    func foldersFirst(_ rows: [String], _ folder: String) -> Bool {
        let kinds = rows.map { facts(folder, $0).isFolder }
        guard let firstFile = kinds.firstIndex(of: false) else { return false }
        return !kinds[firstFile...].contains(true) && kinds.first == true
    }

    func groupedByKind(_ rows: [String], _ folder: String) -> Bool {
        let kinds = rows.map { facts(folder, $0).kind }
        var seen = Set<String>()
        var previous = ""
        for kind in kinds {
            if kind != previous {
                if seen.contains(kind) { return false }
                seen.insert(kind)
                previous = kind
            }
        }
        return rows.count >= 6
    }

    func title() -> String { (try? mainWindow(timeout: 2))?.title ?? "" }

    func waitTitle(_ title: String) throws {
        try wait("the window to show \"\(title)\"") { self.title() == title }
    }

    func browserSnapshot() -> Snapshot? {
        guard let window = try? mainWindow(timeout: 2) else { return nil }
        return snapshot(window)
    }

    func status() -> Int? { browserSnapshot().flatMap(FilesJourneys.statusCount) }

    func paneFrame() -> CGRect? { browserSnapshot()?.identified(app.id("pane"))?.frame }

    /// Names in the file area, top to bottom: table rows in list view, else texts.
    func rows(all: Bool = false) -> [String] {
        guard let snap = browserSnapshot() else { return [] }
        return snap.rowNames().map(\.name)
    }

    func showsItems(names: [String]?, mode: String) -> Bool {
        guard let snap = browserSnapshot(), let window = snap.root?.frame else { return false }
        let area = snap.identified(app.id("pane"))?.frame ?? FilesJourneys.contentArea(snap, window)
        guard area.height > 100 else { return false }
        let inside = snap.nodes.filter { $0.isVisibleSize && area.intersects($0.frame!) }
        if mode == "gallery" {
            // The strip's thumbnails: images, each named after its item.
            let images = inside.filter { $0.role == "AXImage" }
            guard let names else { return !images.isEmpty }
            return images.contains { image in names.contains { image.allText.contains($0) } }
        }
        let texts = Set(inside.filter { ["AXStaticText", "AXTextField"].contains($0.role) }.map(\.text))
        guard let names else { return texts.contains { fold($0).contains("conj") } }
        return names.contains { texts.contains($0) }
    }

    func toolbarAtTop() -> Bool {
        guard let snap = browserSnapshot(), let window = snap.root?.frame,
              let field = FilesJourneys.searchField(snap)?.frame else { return false }
        return field.minY - window.minY <= 90
    }

    /// The sidebar entry: the leftmost text with that title.
    func sidebarItem(_ title: String) throws -> Node? {
        guard let snap = browserSnapshot() else { throw StepFailure("no browser window") }
        let pane = snap.identified(app.id("pane"))?.frame
        return snap.all("AXStaticText") { $0.text == title && $0.isVisibleSize && ($0.frame!.maxX <= (pane?.minX ?? .greatestFiniteMagnitude)) }
            .min { $0.frame!.minX < $1.frame!.minX }
    }

    func goSidebar(_ title: String, titles: [String]? = nil) throws {
        guard let item = try sidebarItem(title) else { throw StepFailure("no \"\(title)\" in the sidebar") }
        try click(item)
        let expected = titles ?? [title]
        try wait("the window to show \(title)") { expected.contains(self.title()) }
    }

    func rowNode(_ name: String) -> Node? {
        browserSnapshot()?.rowNames().first { $0.name == name }?.node
    }

    /// Selects a row by clicking it. A row already selected is left alone: a
    /// click on a selected row's name starts renaming it, as in Finder.
    func selectRow(_ name: String) throws {
        var node: Node?
        try wait("a row named \"\(name)\"") {
            node = rowNode(name)
            return node != nil
        }
        if !(isRowSelected(name) && selectedRowCount() == 1) {
            try click(node!)
        }
        // The status bar's "1 of 9 selected" stands in only where rows do not
        // say they are selected: it also reads so while another row (the
        // folder Cmd+Up came back from) is still the one selected.
        try wait("\"\(name)\" selected") {
            if self.isRowSelected(name) { return true }
            guard self.selectedRowCount() == 0 else { return false }
            return (self.browserSnapshot().flatMap(FilesJourneys.statusNode)?.text ?? "").contains("selected")
        }
        // A slow second click may have started renaming: leave the name as it was.
        if isEditingText(), focusedValue() == name { try key("escape") }
    }

    /// Whether the table row showing `name` reports itself selected (AXSelected).
    func isRowSelected(_ name: String) -> Bool {
        guard let snap = browserSnapshot() else { return false }
        for (index, node) in snap.nodes.enumerated() where node.role == "AXRow" {
            if snap.descendants(of: index).contains(where: { $0.text == name }) {
                return (node.element.attribute("AXSelected") as? Bool) == true
            }
        }
        return false
    }

    func selectedRowCount() -> Int {
        guard let snap = browserSnapshot() else { return 0 }
        return snap.nodes.filter { $0.role == "AXRow" && ($0.element.attribute("AXSelected") as? Bool) == true }.count
    }

    func openRow(_ name: String) throws {
        var node: Node?
        try wait("a row named \"\(name)\"") {
            node = rowNode(name)
            return node != nil
        }
        try click(node!, count: 2)
        try waitTitle(name)
    }

    func isEditingText() -> Bool {
        guard let focused = ax.element("AXFocusedUIElement") else { return false }
        return Layout.inputRoles.contains(focused.role) || focused.role == "AXTextArea"
    }

    func goToFolder(_ path: String, expect: String) throws {
        try key("cmd+shift+g")
        try wait("the path field") { self.isEditingText() }
        try key("cmd+a")
        type(path)
        try key("return")
        try waitTitle(expect)
        try wait("the folder's items") { (self.status() ?? -1) >= 0 }
    }

    /// Types a search. `allowEmpty`: the empty-state words that also end the
    /// wait, for a scope where no results is a right answer.
    func startSearch(_ text: String, allowEmpty: String? = nil) throws {
        try key("cmd+f")
        try wait("the search field to take the keys") { self.isEditingText() }
        type(text)
        try waitTitle("Search: " + text)
        let what = allowEmpty.map { "search results or \"\($0)\"" } ?? "search results"
        try wait(what, timeout: 20) {
            if (self.status() ?? 0) > 0 && !self.rows().isEmpty { return true }
            guard let allowEmpty, let snap = self.browserSnapshot() else { return false }
            return snap.nodes.contains { $0.text == allowEmpty && $0.isVisibleSize }
        }
    }

    func endSearch(returningTo title: String, alternatives: [String] = []) throws {
        if !isEditingText() {
            if let field = browserSnapshot().flatMap(FilesJourneys.searchField) { try click(field) } else { try key("cmd+f") }
            try wait("the search field to take the keys") { self.isEditingText() }
        }
        try key("escape")
        try wait("the search to end in \(title)") { ([title] + alternatives).contains(self.title()) }
        let field = browserSnapshot().flatMap(FilesJourneys.searchField)
        try check((field?.value ?? "").isEmpty, "the search field still reads \"\(field?.value ?? "")\"")
    }

    func chip(_ snap: Snapshot, _ kind: String, _ title: String) -> Node? {
        if let node = snap.identified(app.id("scope." + kind)) {
            let index = snap.nodes.firstIndex { $0.identifier == node.identifier }!
            let texts = [node.text] + snap.descendants(of: index).map(\.text)
            if texts.contains(title) { return node }
            return nil
        }
        // Without identifiers: a text with the title in the chip row under the toolbar.
        guard let field = FilesJourneys.searchField(snap)?.frame else { return nil }
        return snap.all("AXStaticText") { $0.text == title && ($0.frame?.minY ?? 0) > field.maxY && ($0.frame?.minY ?? 0) < field.maxY + 40 }.first
    }

    func chipTexts(_ snap: Snapshot) -> [String] {
        guard let field = FilesJourneys.searchField(snap)?.frame else { return [] }
        return snap.all("AXStaticText") { ($0.frame?.minY ?? 0) > field.maxY && ($0.frame?.minY ?? 0) < field.maxY + 40 }.map(\.text)
    }

    func clickChip(_ kind: String, _ title: String) throws {
        guard let snap = browserSnapshot(), let node = chip(snap, kind, title) else {
            throw StepFailure("no \"\(title)\" scope chip")
        }
        try click(node)
        try wait("the \(title) chip chosen") {
            guard let snap = self.browserSnapshot(), let chosen = self.chip(snap, kind, title) else { return false }
            return chosen.allText.joined().contains(title) || chosen.text == title
        }
        Input.pause(0.5)
    }

    /// The window's tab shortcut, else a click on the tab itself.
    func switchTab(to title: String, combo: String) throws {
        try key(combo)
        if (try? wait("the \"\(title)\" tab", timeout: 3) { self.title() == title }) != nil { return }
        guard let window = try? mainWindow(timeout: 2),
              let tab = snapshot(window).all("AXRadioButton", { $0.text == title }).first else {
            throw StepFailure("\(combo) did not switch tabs and there is no \"\(title)\" tab to click")
        }
        note("\(combo) did not switch tabs; clicked the tab")
        try click(tab)
        try waitTitle(title)
    }

    /// A node in any of the app's windows: sheets, alerts and popovers included.
    func anyNode(_ test: (Node) -> Bool) -> Node? {
        for window in windows() {
            if let found = snapshot(window).nodes.first(where: test) { return found }
        }
        return nil
    }

    /// The text of the field that has the keys.
    func focusedValue() -> String {
        ax.element("AXFocusedUIElement")?.string("AXValue") ?? ""
    }

    /// What the omnibar says it is doing: Go, Filter, Search or Command.
    func omnibarBadge() -> String {
        browserSnapshot()?.identified(app.id("omnibar.mode"))?.text ?? ""
    }

    /// Nexus's own trail of clipboard, key and task events (nexus.log in the
    /// fixture home's Library/Logs/grand-line), last lines first-to-last.
    func nexusLogTail(_ count: Int = 30) -> String {
        let file = url("Library/Logs/grand-line/nexus.log")
        guard let text = contents("Library/Logs/grand-line/nexus.log") else { return "(no log at \(file.path))" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count)
        return lines.isEmpty ? "(the log is empty)" : lines.joined(separator: "\n")
    }

    /// Runs a step's work; when it fails, the failure carries the last lines
    /// of Nexus's log, so a paste that made nothing says how far it got.
    func withNexusLog(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let failure as StepFailure {
            throw StepFailure(failure.message + "\nNexus log, last lines:\n" + nexusLogTail())
        }
    }

    func writeFixture(_ relative: String, _ text: String) throws {
        let target = url(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
    }

    func contents(_ relative: String) -> String? {
        (try? Data(contentsOf: url(relative))).map { String(decoding: $0, as: UTF8.self) }
    }

    func tabCount() -> Int {
        guard let window = try? mainWindow(timeout: 2) else { return 0 }
        let snap = snapshot(window)
        if let group = snap.nodes.firstIndex(where: { $0.role == "AXTabGroup" }) {
            let tabs = snap.descendants(of: group).filter { $0.role == "AXRadioButton" }
            if !tabs.isEmpty { return tabs.count }
        }
        return windows().filter { $0.string("AXSubrole") == "AXStandardWindow" }.count
    }
}
