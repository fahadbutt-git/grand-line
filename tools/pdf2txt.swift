// Prints the text of a PDF, so it can go to an AI as plain text instead of
// page images (far fewer tokens). Scanned PDFs have no text: run OCR first.
//   pdf2txt paper.pdf > paper.txt
import Foundation
import PDFKit

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write("usage: pdf2txt FILE.pdf\n".data(using: .utf8)!)
  exit(1)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
  FileHandle.standardError.write("cannot open \(CommandLine.arguments[1])\n".data(using: .utf8)!)
  exit(2)
}
for i in 0..<doc.pageCount {
  if let text = doc.page(at: i)?.string { print(text) }
}
