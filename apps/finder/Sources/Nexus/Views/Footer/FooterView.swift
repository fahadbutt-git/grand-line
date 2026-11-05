import BrowserKit
import FileKit
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
            Text(ItemFormat.searchStatus(pane.state.searchCounts, selected: selection.count, total: pane.items.count,
                                         selectedBytes: selectedBytes(selection)))
                .font(NexusType.labelNumbers)
                .foregroundStyle(palette.dim)
                .lineLimit(1)
                .fixedSize()
            if let transfer = services.transfers.summary {
                Button { model.perform(.showTransfers) } label: {
                    HStack(spacing: 4) {
                        ProgressView(value: services.transfers.running?.fraction ?? 0).frame(width: 60)
                        Text(transfer).font(NexusType.label).foregroundStyle(palette.accent).lineLimit(1)
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
                    .font(NexusType.labelNumbers)
                    .foregroundStyle(palette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(palette.panel)
        // With the toolbar hidden, the tasks popover opens from here.
        .popover(isPresented: Binding(get: { model.showTransfers && !model.showToolbar },
                                      set: { if !$0 { model.showTransfers = false } })) {
            TasksView(model: model, services: services, palette: palette)
        }
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
                    Text(hint.label).font(NexusType.label).foregroundStyle(palette.faint).lineLimit(1).fixedSize()
                }
            }
        }
        .fixedSize()
    }
}

/// The tasks popover: each task with its progress and a Stop button, those
/// that ended, and the undo history, where an older step can be undone with
/// everything after it.
struct TasksView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var services: Services
    let palette: Palette

    var body: some View {
        let list = services.transfers
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks").font(NexusType.headline).foregroundStyle(palette.strong)
                Spacer(minLength: 8)
                if !list.ended.isEmpty {
                    Button("Clear") { services.clearEndedTasks() }
                        .buttonStyle(LinkButtonStyle(palette: palette))
                        .font(NexusType.label)
                }
            }
            if list.tasks.isEmpty {
                Text("Nothing running").font(NexusType.callout).foregroundStyle(palette.dim)
            }
            ForEach(list.active) { entry in
                TaskRow(entry: entry, palette: palette) { services.cancelTask(entry.id) }
            }
            ForEach(Array(list.ended.prefix(8))) { entry in
                TaskRow(entry: entry, palette: palette, stop: nil)
            }
            if !services.undoHistory.isEmpty {
                Hairline(palette: palette)
                Text("Undo history").font(NexusType.section).foregroundStyle(palette.dim)
                ForEach(Array(services.undoHistory.prefix(8).enumerated()), id: \.offset) { index, record in
                    HStack(spacing: 8) {
                        Text(TaskTitles.history(record))
                            .font(NexusType.callout).foregroundStyle(palette.text)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(index == 0 ? "Undo" : "Undo to Here") { model.undoHistory(through: index) }
                            .buttonStyle(LinkButtonStyle(palette: palette))
                            .font(NexusType.label)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(palette.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nexus.tasks.popover")
    }
}

struct TaskRow: View {
    let entry: TransferList.Entry
    let palette: Palette
    let stop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.title).font(NexusType.callout).foregroundStyle(palette.text).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if let stop, !entry.cancelling {
                    Button(action: stop) {
                        Image(systemName: "xmark.circle.fill").font(NexusType.callout).foregroundStyle(palette.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                    .accessibilityLabel("Stop " + entry.title)
                }
            }
            if let fraction = entry.fraction {
                ProgressView(value: fraction).controlSize(.small)
            }
            Text(entry.status)
                .font(NexusType.label)
                .foregroundStyle(isFailure ? Color(nsColor: .systemRed) : palette.dim)
                .lineLimit(2)
        }
    }

    private var isFailure: Bool {
        if case .failed = entry.state { return true }
        return false
    }
}
