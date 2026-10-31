import XCTest
@testable import IcebergKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Stream widgets: a script that keeps running and prints a line per update.
final class StreamProcessTests: XCTestCase {
    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func add(_ s: String) { lock.lock(); storage.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    final class ExitBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: StreamExit?
        func set(_ e: StreamExit) { lock.lock(); value = e; lock.unlock() }
        var exit: StreamExit? { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func run(_ command: String, interval: TimeInterval = 0, limit: TimeInterval = 5,
                     after started: ((StreamProcess, Lines) -> Void)? = nil) -> ([String], StreamExit?) {
        let p = StreamProcess(command: command)
        p.minimumInterval = interval
        let lines = Lines()
        let box = ExitBox()
        let ended = expectation(description: "the stream ends")
        XCTAssertTrue(p.start(onLine: { lines.add($0) }, onExit: { box.set($0); ended.fulfill() }))
        started?(p, lines)
        wait(for: [ended], timeout: limit)
        return (lines.all, box.exit)
    }

    func testEveryLineInOrder() {
        let (lines, exit) = run("printf 'one\\ntwo\\n{\"text\": \"three\"}\\n'")
        XCTAssertEqual(lines, ["one", "two", #"{"text": "three"}"#])
        XCTAssertEqual(exit?.exitCode, 0)
        XCTAssertEqual(exit?.lines, 3)
        // A stream is meant to keep going, so ending by itself is a failure.
        XCTAssertEqual(exit?.isFailure, true)
        XCTAssertEqual(exit?.stoppedByRequest, false)
    }

    func testFastScriptsAreThinnedToTheNewestLine() {
        let (lines, exit) = run("i=0; while [ $i -lt 300 ]; do echo $i; i=$((i+1)); done; sleep 0.3", interval: 0.2)
        XCTAssertEqual(exit?.lines, 300)
        XCTAssertLessThan(lines.count, 300)
        XCTAssertEqual(lines.last, "299", "the newest line is always delivered")
    }

    func testStopEndsTheWholeGroup() throws {
        let child = Lines()
        let (lines, exit) = run("sleep 30 & echo $!; wait", limit: 5) { p, seen in
            let deadline = Date().addingTimeInterval(3)
            while seen.all.isEmpty && Date() < deadline { usleep(20_000) }
            if let first = seen.all.first { child.add(first) }
            p.stop()
        }
        XCTAssertEqual(exit?.stoppedByRequest, true)
        XCTAssertEqual(exit?.isFailure, false)
        XCTAssertEqual(lines.count, 1)
        let pid = try XCTUnwrap(child.all.first.flatMap { Int32($0) })
        // The background sleep went with it.
        let deadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0 && Date() < deadline { usleep(20_000) }
        XCTAssertNotEqual(kill(pid, 0), 0, "the stream's child is still running")
    }

    func testErrorsAreKeptForTheReason() {
        let (_, exit) = run("echo 'no such device' >&2; exit 3")
        XCTAssertEqual(exit?.exitCode, 3)
        XCTAssertEqual(exit?.reason, "no such device (exit 3)")
    }

    func testUnstartableShell() {
        let p = StreamProcess(command: "echo hi")
        p.shell = "/nonexistent/sh"
        let box = ExitBox()
        XCTAssertFalse(p.start(onLine: { _ in }, onExit: { box.set($0) }))
        XCTAssertNotNil(box.exit?.launchError)
        XCTAssertFalse(p.isRunning)
    }

    func testStartsOnlyOnce() {
        let p = StreamProcess(command: "sleep 5")
        let box = ExitBox()
        let ended = expectation(description: "ends")
        XCTAssertTrue(p.start(onLine: { _ in }, onExit: { box.set($0); ended.fulfill() }))
        XCTAssertFalse(p.start(onLine: { _ in }, onExit: { _ in }))
        XCTAssertTrue(p.isRunning)
        p.stop()
        wait(for: [ended], timeout: 3)
        XCTAssertFalse(p.isRunning)
    }

    func testWorkingFolderAndUnbufferedPython() {
        let tmp = TempFolder()
        tmp.write("value.txt", "from file\n")
        let p = StreamProcess(command: "cat value.txt; echo \"$PYTHONUNBUFFERED\"", workingDirectory: tmp.url)
        p.minimumInterval = 0
        let lines = Lines()
        let ended = expectation(description: "ends")
        p.start(onLine: { lines.add($0) }, onExit: { _ in ended.fulfill() })
        wait(for: [ended], timeout: 5)
        XCTAssertEqual(lines.all, ["from file", "1"])
    }
}
