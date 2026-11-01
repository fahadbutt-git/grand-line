import XCTest
@testable import IcebergKit

final class CommandRunnerTests: XCTestCase {
    let runner = CommandRunner()

    func testOutputAndExitCode() {
        let r = runner.run("echo hello; echo oops >&2; exit 3", timeout: 5)
        XCTAssertEqual(r.stdout, "hello\n")
        XCTAssertEqual(r.stderr, "oops\n")
        XCTAssertEqual(r.exitCode, 3)
        XCTAssertFalse(r.timedOut)
        XCTAssertNil(r.launchError)
    }

    func testWorkingDirectoryAndEnvironment() {
        let tmp = TempFolder()
        tmp.write("value.txt", "from file\n")
        let r = runner.run("cat value.txt; echo \"$GRAND_LINE_ICEBERG_WIDGET\"", timeout: 5,
                           workingDirectory: tmp.url, extraEnvironment: ["GRAND_LINE_ICEBERG_WIDGET": "sample"])
        XCTAssertEqual(r.stdout, "from file\nsample\n")
    }

    func testMissingFolderIsReported() {
        let r = runner.run("echo never", timeout: 5, workingDirectory: URL(fileURLWithPath: "/nonexistent/folder"))
        XCTAssertEqual(r.exitCode, 126)
        XCTAssertEqual(r.stdout, "")
        XCTAssertTrue(r.stderr.contains("missing"))
    }

    func testPathIncludesPackageTools() {
        let env = CommandRunner.defaultEnvironment(home: "/Users/me", base: ["PATH": "/usr/bin:/bin"])
        XCTAssertEqual(env["PATH"], "/Users/me/.grand-line/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(env["HOME"], "/Users/me")
        XCTAssertNotNil(env["LANG"])
    }

    func testStdinIsEmpty() {
        // A command that reads stdin must not hang waiting for it.
        let r = runner.run("cat; echo done", timeout: 5)
        XCTAssertEqual(r.stdout, "done\n")
    }

    func testHangingCommandIsKilledAfterTimeout() {
        let started = Date()
        let r = runner.run("echo started; sleep 30; echo never", timeout: 1)
        let took = Date().timeIntervalSince(started)
        XCTAssertTrue(r.timedOut)
        XCTAssertEqual(r.stdout, "started\n")
        XCTAssertLessThan(took, 3, "returned after \(took) s")
        XCTAssertNotNil(r.signal)
    }

    func testCommandIgnoringSIGTERMIsKilled() {
        let started = Date()
        let r = runner.run("trap '' TERM; while :; do sleep 0.1; done", timeout: 1)
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(r.signal, SIGKILL)
    }

    func testChildrenOfAHungCommandAreKilledToo() {
        let tmp = TempFolder()
        let marker = tmp.url.appendingPathComponent("child-alive")
        // The child would write the marker after 2 s if it survived.
        _ = runner.run("(sleep 2; touch '\(marker.path)') & sleep 30", timeout: 0.5)
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testBackgroundChildDoesNotBlockTheResult() {
        // The command ends at once but leaves a child holding stdout open.
        let started = Date()
        let r = runner.run("sleep 5 & echo quick", timeout: 4)
        XCTAssertEqual(r.stdout, "quick\n")
        XCTAssertFalse(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testOutputIsCapped() {
        var small = CommandRunner()
        small.maxOutputBytes = 1000
        let r = small.run("yes abcdefgh | head -c 200000", timeout: 5)
        XCTAssertEqual(r.stdout.utf8.count, 1000)
        XCTAssertTrue(r.truncated)
        XCTAssertFalse(r.timedOut)
    }

    func testMissingShellIsALaunchError() {
        var broken = CommandRunner()
        broken.shell = "/nonexistent/sh"
        let r = broken.run("echo hi", timeout: 2)
        XCTAssertNotNil(r.launchError)
    }

    /// A command that ends normally but left `helper &` running: the helper
    /// goes with it, so refreshes cannot pile up orphans.
    func testBackgroundChildOfANormalRunIsKilled() throws {
        let r = runner.run("sleep 30 & echo $!", timeout: 5)
        XCTAssertFalse(r.timedOut)
        XCTAssertEqual(r.exitCode, 0)
        let child = try XCTUnwrap(pid_t(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = Date().addingTimeInterval(2)
        while kill(child, 0) == 0 && Date() < deadline { usleep(20_000) }
        XCTAssertNotEqual(kill(child, 0), 0, "the background sleep is still running")
    }

    /// A child that leaves the group on purpose (a new session) outlives the run.
    func testChildInItsOwnSessionOutlivesTheRun() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { throw XCTSkip("no perl") }
        let r = runner.run("/usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sleep 3 >/dev/null 2>&1 </dev/null & echo $!; sleep 0.5", timeout: 5)
        let child = try XCTUnwrap(pid_t(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        usleep(300_000)
        XCTAssertEqual(kill(child, 0), 0)
        kill(child, SIGKILL)
    }

    /// After the leader is reaped its bare pid may belong to someone else:
    /// only its group is signalled then. Stand-in for "someone else": a live
    /// process that is not a group leader.
    func testReapedLeaderIsNeverSignalledByBarePid() throws {
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/bin/sleep")
        other.arguments = ["30"]
        try other.run()
        defer { other.terminate(); other.waitUntilExit() }
        let pid = other.processIdentifier
        guard getpgid(pid) != pid else { throw XCTSkip("the stand-in leads its own group here") }

        XCTAssertFalse(ProcessGroup.signal(pid, SIGKILL, leaderReaped: true))
        usleep(100_000)
        XCTAssertTrue(other.isRunning, "a reaped leader's pid must not be signalled")

        // Before reaping, the fallback to the pid is allowed.
        XCTAssertTrue(ProcessGroup.signal(pid, 0, leaderReaped: false))
        XCTAssertFalse(ProcessGroup.signal(0, SIGKILL, leaderReaped: false), "pid 0 is never signalled")
    }
}
