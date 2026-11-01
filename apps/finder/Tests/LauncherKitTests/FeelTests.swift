import XCTest
import IndexKit
@testable import LauncherKit

/// What makes the launcher predictable to use: tight fuzzy matches, typos
/// one tier below everything else, what Return does said in plain words, the
/// section order, query history on Up, Right arrow and the modifier keys.
final class FeelTests: XCTestCase {
    func hit(_ query: String, _ title: String) -> TextMatcher.Hit? {
        TextMatcher(query).match(FoldedText(title))
    }

    // MARK: Tight fuzzy matching

    func testLettersScatteredThroughALongTitleDoNotMatch() {
        XCTAssertNil(hit("sleep", "How to study for USMLE Step 1 - resources and planning"))
        XCTAssertNil(hit("ab", "Alpha one two three Beta"), "three words skipped between the two used")
        XCTAssertNil(hit("ac", "abbbbc"), "four letters skipped inside one word")
    }

    func testAbbreviationsStillMatch() {
        XCTAssertEqual(hit("vsc", "Visual Studio Code")?.tier, .fuzzy)
        XCTAssertEqual(hit("spf", "System Preferences")?.tier, .fuzzy)
        XCTAssertEqual(hit("gd", "GoogleDrive")?.tier, .fuzzy)
        XCTAssertEqual(hit("ff", "Firefox")?.tier, .fuzzy)
        XCTAssertEqual(hit("glre", "Gold Lake Ridge Estate")?.tier, .fuzzy)
        XCTAssertNotNil(hit("ac", "a b c"), "one word skipped is fine")
    }

    func testTightnessRules() {
        let text = FoldedText("How to study for USMLE Step")
        // s(study) l(inside USMLE): a new word entered in its middle.
        XCTAssertFalse(TextMatcher.isTight([7, 20], in: text))
        // s(study) U(USMLE): one word skipped.
        XCTAssertTrue(TextMatcher.isTight([7, 17], in: text))
        // h(How) U(USMLE): three words skipped.
        XCTAssertFalse(TextMatcher.isTight([0, 17], in: text))
    }

    func testFuzzyNeverBeatsAWordStart() {
        let query = LaunchQuery(raw: "step")
        let rows = [Make.row("System Test Editor Panel"), Make.row("Next Step")]
        let ranked = Ranker().rank(Make.matched(rows, "step"), query: query).map(\.title)
        XCTAssertEqual(ranked, ["Next Step", "System Test Editor Panel"])
    }

    func testIndexHitsFoundOnlyByScatteredLettersAreDropped() async throws {
        let provider = FilesProvider(
            paths: GrandLinePaths(home: "/Users/me"),
            names: { _, _ in [
                IndexMatch(path: "/Users/me/How to study for USMLE Step 1.pdf", name: "How to study for USMLE Step 1.pdf",
                           isFolder: false, tier: .fuzzy, highlights: []),
                IndexMatch(path: "/Users/me/sleep log.txt", name: "sleep log.txt", isFolder: false, tier: .prefix, highlights: []),
            ] },
            spotlight: { _, _ in [] }
        )
        let rows = try await provider.results(for: LaunchQuery(raw: "sleep"))
        XCTAssertEqual(rows.map(\.title), ["sleep log.txt"])
    }

    // MARK: Typos

    func testOneLetterOffMatchesAsATypo() {
        XCTAssertEqual(hit("safri", "Safari")?.tier, .fuzzy, "a letter missed: still its letters in order, close together")
        XCTAssertEqual(hit("safarri", "Safari")?.tier, .typo, "a letter added")
        XCTAssertEqual(hit("safark", "Safari")?.tier, .typo, "a letter changed, though k is not in the title")
        XCTAssertEqual(hit("slepe", "Sleep")?.tier, .typo, "two letters swapped")
        XCTAssertEqual(hit("calender", "Calendar")?.tier, .typo)
        XCTAssertEqual(hit("notse", "Apple Notes")?.tier, .typo, "at the start of any word")
    }

    func testTyposNeedFourLettersTheFirstLetterAndOneEdit() {
        XCTAssertNil(hit("saf", "Sag"), "three letters are never a typo")
        XCTAssertNil(hit("xafari", "Safari"), "the first letter must be right")
        XCTAssertNil(hit("sfrai", "Safari"), "two edits")
        XCTAssertNil(TextMatcher("safri", exactOnly: true).match(FoldedText("Safari")))
    }

