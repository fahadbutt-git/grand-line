import XCTest
@testable import BrowserKit

final class SelectionTests: XCTestCase {
    let order = ["a", "b", "c", "d", "e"]

    func testClickToggleAndShiftRange() {
        var selection = SelectionModel()
        selection.select("b")
        XCTAssertEqual(selection.ordered(in: order), ["b"])
        selection.toggle("d")
        XCTAssertEqual(selection.ordered(in: order), ["b", "d"])
        selection.toggle("b")
        XCTAssertEqual(selection.ordered(in: order), ["d"])
        selection.extend(to: "a", in: order)
        XCTAssertEqual(selection.ordered(in: order), ["a", "b", "c", "d"])
    }

    func testArrowsMoveAndExtend() {
        var selection = SelectionModel()
        selection.move(by: 1, in: order)
        XCTAssertEqual(selection.ordered(in: order), ["a"], "Down with nothing selected picks the first")
        selection.move(by: 1, in: order)
        selection.move(by: 1, in: order, extending: true)
        XCTAssertEqual(selection.ordered(in: order), ["b", "c"])
        selection.move(by: 10, in: order)
        XCTAssertEqual(selection.ordered(in: order), ["e"], "stops at the end")
        selection.move(by: -3, in: order)
        XCTAssertEqual(selection.ordered(in: order), ["b"], "grid steps move by a row")
    }

    func testSelectAllClearAndPrune() {
        var selection = SelectionModel()
        selection.selectAll(order)
        XCTAssertEqual(selection.count, 5)
        selection.prune(to: ["a", "c"])
        XCTAssertEqual(selection.ordered(in: order), ["a", "c"])
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testSetKeepsOnlyShownItems() {
        var selection = SelectionModel()
        selection.set(["c", "zz", "a"], in: order)
        XCTAssertEqual(selection.ordered(in: order), ["a", "c"])
        XCTAssertEqual(selection.cursor, "a")
    }

    func testTypeSelect() {
        var typing = TypeSelect()
        let names = ["Analysis", "cornea notes.md", "Cover letter.docx", "glaucoma.R"]
        let now = Date()
        XCTAssertEqual(typing.type("c", names: names, at: now), 1)
        XCTAssertEqual(typing.type("ov", names: names, at: now.addingTimeInterval(0.3)), 2)
        XCTAssertEqual(typing.type("g", names: names, at: now.addingTimeInterval(5)), 3, "a pause starts over")
        XCTAssertNil(typing.type("q", names: names, at: now.addingTimeInterval(5.1)))
    }
}
