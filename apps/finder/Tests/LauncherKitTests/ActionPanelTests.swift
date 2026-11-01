import XCTest
@testable import LauncherKit

/// Command+K for every kind of row, the panel's keys, the file buffer and the
/// "selection" keyword.
final class ActionPanelTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")

    func titles(_ actions: [LaunchAction]) -> [String] { actions.map(\.title) }

    func testFileRowsGetEveryFileAction() throws {
        let row = FileResults.result(FileHit(path: "/Users/me/Drive/Review.pdf", isFolder: false), paths: paths)
        let actions = ActionPanel.actions(for: row)
        for wanted in ["Open", "Open with…", "Show in Nexus", "Quick Look", "Copy path", "Copy name", "Copy file", "Add to buffer", "Move to Trash"] {
            XCTAssertTrue(titles(actions).contains(wanted), wanted)
        }
        XCTAssertEqual(Set(actions.map(\.command)).count, actions.count, "no action twice")
        let name = try XCTUnwrap(actions.first { $0.title == "Copy name" })
        XCTAssertEqual(name.command, .copyText("Review.pdf"))
        let trash = try XCTUnwrap(actions.first { $0.title == "Move to Trash" })
        XCTAssertEqual(trash.command, .files(.trash, ["/Users/me/Drive/Review.pdf"]))
        XCTAssertNotNil(trash.confirmation, "moving to the Trash asks first")
        // The row's own actions come first, in their order.
        XCTAssertEqual(Array(titles(actions).prefix(3)), ["Open", "Show in Nexus", "Quick Look"])
    }

    func testFoldersHaveNoOpenWith() {
        let row = FileResults.result(FileHit(path: "/Users/me/Drive", isFolder: true), paths: paths)
        XCTAssertEqual(ResultKind.of(row), .file(path: "/Users/me/Drive", isFolder: true))
        XCTAssertFalse(titles(ActionPanel.actions(for: row)).contains("Open with…"))
    }

    func testNothingEverDeletes() {
        let rows = [
            FileResults.result(FileHit(path: "/Users/me/a.txt", isFolder: false), paths: paths),
            AppCatalog.result("/Applications/Safari.app", paths: paths),
        ]
        for row in rows {
            for action in ActionPanel.actions(for: row) {
                XCTAssertFalse(action.title.lowercased().contains("delete"), action.title)
                if case .files(.trash, _) = action.command { XCTAssertNotNil(action.confirmation) }
            }
        }
    }

    func testAppsCalculatorBookmarksAndCommands() throws {
        let app = ActionPanel.actions(for: AppCatalog.result("/Applications/Safari.app", paths: paths))
        XCTAssertEqual(app.first { $0.title == "Copy name" }?.command, .copyText("Safari"))
        XCTAssertTrue(titles(app).contains("Show in Nexus"))

        let rates = CurrencyRatesStore(fileURL: nil)
        let sum = try XCTUnwrap(CalculatorProvider(rates: rates).instantResults(for: LaunchQuery(raw: "2+2")).first)
        XCTAssertTrue(titles(ActionPanel.actions(for: sum)).contains("Copy answer"))
        var bare = sum
        bare.actions = []
        XCTAssertEqual(ActionPanel.actions(for: bare).first?.command, .copyText(sum.title), "a sum can always be copied")

        let bookmark = try XCTUnwrap(Bookmarks.results([Bookmark(title: "PubMed", url: "https://pubmed.ncbi.nlm.nih.gov/", folder: "Research")]).first)
        let marks = ActionPanel.actions(for: bookmark)
        XCTAssertTrue(titles(marks).contains("Open"))
        XCTAssertTrue(titles(marks).contains("Copy URL"))
        XCTAssertTrue(titles(marks).contains("Copy title"))

        let script = CommandScript(name: "transcode", path: "/Users/me/.grand-line/bin/transcode", summary: "Convert a file", arguments: [])
        let command = ActionPanel.actions(for: CommandsProvider.row(script))
        XCTAssertEqual(command.first?.title, "Run")
        XCTAssertEqual(command.first { $0.title == "Edit" }?.command, .run("/usr/bin/open", arguments: ["-t", script.path]))
    }

    func testEveryKindHasActions() {
        let rows: [LaunchResult] = [
            Make.row("Anything"),
            LaunchResult(id: "x", title: "No actions", icon: .symbol("x"), section: .system, actions: []),
            WebSearches.result(WebSearches.builtIn[0], query: "glaucoma"),
        ]
        for row in rows {
            XCTAssertFalse(ActionPanel.actions(for: row).isEmpty, row.title)
        }
    }

    // MARK: The panel's keys

    func panel() -> ActionPanelModel {
        let row = FileResults.result(FileHit(path: "/Users/me/a.txt", isFolder: false), paths: paths)
        return ActionPanelModel(title: row.title, actions: ActionPanel.actions(for: row), result: row)
    }

    func testPanelMovesAndRuns() {
        var model = panel()
        var gate = ConfirmationGate()
        let outcome1 = model.handle(.moveUp, gate: &gate)
        XCTAssertEqual(outcome1, .handled)
        XCTAssertEqual(model.selected, 0)
        let outcome2 = model.handle(.moveDown, gate: &gate)
        XCTAssertEqual(outcome2, .handled)
        XCTAssertEqual(model.selected, 1)
        let outcome3 = model.handle(.primary, gate: &gate)
        XCTAssertEqual(outcome3, .run(model.actions[1]))
        let outcome4 = model.handle(.actions, gate: &gate)
        XCTAssertEqual(outcome4, .close)
        let outcome5 = model.handle(.complete, gate: &gate)
        XCTAssertEqual(outcome5, .passThrough)
    }

    func testTrashAsksThenRunsOnTheSecondReturn() {
        var model = panel()
        var gate = ConfirmationGate()
        model.selected = model.actions.firstIndex { $0.title == "Move to Trash" }!
        let outcome6 = model.handle(.primary, gate: &gate)
        XCTAssertEqual(outcome6, .handled)
        XCTAssertTrue(gate.isConfirming)
        let outcome7 = model.handle(.primary, gate: &gate)
        XCTAssertEqual(outcome7, .run(model.actions[model.selected]))
        XCTAssertFalse(gate.isConfirming)
    }

    func testEscapeCancelsTheQuestionThenCloses() {
        var model = panel()
        var gate = ConfirmationGate()
        model.selected = model.actions.firstIndex { $0.title == "Move to Trash" }!
        _ = model.handle(.primary, gate: &gate)
        let outcome8 = model.handle(.escape, gate: &gate)
        XCTAssertEqual(outcome8, .handled)
        XCTAssertFalse(gate.isConfirming)
        let outcome9 = model.handle(.escape, gate: &gate)
        XCTAssertEqual(outcome9, .close)
        // Moving away also drops the question.
        _ = model.handle(.primary, gate: &gate)
        _ = model.handle(.moveUp, gate: &gate)
        XCTAssertFalse(gate.isConfirming)
    }

    func testShortcutsRunTheirAction() {
        var model = panel()
        var gate = ConfirmationGate()
        let outcome = model.handle(.shortcut(KeyShortcut("n", shift: true)), gate: &gate)
        XCTAssertEqual(outcome, .run(model.actions.first { $0.title == "Copy name" }!))
        let outcome10 = model.handle(.shortcut(KeyShortcut("j")), gate: &gate)
        XCTAssertEqual(outcome10, .passThrough)
    }

    func testCommandBTogglesTheBuffer() {
        let press = KeyPress(keyCode: 11, characters: "b", command: true)
        XCTAssertEqual(KeyCommand.command(for: press), .toggleBuffer)
        let row = FileResults.result(FileHit(path: "/x/a.txt", isFolder: false), paths: paths)
        // The footer stays short: ⌘B is listed in the actions (⌘K), not the footer.
        XCTAssertTrue(FooterHints.hints(for: row, confirming: nil).contains { $0.keys == "\u{2318}K" })
        XCTAssertFalse(FooterHints.hints(for: row, confirming: nil).contains { $0.keys == "\u{2318}B" })
    }

    // MARK: File buffer

    func testBufferTogglesFileRowsOnly() {
        var buffer = FileBuffer()
        let a = FileResults.result(FileHit(path: "/x/a.txt", isFolder: false), paths: paths)
        let b = FileResults.result(FileHit(path: "/x/b", isFolder: true), paths: paths)
        XCTAssertTrue(buffer.toggle(a))
        XCTAssertTrue(buffer.toggle(b))
        XCTAssertFalse(buffer.toggle(Make.row("Safari")))
        XCTAssertEqual(buffer.paths, ["/x/a.txt", "/x/b"])
        XCTAssertEqual(buffer.chips.map(\.name), ["a.txt", "b"])
        XCTAssertEqual(buffer.title, "2 files in the buffer")
        XCTAssertTrue(buffer.toggle(a))
        XCTAssertEqual(buffer.paths, ["/x/b"])
    }

    func testBufferActionsApplyToEveryFile() throws {
        let buffer = FileBuffer(paths: ["/x/a.txt", "/x/b.txt", "/x/a.txt"])
        XCTAssertEqual(buffer.count, 2)
        let actions = buffer.actions
        XCTAssertEqual(actions.first?.command, .files(.open, ["/x/a.txt", "/x/b.txt"]))
        XCTAssertTrue(actions.contains { $0.command == .files(.reveal, buffer.paths) })
        XCTAssertTrue(actions.contains { $0.command == .copyText("/x/a.txt\n/x/b.txt") })
        XCTAssertTrue(actions.contains { $0.command == .copyText("a.txt\nb.txt") })
        let trash = try XCTUnwrap(actions.first { $0.command == .files(.trash, buffer.paths) })
        XCTAssertEqual(trash.confirmation, "Move 2 items to the Trash?")
        XCTAssertEqual(actions.last?.command, .clearBuffer)
    }

    func testBufferAddsSeveralOrTakesThemAllOut() {
        var buffer = FileBuffer(paths: ["/x/a"])
        buffer.toggle(paths: ["/x/a", "/x/b"])
        XCTAssertEqual(buffer.paths, ["/x/a", "/x/b"])
        buffer.toggle(paths: ["/x/a", "/x/b"])
        XCTAssertTrue(buffer.isEmpty)
        var full = FileBuffer()
        for i in 0..<(FileBuffer.limit + 3) { full.add("/x/\(i)") }
        XCTAssertEqual(full.count, FileBuffer.limit)
    }

    // MARK: "selection"

    func testSelectionReadsNexusStateFile() throws {
        let file = try Make.folder().appendingPathComponent("nexus-selection")
        try Make.write("/x/a.txt\n\n/x/b.pdf\n/x/a.txt\nnot a path\n", to: file)
        XCTAssertEqual(SelectionProvider.readNexus(file.path), ["/x/a.txt", "/x/b.pdf"])
        XCTAssertEqual(SelectionProvider.readNexus("/no/such/file"), [])
        XCTAssertEqual(paths.nexusSelection, "/Users/me/.local/state/grand-line/nexus-selection")
    }

    func testSelectionKeywordListsActionsForTheSelectedFiles() {
        let provider = SelectionProvider()
        provider.set(["/x/a.txt", "/x/b.pdf"], from: "Nexus")
        let rows = provider.instantResults(for: LaunchQuery(raw: "selection"))
        XCTAssertEqual(rows.first?.title, "Open 2 items")
        XCTAssertEqual(rows.first?.primary?.command, .files(.open, ["/x/a.txt", "/x/b.pdf"]))
        XCTAssertTrue(rows.contains { $0.primary?.command == .buffer(["/x/a.txt", "/x/b.pdf"]) })
        XCTAssertTrue(rows.allSatisfy { $0.subtitle.hasPrefix("Nexus") })
        XCTAssertEqual(provider.instantResults(for: LaunchQuery(raw: "sel")).count, rows.count)
        let narrowed = provider.instantResults(for: LaunchQuery(raw: "selection trash"))
        XCTAssertEqual(narrowed.first?.primary?.command, .files(.trash, ["/x/a.txt", "/x/b.pdf"]))
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "se")).isEmpty)
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "safari")).isEmpty)
    }

    func testSelectionSaysWhenNothingIsSelected() {
        let provider = SelectionProvider()
        let rows = provider.instantResults(for: LaunchQuery(raw: "selection"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].actions.isEmpty)
        XCTAssertEqual(SelectionProvider.parse("/a\n/b\n"), ["/a", "/b"])
    }
}
