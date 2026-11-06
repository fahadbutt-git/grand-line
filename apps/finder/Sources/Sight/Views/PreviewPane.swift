import LauncherKit
import Quartz
import SwiftUI

/// Quick Look for the selected file, or the text of a definition or snippet.
struct PreviewPane: View {
    let row: LaunchResult

    var body: some View {
        if let path = row.previewPath {
            QuickLookView(url: URL(fileURLWithPath: path))
        } else {
            ScrollView {
                Text(row.detail ?? "")
                    .font(Typo.row)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL)?.absoluteString != url.absoluteString { view.previewItem = url as NSURL }
    }
}
