import ArchiveKit
import BrowserKit
import Quartz
import SwiftUI

/// The inline preview pane (R13, Cmd+Shift+P): Quick Look of a single selected
/// item, also inside an archive.
struct PreviewPane: View {
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @Local private var url: URL? = nil

    var body: some View {
        let selection = pane.selectedItems
        VStack(spacing: 0) {
            if selection.count == 1, let url {
                QuickLookPreview(url: url)
                Text(selection[0].name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(8)
            } else {
                Spacer()
                Text(selection.isEmpty ? "No selection" : ItemFormat.count(selection.count) + " selected")
                    .font(.system(size: 13)).foregroundStyle(palette.faint)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .task(id: selection.first?.id ?? "") {
            url = await Self.previewURL(selection.count == 1 ? selection.first : nil, location: pane.location)
        }
    }

    static func previewURL(_ item: FileItem?, location: BrowserLocation) async -> URL? {
        guard let item else { return nil }
        guard let entry = item.archiveEntry, !item.isFolder, case .archive(let archive, _) = location else {
            return item.isInArchive ? nil : item.url
        }
        return await Task.detached { try? Archive.preview(entry, from: archive) }.value
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView(frame: .zero)
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
