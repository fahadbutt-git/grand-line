// Sets or reads the default app for file types through NSWorkspace, the API
// Finder itself uses, then reads the result back so a silent refusal shows.
//   setdefault /Applications/WordCraft.app docx doc odt   set, then confirm
//   setdefault --uti docx                                print the type identifier
// Exit codes: 0 done, 1 usage, 2 macOS kept another app, 3 unknown type or app.
import AppKit
import CoreServices
import UniformTypeIdentifiers

func current(_ type: UTType) -> String? {
  NSWorkspace.shared.urlForApplication(toOpen: type)?.path
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
  FileHandle.standardError.write("usage: setdefault APP.app EXT... | setdefault --uti EXT\n".data(using: .utf8)!)
  exit(1)
}

if args[0] == "--uti" {
  guard let type = UTType(filenameExtension: args[1]) else { exit(3) }
  print(type.identifier)
  exit(0)
}

let app = URL(fileURLWithPath: args[0])
guard FileManager.default.fileExists(atPath: app.path) else {
  print("no app at \(app.path)"); exit(3)
}
// Register first, so an app copied in moments ago is known to macOS.
LSRegisterURL(app as CFURL, true)

var status: Int32 = 0
for ext in args.dropFirst() {
  let clean = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
  guard let type = UTType(filenameExtension: clean) else {
    print(".\(clean): unknown file type"); status = 3; continue
  }
  let done = DispatchSemaphore(value: 0)
  var failure: Error?
  NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
    failure = error; done.signal()
  }
  _ = done.wait(timeout: .now() + 10)
  let now = current(type) ?? "nothing"
  if now == app.path {
    print(".\(clean): \(app.lastPathComponent)")
  } else {
    print(".\(clean): macOS kept \(now)\(failure.map { " (\($0.localizedDescription))" } ?? "")")
    status = max(status, 2)
  }
}
exit(status)
