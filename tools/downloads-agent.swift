// Starts the Downloads sorter for macOS. macOS ties the "may use Downloads"
// permission to this one small program, not to bash, so no other script
// gets that access. It runs the sorter as a child and waits for it.
//   downloads-agent run
import Foundation

guard CommandLine.arguments.count == 2, CommandLine.arguments[1] == "run" else {
  FileHandle.standardError.write("usage: downloads-agent run\n".data(using: .utf8)!)
  exit(1)
}
let script = NSHomeDirectory() + "/.grand-line/bin/tidy-downloads"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/bash")
task.arguments = [script]
do { try task.run() } catch { exit(2) }
task.waitUntilExit()
exit(task.terminationStatus)
