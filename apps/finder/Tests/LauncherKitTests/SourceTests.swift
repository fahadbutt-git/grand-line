import XCTest
@testable import LauncherKit

final class SourceTests: XCTestCase {
    func testZenBookmarks() {
        let rows: [ZenBookmarks.Row] = [
            .init(id: 1, parent: 0, type: 2, title: "", url: nil),
            .init(id: 3, parent: 1, type: 2, title: "toolbar", url: nil),
            .init(id: 10, parent: 3, type: 2, title: "Research", url: nil),
            .init(id: 11, parent: 10, type: 1, title: "PubMed", url: "https://pubmed.ncbi.nlm.nih.gov/"),
            .init(id: 12, parent: 3, type: 1, title: "", url: "https://www.example.org/cornea"),
            .init(id: 13, parent: 3, type: 1, title: "Recent", url: "place:sort=8"),
            .init(id: 14, parent: 3, type: 3, title: "", url: nil),
        ]
        let bookmarks = ZenBookmarks.bookmarks(from: rows)
        XCTAssertEqual(bookmarks.map(\.title), ["PubMed", "https://www.example.org/cornea"], "place: queries and separators are left out")
        XCTAssertEqual(bookmarks.map(\.folder), ["Bookmarks toolbar › Research", "Bookmarks toolbar"])
    }

    func testChromeBookmarks() throws {
        let json = """
        {"roots": {
          "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
            {"type": "url", "name": "PubMed", "url": "https://pubmed.ncbi.nlm.nih.gov/"},
            {"type": "folder", "name": "Research", "children": [
              {"type": "url", "name": "", "url": "https://www.example.org/cornea"}
            ]}
          ]},
          "other": {"type": "folder", "name": "Other bookmarks", "children": []}
        }}
        """
        let bookmarks = ChromeBookmarks.parse(Data(json.utf8))
        XCTAssertEqual(bookmarks.map(\.title), ["PubMed", "https://www.example.org/cornea"])
        XCTAssertEqual(bookmarks[1].folder, "Bookmarks bar › Research")
        XCTAssertEqual(ChromeBookmarks.host(bookmarks[1].url), "example.org")
        let row = ChromeBookmarks.results(bookmarks)[0]
        XCTAssertEqual(row.primary?.command, .openURL("https://pubmed.ncbi.nlm.nih.gov/", bundleID: "com.google.Chrome"))

        let chrome = try Make.folder()
        try Make.write(json, to: chrome.appendingPathComponent("Default/Bookmarks"))
        try Make.write(json, to: chrome.appendingPathComponent("Profile 1/Bookmarks"))
        XCTAssertEqual(ChromeBookmarks.load(chromeFolder: chrome.path).count, 2, "a URL in two profiles is listed once")
    }

    func testAeroSpaceWindows() {
        let output = "12|Safari|PubMed | glaucoma\n7|Ghostty|\nbad line\n"
        let windows = WindowsProvider.parse(output)
        XCTAssertEqual(windows, [WindowEntry(id: 12, app: "Safari", title: "PubMed | glaucoma"), WindowEntry(id: 7, app: "Ghostty", title: "")])
        let rows = WindowsProvider().rows(windows)
        XCTAssertEqual(rows[1].title, "Ghostty")
        guard case .run(_, let arguments)? = rows[0].primary?.command else { return XCTFail() }
        XCTAssertEqual(arguments, ["focus", "--window-id", "12"])
        XCTAssertEqual(WindowsProvider.format, "%{window-id}|%{app-name}|%{window-title}")
    }

