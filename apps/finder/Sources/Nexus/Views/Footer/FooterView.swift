import BrowserKit
import SwiftUI

/// The status bar: what is selected, transfers running (R8), the keys for
/// where you are, and true free space (R9).
struct FooterView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    @ObservedObject var services: Services
    let palette: Palette

    var body: some View {
        let selection = pane.selectedItems
        HStack(spacing: 12) {
            Text(ItemFormat.status(selected: selection.count, total: pane.items.count, selectedBytes: selectedBytes(selection)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(palette.dim)
                .lineLimit(1)
                .fixedSize()
            if let transfer = services.transfers.summary {
                Button { model.perform(.showTransfers) } label: {
                    HStack(spacing: 4) {
                        ProgressView(value: services.transfers.running?.fraction ?? 0).frame(width: 60)
                        Text(transfer).font(.system(size: 11)).foregroundStyle(palette.accent).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            ViewThatFits(in: .horizontal) {
                hints(FooterHints.hints(inArchive: pane.location.isArchive, inTrash: pane.inTrash,
                                        paneCount: model.mode == .panes ? model.layout.count : 1,
                                        searching: isSearching))
                hints(Array(FooterHints.hints(inArchive: pane.location.isArchive, inTrash: pane.inTrash,
                                              paneCount: model.mode == .panes ? model.layout.count : 1,
                                              searching: isSearching).prefix(3)))
                Color.clear.frame(width: 1)
            }
            .frame(maxWidth: .infinity)
            if let free = pane.freeSpace {
                Text(ItemFormat.free(free))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(palette.panel)
        .popover(isPresented: $model.showTransfers) { TransfersView(transfers: services.transfers, palette: palette) }
    }

    private var isSearching: Bool {
        if case .search = pane.location { return true }
        return false
    }

    /// Files are summed at once; folders once their size is measured.
    private func selectedBytes(_ items: [FileItem]) -> Int64? {
        guard !items.isEmpty else { return nil }
        var total: Int64 = 0
        for item in items {
            if let size = item.size { total += size } else if let size = pane.state.folderSizes[item.path] { total += size } else { return nil }
        }
        return total
    }

    private func hints(_ list: [FooterHint]) -> some View {
        HStack(spacing: 10) {
            ForEach(list, id: \.self) { hint in
                HStack(spacing: 4) {
                    KeyCap(text: hint.keys, palette: palette)
                    Text(hint.label).font(.system(size: 11)).foregroundStyle(palette.faint).lineLimit(1).fixedSize()
                }
            }
        }
        .fixedSize()
    }
}

struct TransfersView: View {
    let transfers: TransferList
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transfers").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.strong)
            if let running = transfers.running {
                ProgressView(value: running.fraction) { Text(transfers.summary ?? "").foregroundStyle(palette.text).lineLimit(1) }
            }
            ForEach(Array(transfers.done.prefix(8).enumerated()), id: \.offset) { _, done in
                Text("\(done.kind.rawValue): \(ItemFormat.count(done.files, "file")), \(ItemFormat.size(done.bytes))")
                    .font(.system(size: 12)).foregroundStyle(palette.dim).lineLimit(1)
            }
            if transfers.done.isEmpty, transfers.running == nil {
                Text("Nothing running").font(.system(size: 12)).foregroundStyle(palette.dim)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(palette.panel)
    }
}
