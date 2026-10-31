// Shrinks a PDF by recompressing its images, using Apple's PDFKit.
// Built by setup into ~/.grand-line/.build/pdfshrink.
// Usage: pdfshrink <input.pdf> <output.pdf>

import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count == 3,
      let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: pdfshrink <input.pdf> <output.pdf>\n".data(using: .utf8)!)
    exit(1)
}

let options: [PDFDocumentWriteOption: Any] = [
    .saveImagesAsJPEGOption: true,
    .optimizeImagesForScreenOption: true,
]
if !document.write(to: URL(fileURLWithPath: args[2]), withOptions: options) {
    FileHandle.standardError.write("Could not write \(args[2])\n".data(using: .utf8)!)
    exit(1)
}