    func testTyposRankBelowEveryOtherMatch() {
        let query = LaunchQuery(raw: "notse")
        let rows = [Make.row("Notes"), Make.row("Nota Tiny Station Exporter")]
        let ranked = Ranker().rank(Make.matched(rows, "notse"), query: query)
        XCTAssertEqual(ranked.map(\.title), ["Nota Tiny Station Exporter", "Notes"])
        XCTAssertEqual(ranked.last?.match.title, .typo)
        XCTAssertLessThan(RankKey(fallback: false, alias: .none, title: MatchTier.fuzzy.rawValue, keyword: RankKey.noMatch, frecency: 0, quality: 0),
                          RankKey(fallback: false, alias: .none, title: MatchTier.typo.rawValue, keyword: RankKey.noMatch, frecency: 1_000, quality: 500))
    }

    func testATitleTypoCanBeTopHitButAKeywordTypoCannot() {
        var title = Make.row("Safari")
        title.match = MatchInfo(title: .typo)
        XCTAssertTrue(ResultGrouping.canBeTopHit(title))
        var keyword = Make.row("Browser")
        keyword.match = MatchInfo(keyword: .typo)
        XCTAssertFalse(ResultGrouping.canBeTopHit(keyword))
    }

    // MARK: Instant answers

    func testAShortWordAnswerRanksBelowAnAppThatStartsWithIt() {
        XCTAssertEqual(CalculatorProvider.match(for: "pi").title, .wordStart)
        XCTAssertEqual(CalculatorProvider.match(for: "2+2").title, .exact)
        XCTAssertEqual(CalculatorProvider.match(for: "5 km in mi").title, .exact)
        var answer = Make.row("3.14159", id: "calc", section: .answers)
        answer.match = CalculatorProvider.match(for: "pi")
        var app = Make.row("Pixelmator")
        app.match = MatchInfo(title: .prefix)
        let ranked = Ranker().rank([answer, app], query: LaunchQuery(raw: "pi"))
        XCTAssertEqual(ranked.first?.title, "Pixelmator")
    }

    // MARK: Plain words

    func testPowerRowsSayWhatReturnDoes() {
        XCTAssertEqual(SettingsActionsProvider.powerSubtitle(confirm: "Press Return again to put the Mac to sleep"),
                       "Return asks, then Return again will put the Mac to sleep")
        XCTAssertEqual(SettingsActionsProvider.powerSubtitle(confirm: "Press Return again to shut down"),
                       "Return asks, then Return again will shut down")
        XCTAssertEqual(SettingsActionsProvider.powerSubtitle(confirm: nil), "Return does it now")
    }

    func testTheFooterSaysWhatReturnDoesThenTheActions() {
        let row = FileResults.result(FileHit(path: "/Users/me/notes.txt", isFolder: false), paths: GrandLinePaths(home: "/Users/me"))
        let hints = FooterHints.hints(for: row, confirming: nil)
        XCTAssertEqual(hints.map(\.label), ["Open", "Show in Nexus", "Actions"])
        XCTAssertEqual(hints.map(\.keys), ["↵", "⌘↵", "⌘K"])
        // Command held: the first hint is what Command+Return does.
        XCTAssertEqual(FooterHints.hints(for: row, confirming: nil, held: .command).first, .init(keys: "⌘↵", label: "Show in Nexus"))
        XCTAssertEqual(FooterHints.hints(for: row, confirming: nil, held: .option).first, .init(keys: "⌥↵", label: "Copy path"))
        XCTAssertEqual(ModifierPreview.subtitle(for: row, held: .option), "⌥↵ Copy path")
        XCTAssertNil(ModifierPreview.subtitle(for: row, held: .none))
    }

    // MARK: Sections

    func testFilesComeBeforeBookmarksAndTheWebLast() {
        let query = LaunchQuery(raw: "note")
        let rows = [
            Make.row("Note search", section: .web, fallback: true),
            Make.row("Notebook club", section: .bookmarks),
            Make.row("Notes.txt", section: .files),
            Make.row("Notes", section: .apps),
            Make.row("Notarize", section: .system),
        ]
        let ranked = Ranker().rank(Make.matched(rows, "note"), query: query)
        let groups = ResultGrouping.group(ranked, layout: .standard)
        XCTAssertEqual(groups.map(\.section), [.topHit, .system, .files, .bookmarks, .web])
        XCTAssertEqual(groups.first?.rows.first?.title, "Notes")
    }

    func testSavedRecentsKeepTheirSection() {
        // The raw values are in usage.json; reordering the sections must not change them.
        XCTAssertEqual(ResultSection.bookmarks.rawValue, 8)
        XCTAssertEqual(ResultSection.files.rawValue, 11)
        XCTAssertEqual(ResultSection.system.rawValue, 7)
        XCTAssertTrue(ResultSection.files < ResultSection.bookmarks)
        XCTAssertTrue(ResultSection.apps < ResultSection.system)
    }

