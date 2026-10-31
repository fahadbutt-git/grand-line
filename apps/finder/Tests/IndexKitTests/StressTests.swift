import XCTest
@testable import IndexKit

/// A million made-up names. The time limit (R1) is checked in release builds:
/// `swift test -c release -Xswiftc -enable-testing --filter StressTests`.
/// Debug builds check the results and a loose limit.
final class StressTests: XCTestCase {
    static let words = [
        "alpha", "bravo", "cedar", "delta", "ember", "fjord", "harbor", "indigo", "juniper", "kestrel",
        "lumen", "meadow", "nectar", "orbit", "pepper", "quartz", "raven", "saffron", "timber", "umber",
        "velvet", "willow", "xenon", "yarrow", "zephyr", "budget", "draft", "summary", "invoice", "photo",
    ]
    static let extensions = ["pdf", "docx", "txt", "png", "xlsx", "md", "swift", "csv"]

    static func millionNames() -> IndexStorage {
        var storage = IndexStorage()
        let root = storage.addRoot("/Stress")
        var seed: UInt64 = 42
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        for f in 0..<1_000 {
            let folder = storage.add("Folder \(f) \(words[f % words.count])", parent: root, isFolder: true)
            for i in 0..<999 {
                if f == 500 && i == 500 {
                    storage.add("Glaucoma Review Notes.docx", parent: folder, isFolder: false)
                    continue
                }
                let a = words[next() % words.count]
                let b = words[next() % words.count]
                let c = words[next() % words.count]
                let ext = extensions[next() % extensions.count]
                storage.add("\(a)_\(b)-\(c) \(i).\(ext)", parent: folder, isFolder: false)
            }
        }
        return storage
    }

    func testMillionNames() async {
        let storage = Self.millionNames()
        XCTAssertEqual(storage.count, 1_000_001)
        let index = FileIndex(roots: ["/Stress"], exclusions: .standard, storage: storage, lastEventID: 0)

        #if DEBUG
        let limit = 5.0
        #else
        let limit = 0.1
        #endif

        let cases: [(query: String, best: String?)] = [
            ("glau rn", "Glaucoma Review Notes.docx"),
            ("glaucoma review", "Glaucoma Review Notes.docx"),
            ("notes.docx", "Glaucoma Review Notes.docx"),
            ("budget", nil),
            ("a", nil),
            ("qzx", nil),
        ]
        for (query, best) in cases {
            _ = await index.search(query, limit: 50)
            let start = Date()
            let results = await index.search(query, limit: 50)
            let elapsed = Date().timeIntervalSince(start)
            print("search \"\(query)\": \(results.count) results in \(Int(elapsed * 1000)) ms")
            XCTAssertLessThan(elapsed, limit, query)
            if let best { XCTAssertEqual(results.first?.name, best, query) }
        }

        let budget = await index.search("budget", limit: 50)
        XCTAssertEqual(budget.count, 50)
        let weak = budget.filter { $0.tier > .wordStart }
        XCTAssertTrue(weak.isEmpty, "weaker matches ranked in: \(weak.prefix(5).map { "\($0.name) \($0.tier)" })")
        let nothing = await index.search("qzx")
        XCTAssertTrue(nothing.isEmpty)
    }

    func testRescanInAMillion() async {
        let index = FileIndex(roots: ["/Stress"], exclusions: .standard, storage: Self.millionNames(), lastEventID: 0)
        let start = Date()
        // The folder does not exist on disk, so the rescan removes it and its 999 files.
        await index.apply([FolderChange(path: "/Stress/Folder 3 delta")])
        let elapsed = Date().timeIntervalSince(start)
        let count = await index.count
        XCTAssertEqual(count, 1_000_001 - 1_000)
        XCTAssertLessThan(elapsed, 5)
    }
}