    func testWebKeywordsAndQuicklinks() {
        let all = WebSearches.all(quicklinks: "# keyword\ttitle\turl\nwiki\tFrench Wikipedia\thttps://fr.wikipedia.org/w/index.php?search=%s\nlp\tLog\thttps://x.test/?q=%s\n")
        XCTAssertEqual(all.map(\.keyword), ["g", "pm", "gs", "yt", "wiki", "lp"])
        XCTAssertEqual(all.first { $0.keyword == "wiki" }?.title, "French Wikipedia")
        XCTAssertEqual(WebSearches.builtIn[1].url(for: "corneal edema & cataract"), "https://pubmed.ncbi.nlm.nih.gov/?term=corneal%20edema%20%26%20cataract")

        let web = WebProvider(quicklinksFile: "/nowhere")
        let rows = web.instantResults(for: LaunchQuery(raw: "pm glaucoma"))
        XCTAssertEqual(rows.first?.title, "Search PubMed for “glaucoma”")
        XCTAssertEqual(rows.first?.match.alias, .exact)
        let listed = web.instantResults(for: LaunchQuery(raw: "?cornea", prefix: .web, term: "cornea"))
        XCTAssertEqual(listed.count, 5)
        XCTAssertTrue(web.instantResults(for: LaunchQuery(raw: "glaucoma")).isEmpty)
    }

    func testAddresses() {
        XCTAssertEqual(WebSearches.address("github.com/me"), "https://github.com/me")
        XCTAssertEqual(WebSearches.address("https://example.org"), "https://example.org")
        XCTAssertNil(WebSearches.address("report.pdf"))
        XCTAssertNil(WebSearches.address("two words.com"))
        XCTAssertNil(WebSearches.address("v1.2"))
    }

    func testFallbacksComeLastAndAskTheAssistants() {
        let rows = FallbackProvider().instantResults(for: LaunchQuery(raw: "cornea"))
        XCTAssertEqual(rows.map(\.id), ["fallback:drive", "fallback:g", "fallback:pm", "fallback:claude", "fallback:chatgpt", "fallback:gemini"])
        XCTAssertTrue(rows.allSatisfy(\.isFallback))
        XCTAssertEqual(rows[0].primary?.command, .setQuery(". cornea drive:"))
        XCTAssertEqual(rows[3].primary?.command, .openURL("https://claude.ai/new?q=cornea", bundleID: nil))
        XCTAssertTrue(FallbackProvider().instantResults(for: LaunchQuery(raw: "")).isEmpty)
        XCTAssertTrue(FallbackProvider().instantResults(for: LaunchQuery(raw: ";x", prefix: .snippets, term: "x")).isEmpty)
    }

    func testExternalProviderConfigAndJSONLines() {
        let configs = ExternalProviderConfig.parse("# keyword\ttitle\tcommand\tglobal\nz\tZotero\t~/bin/zot\tyes\nn\t\tnotes-search\n")
        XCTAssertEqual(configs.count, 2)
        XCTAssertTrue(configs[0].global)
        XCTAssertEqual(configs[1].title, "n")
        let output = """
        {"title": "Cornea review", "subtitle": "2024", "open": "~/Drive/cornea.pdf", "preview": "~/Drive/cornea.pdf"}
        not json
        {"title": "Search more", "query": "z cornea more", "icon": "magnifyingglass"}
        {"title": "Copy cite", "copy": "Smith 2024", "actions": [{"title": "Open site", "url": "https://example.org"}]}
        {"subtitle": "no title"}
        """
        let rows = JSONLines.parse(output, providerID: "ext:z", paths: GrandLinePaths(home: "/Users/me"))
        XCTAssertEqual(rows.map(\.title), ["Cornea review", "Search more", "Copy cite"])
        XCTAssertEqual(rows[0].primary?.command, .open("~/Drive/cornea.pdf"))
        XCTAssertEqual(rows[0].previewPath, "/Users/me/Drive/cornea.pdf")
        XCTAssertEqual(rows[1].primary?.closesWindow, false)
        XCTAssertEqual(rows[2].actions.map(\.title), ["Copy", "Open site"])
        XCTAssertGreaterThan(rows[0].match.quality, rows[1].match.quality, "keeps the program's order")
        let provider = ExternalProvider(configs[0])
        XCTAssertEqual(provider.keyword, "z")
        XCTAssertTrue(provider.inGlobalSearch)
    }