    func testTheOldDefaultOrderReadsAsTheNewDefault() {
        let old = SourceSettings(order: SourceSettings.previousDefaultOrder, disabled: nil)
        XCTAssertEqual(old.order, SourceSettings.standard.order)
        let custom = SourceSettings(order: ["bookmarks", "apps"], disabled: nil)
        XCTAssertEqual(Array(custom.order.prefix(2)), [.bookmarks, .apps], "a chosen order is kept")
    }

    // MARK: Query history and resume

    func testUpOnAnEmptyFieldRecallsEarlierQueries() {
        var history = QueryHistory()
        history.record("safari")
        history.record("  notes ")
        history.record("safari")
        XCTAssertEqual(history.entries, ["safari", "notes"])
        XCTAssertNil(history.up(text: "sa", atTop: true), "something typed: Up moves the selection")
        XCTAssertNil(history.up(text: "", atTop: false))
        XCTAssertEqual(history.up(text: "", atTop: true), "safari")
        XCTAssertEqual(history.up(text: "safari", atTop: true), "notes")
        XCTAssertNil(history.up(text: "notes", atTop: true), "the oldest")
        history.leave()
        XCTAssertNil(history.up(text: "notes", atTop: true))
    }

    func testClipboardQueriesAreNotKeptButSymbolsAre() {
        var history = QueryHistory()
        history.record(":password")
        history.record("::alpha")
        history.record("")
        XCTAssertEqual(history.entries, ["::alpha"])
        for i in 0..<(QueryHistory.limit + 5) { history.record("q\(i)") }
        XCTAssertEqual(history.entries.count, QueryHistory.limit)
    }

    func testTheLastQueryStaysForAQuickReopenOnly() {
        let closed = Date()
        XCTAssertTrue(QueryResume.keepsQuery(hiddenAt: nil, now: closed))
        XCTAssertTrue(QueryResume.keepsQuery(hiddenAt: closed, now: closed.addingTimeInterval(60)))
        XCTAssertFalse(QueryResume.keepsQuery(hiddenAt: closed, now: closed.addingTimeInterval(QueryResume.keepFor + 1)))
    }

    func testThePlaceholderTeachesSomethingNewEachOpening() {
        let lines = (0..<SearchPlaceholder.lines.count).map { SearchPlaceholder.text(opening: $0) }
        XCTAssertEqual(Set(lines).count, SearchPlaceholder.lines.count)
        XCTAssertEqual(SearchPlaceholder.text(opening: SearchPlaceholder.lines.count), lines[0])
        XCTAssertFalse(SearchPlaceholder.text(opening: -1).isEmpty)
    }

    // MARK: Keys

    func testModifierKeysAndRightArrow() {
        XCTAssertEqual(KeyCommand.command(for: KeyPress(keyCode: KeyPress.Code.returnKey, option: true)), .alternate)
        XCTAssertEqual(KeyCommand.command(for: KeyPress(keyCode: KeyPress.Code.returnKey, command: true)), .secondary)
        XCTAssertEqual(KeyCommand.command(for: KeyPress(keyCode: KeyPress.Code.right)), .drillIn)
        XCTAssertNil(KeyCommand.command(for: KeyPress(keyCode: KeyPress.Code.right, shift: true)), "Shift+Right selects text")
        XCTAssertEqual(HeldModifier(command: true, option: false), .command)
        XCTAssertEqual(HeldModifier(command: false, option: true), .option)
        XCTAssertEqual(HeldModifier(command: true, option: false, shift: true), .none)
    }

    func testRightArrowGoesIntoFoldersAndOpensActionsElsewhere() {
        let paths = GrandLinePaths(home: "/Users/me")
        let folder = FileResults.result(FileHit(path: "/Users/me/Documents", isFolder: true), paths: paths)
        XCTAssertEqual(DrillIn.target(for: folder, paths: paths), .browse("~/Documents/"))
        let app = Make.row("Safari", id: "app:/Applications/Safari.app")
        XCTAssertEqual(DrillIn.target(for: app, paths: paths), .actions)
        XCTAssertNil(DrillIn.target(for: Make.row("Search the web", fallback: true), paths: paths))
        XCTAssertNil(DrillIn.target(for: nil, paths: paths))
    }

    func testOptionReturnCopiesWhatIsNotAlreadyOnReturn() {
        let app = Make.row("Safari", id: "app:/Applications/Safari.app")
        XCTAssertEqual(ActionPanel.alternate(for: app)?.command, .copyText("/Applications/Safari.app"))
        var answer = Make.row("4", id: "calc", section: .answers)
        answer.providerID = "calculator"
        answer.actions = [LaunchAction("Copy answer", symbol: "doc", .copyText("4")), LaunchAction("Paste answer", symbol: "doc", .paste("4")),
                          LaunchAction("Copy with unit", symbol: "doc", .copyText("4 m"))]
        XCTAssertEqual(ActionPanel.alternate(for: answer)?.title, "Copy with unit")
    }
}
