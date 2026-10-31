import XCTest
@testable import LauncherKit

/// The models behind Sight's Settings window: sources turned on and off and
/// reordered, the section order and row counts they give, web engines, and
/// the round trip through the defaults domain.
final class SightSettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "SightSettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Sources

    func testDefaultSourcesKeepTheDefaultSectionOrder() {
        XCTAssertEqual(SourceSettings.standard.order, LauncherSource.allCases)
        XCTAssertEqual(SourceSettings.standard.sectionOrder, ResultSection.allCases)
        XCTAssertEqual(ResultLayout(order: SourceSettings.standard.sectionOrder), .standard)
    }

    func testProviderOrderAndEnabledRoundTrip() {
        var sources = SourceSettings.standard
        sources.move(.files, by: -100)
        sources.move(.apps, by: 1)
        sources.set(.bookmarks, enabled: false)
        sources.set(.units, enabled: false)
        XCTAssertEqual(sources.order.first, .files)

        var prefs = SightPreferences()
        prefs.sources = sources
        prefs.save(to: defaults)
        let read = SightPreferences(defaults: defaults)
        XCTAssertEqual(read.sources, sources)
        XCTAssertFalse(read.sources.isEnabled(.bookmarks))
        XCTAssertTrue(read.sources.isEnabled(.apps))
        XCTAssertEqual(defaults.stringArray(forKey: SourceSettings.disabledKey), ["units", "bookmarks"])

        // Files first puts the Files section first, after the favourites, recents and top hit.
        XCTAssertEqual(Array(read.sources.sectionOrder.prefix(4)), [.favourites, .recents, .topHit, .files])
        XCTAssertEqual(Set(read.sources.sectionOrder), Set(ResultSection.allCases))
    }

    func testUnknownAndMissingSourcesAreRepaired() {
        let sources = SourceSettings(order: ["files", "nonsense", "apps", "files"], disabled: ["windows", "gone"])
        XCTAssertEqual(sources.order.count, LauncherSource.allCases.count)
        XCTAssertEqual(Array(sources.order.prefix(2)), [.files, .apps])
        XCTAssertEqual(sources.disabled, [.windows])
    }

    func testDragMovesLikeSwiftUI() {
        var sources = SourceSettings.standard
        let first = sources.order[0]
        sources.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(sources.order[2], first)
        sources.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(sources.order, LauncherSource.allCases)
    }

    func testAProviderRunsWhileAnySourceItServesIsOn() {
        var sources = SourceSettings.standard
        sources.set(.calculator, enabled: false)
        XCTAssertTrue(sources.runs(providerID: "calculator"), "units still need it")
        sources.set(.units, enabled: false)
        XCTAssertFalse(sources.runs(providerID: "calculator"))
        XCTAssertTrue(sources.runs(providerID: "symbols"), "a provider no source names always runs")
    }

    func testCalculatorAnswersOnlyWhatIsTurnedOn() {
        let store = CurrencyRatesStore(fileURL: nil)
        let noUnits = CalculatorProvider(rates: store, conversions: false)
        XCTAssertTrue(noUnits.instantResults(for: LaunchQuery(raw: "5 km in m")).isEmpty)
        XCTAssertEqual(noUnits.instantResults(for: LaunchQuery(raw: "2+2")).first?.title, "4")
        let onlyUnits = CalculatorProvider(rates: store, arithmetic: false)
        XCTAssertTrue(onlyUnits.instantResults(for: LaunchQuery(raw: "2+2")).isEmpty)
        XCTAssertFalse(onlyUnits.instantResults(for: LaunchQuery(raw: "5 km in m")).isEmpty)
    }

    // MARK: Section order and row counts

    func testLayoutOrdersSectionsAndLimitsRows() {
        let query = LaunchQuery(raw: "no", term: "no")
        let rows = Ranker().rank(Make.matched([
            Make.row("Notes", section: .apps),
            Make.row("Notebook", section: .apps),
            Make.row("Nordic", section: .apps),
            Make.row("Notes.txt", section: .files),
        ], query.term), query: query)
        let layout = ResultLayout(order: [.files, .apps], limits: [.apps: 2])
        let groups = ResultGrouping.group(rows, topHit: false, layout: layout)
        XCTAssertEqual(groups.map(\.section), [.files, .apps])
        XCTAssertEqual(groups[1].rows.count, 2)
        XCTAssertEqual(layout.limit(.topHit), 1)
        XCTAssertEqual(layout.order.count, ResultSection.allCases.count, "missing sections are added")
    }

    func testResultLimitsRoundTripAndClamp() {
        var prefs = SightPreferences()
        prefs.limits = [.files: 12, .apps: ResultSection.apps.limit]
        prefs.save(to: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: SightPreferences.resultLimitsKey) as? [String: Int], ["files": 12])
        XCTAssertEqual(SightPreferences(defaults: defaults).limits, [.files: 12])
        XCTAssertEqual(SightPreferences.limits(from: ["web": 500, "topHit": 3, "nope": 2]), [.web: 20])
    }

    // MARK: Web engines

    func testWebEngineParsing() {
        let stored: [Any] = [
            ["name": "Google", "url": "https://www.google.com/search?q=%s", "keyword": "g", "fallback": true],
            ["name": "No words", "url": "https://example.org/", "keyword": "nw"],
            ["name": "Plain http", "url": "http://x.test/?q=%s", "keyword": "PX", "fallback": NSNumber(value: false)],
            ["name": "", "url": "https://x.test/?q=%s", "keyword": "anon"],
            ["name": "Same key", "url": "https://y.test/?q=%s", "keyword": "g"],
            ["name": "Ask", "url": "https://ask.test/?q=%s", "keyword": "", "fallback": true],
            "not a dictionary",
        ]
        let engines = WebEngineList.parse(stored)
        XCTAssertEqual(engines.map(\.name), ["Google", "Plain http", "Ask"])
        XCTAssertEqual(engines[1].keyword, "px")
        XCTAssertEqual(engines.map(\.fallback), [true, false, true])
        XCTAssertEqual(WebEngineList.parse(nil), WebEngineList.standard)
        XCTAssertEqual(WebEngineList.parse([Any]()), [], "an emptied list stays empty")

        XCTAssertNil(WebEngine.problem(name: "PubMed", template: "https://pubmed.ncbi.nlm.nih.gov/?term=%s", keyword: "pm"))
        XCTAssertNotNil(WebEngine.problem(name: "PubMed", template: "pubmed.ncbi.nlm.nih.gov/?term=%s", keyword: "pm"))
        XCTAssertNotNil(WebEngine.problem(name: "PubMed", template: "https://pubmed.ncbi.nlm.nih.gov/", keyword: "pm"))
        XCTAssertNotNil(WebEngine.problem(name: "PubMed", template: "https://pubmed.ncbi.nlm.nih.gov/?term=%s", keyword: "p m"))
    }

    func testEnginesRoundTripAndFeedTheProviders() throws {
        var prefs = SightPreferences()
        prefs.engines = [
            WebEngine(name: "PubMed", template: "https://pubmed.ncbi.nlm.nih.gov/?term=%s", keyword: "pm", fallback: true),
            WebEngine(name: "Kagi", template: "https://kagi.com/search?q=%s", keyword: "k", fallback: true),
            WebEngine(name: "Scholar", template: "https://scholar.google.com/scholar?q=%s", keyword: "gs"),
        ]
        prefs.assistantFallbacks = false
        prefs.save(to: defaults)
        let read = SightPreferences(defaults: defaults)
        XCTAssertEqual(read.engines, prefs.engines)
        XCTAssertFalse(read.assistantFallbacks)

        let rows = FallbackProvider(fallbacks: read.fallbacks).instantResults(for: LaunchQuery(raw: "cornea"))
        XCTAssertEqual(rows.map(\.id), ["fallback:drive", "fallback:pm", "fallback:k"])
        XCTAssertEqual(rows[2].primary?.command, .openURL("https://kagi.com/search?q=cornea", bundleID: nil))

        let searches = WebEngineList.searches(read.engines, quicklinks: "k\tKagi Lite\thttps://kagi.com/html?q=%s\n")
        XCTAssertEqual(searches.map(\.keyword), ["pm", "gs", "k"])
        XCTAssertEqual(searches.last?.title, "Kagi Lite")

        let web = WebProvider(quicklinksFile: "/nowhere")
        web.setEngines(read.engines)
        XCTAssertEqual(web.instantResults(for: LaunchQuery(raw: "k glaucoma")).first?.title, "Search Kagi for “glaucoma”")
        XCTAssertTrue(web.instantResults(for: LaunchQuery(raw: "g glaucoma")).isEmpty, "Google was removed")
    }

    func testStandardEnginesMatchTheBuiltInFallbacks() {
        let rows = FallbackProvider(fallbacks: SightPreferences().fallbacks).instantResults(for: LaunchQuery(raw: "cornea"))
        XCTAssertEqual(rows.map(\.id), FallbackProvider().instantResults(for: LaunchQuery(raw: "cornea")).map(\.id))
    }

    // MARK: The rest of the window

    func testGeneralSettingsRoundTrip() {
        XCTAssertEqual(SightPreferences(defaults: defaults), SightPreferences(), "nothing stored gives the defaults")
        var prefs = SightPreferences()
        prefs.showMenuBarIcon = false
        prefs.launchAtLogin = false
        prefs.closeAfterSettingChange = true
        prefs.save(to: defaults)
        XCTAssertEqual(SightPreferences(defaults: defaults), prefs)
        XCTAssertTrue(defaults.bool(forKey: SettingsActionsProvider.closeAfterChangeKey))
    }

    func testUsageResetForgetsEverything() {
        let usage = UsageStore()
        let query = LaunchQuery(raw: "no", term: "no")
        usage.record(Make.row("Notes"), query: query)
        XCTAssertFalse(usage.frecencies(for: query).isEmpty)
        usage.reset()
        XCTAssertTrue(usage.frecencies(for: query).isEmpty)
    }
}
