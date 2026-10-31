import XCTest
@testable import IndexKit

final class PersistenceTests: XCTestCase {
    private var folder = ""

    override func setUpWithError() throws {
        folder = try Fixture.folder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: folder)
    }

    func testSaveAndLoadKeepEverything() async throws {
        let index = Fixture.index(["a/notes.txt", "b/notes.txt", "Café/Résumé.pdf", "c/gone.txt"])
        await index.noteOpened("/Index/b/notes.txt")
        await index.apply([])
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("cache/index.bin")
        try await index.save(to: snapshot)

        let loaded = try FileIndex.load(from: snapshot)
        XCTAssertEqual(loaded.roots, ["/Index"])
        let count = await loaded.count
        XCTAssertEqual(count, 9)
        let notes = await loaded.search("notes")
        XCTAssertEqual(notes.first?.path, "/Index/b/notes.txt")
        let resume = await loaded.search("resume")
        XCTAssertEqual(resume.first?.path, "/Index/Café/Résumé.pdf")
        XCTAssertEqual(resume.first?.highlights, [0..<6])
        let event = await loaded.lastEventID
        XCTAssertEqual(event, 0)
    }

    func testSavingCompactsRemovedEntries() async throws {
        var storage = Fixture.storage(["keep/a.txt", "drop/b.txt"])
        storage.remove(storage.children(of: 0)["drop"]!)
        let index = FileIndex(roots: ["/Index"], exclusions: .standard, storage: storage, lastEventID: 42)
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("index.bin")
        try await index.save(to: snapshot)
        let loaded = try FileIndex.load(from: snapshot)
        let count = await loaded.count
        XCTAssertEqual(count, 3)
        let event = await loaded.lastEventID
        XCTAssertEqual(event, 42)
        let dropped = await loaded.search("b.txt")
        XCTAssertTrue(dropped.isEmpty)
    }

    func testRejectsOtherFiles() throws {
        let junk = URL(fileURLWithPath: folder).appendingPathComponent("junk.bin")
        try Data("not an index at all".utf8).write(to: junk)
        XCTAssertThrowsError(try FileIndex.load(from: junk)) { error in
            XCTAssertEqual(error as? IndexSnapshot.Failure, .notAnIndex)
        }
    }

    func testRejectsTruncatedFiles() async throws {
        let index = Fixture.index(["a/one.txt"])
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("index.bin")
        try await index.save(to: snapshot)
        let whole = try Data(contentsOf: snapshot)
        try whole.prefix(whole.count / 2).write(to: snapshot)
        XCTAssertThrowsError(try FileIndex.load(from: snapshot)) { error in
            XCTAssertEqual(error as? IndexSnapshot.Failure, .truncated)
        }
    }

    func testBuiltIndexRoundTrips() async throws {
        try Fixture.make("Docs/letter.docx", in: folder)
        let index = FileIndex(roots: [folder + "/Docs"])
        await index.build()
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("built.bin")
        try await index.save(to: snapshot)
        let loaded = try FileIndex.load(from: snapshot)
        let paths = await loaded.search("letter").map(\.path)
        XCTAssertEqual(paths, [folder + "/Docs/letter.docx"])
    }
}