    func testSettingsPanes() {
        let rows = SettingsPanes.results()
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        let wifi = Catalog(rows).search("wireless").first
        XCTAssertEqual(wifi?.title, "Wi-Fi")
        XCTAssertEqual(wifi?.primary?.command, .openURL("x-apple.systempreferences:com.apple.wifi-settings-extension", bundleID: nil))
    }

    func testMenuBarItemsFlatten() {
        let bar = [
            MenuNode(title: "Apple", children: [MenuNode(title: "About This Mac")]),
            MenuNode(title: "File", children: [
                MenuNode(title: "New Window", shortcut: KeyShortcut(menuKey: "N", axModifiers: 0)),
                MenuNode(title: ""),
                MenuNode(title: "Export", children: [MenuNode(title: "PDF"), MenuNode(title: "Word", enabled: false)]),
                MenuNode(title: "Print", enabled: false),
            ]),
        ]
        let items = MenuBarItems.flatten(bar)
        XCTAssertEqual(items.map(\.path), [["File", "New Window"], ["File", "Export", "PDF"]])
        let rows = MenuBarItems.results(items, app: "Preview", pid: 99)
        XCTAssertEqual(rows[1].subtitle, "Preview › File › Export")
        XCTAssertEqual(rows[0].keys, ["⌘N"])
        XCTAssertEqual(rows[1].primary?.command, .pressMenuItem(pid: 99, path: ["File", "Export", "PDF"]))
    }

    func testQuitProcessesAsksFirst() {
        let provider = ProcessProvider()
        provider.set([ProcessEntry(pid: 10, name: "Safari"), ProcessEntry(pid: 11, name: "Slack")])
        XCTAssertEqual(ProcessProvider.parse("force quit zoom")?.force, true)
        XCTAssertNil(ProcessProvider.parse("quitting"))
        let rows = provider.instantResults(for: LaunchQuery(raw: "quit saf"))
        XCTAssertEqual(rows.map(\.title), ["Quit Safari"])
        XCTAssertEqual(rows[0].match.highlights, [5..<8])
        XCTAssertNotNil(rows[0].primary?.confirmation)
        XCTAssertEqual(rows[0].primary?.command, .quit(pid: 10, force: false))
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "safari")).isEmpty)
    }

    func testDefine() async throws {
        let provider = DefineProvider { word in word == "glaucoma" ? "glaucoma | noun | a condition of increased pressure within the eyeball. It causes gradual loss of sight. THESAURUS: eye disease" : nil }
        XCTAssertEqual(DefineProvider.parse("define glaucoma")?.word, "glaucoma")
        XCTAssertEqual(DefineProvider.parse("syn happy")?.kind, .synonyms)
        XCTAssertNil(DefineProvider.parse("define "))
        let rows = try await provider.results(for: LaunchQuery(raw: "define glaucoma"))
        XCTAssertEqual(rows.first?.title, "glaucoma | noun | a condition of increased pressure within the eyeball.")
        XCTAssertEqual(rows.first?.primary?.command, .lookUp("glaucoma"))
        XCTAssertNotNil(rows.first?.detail)
        let syn = try await provider.results(for: LaunchQuery(raw: "syn glaucoma"))
        XCTAssertEqual(syn.first?.title, "eye disease")
        let none = try await provider.results(for: LaunchQuery(raw: "define xyzzy"))
        XCTAssertTrue(none.isEmpty)
    }

    func testSymbolsIncludeScienceAndEmoji() {
        let symbols = SymbolTable.symbols()
        XCTAssertTrue(symbols.contains { $0.character == "±" })
        XCTAssertTrue(symbols.contains { $0.character == "😀" && $0.name == "grinning face" })
        XCTAssertGreaterThan(symbols.count, 800)
        let rows = SymbolTable.results(symbols)
        let pm = Catalog(rows).search("plusminus").first
        XCTAssertEqual(pm?.accessory, "±")
        XCTAssertEqual(pm?.primary?.command, .paste("±"))
    }
}
