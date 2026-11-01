import BrowserKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar (R29): 14 pt text in 30 pt rows, SF Symbols, sections Places,
/// Active projects, Saved searches and Locations with every mounted drive.
struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var sidebar: SidebarModel
    let palette: Palette

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 40)
                ForEach(sidebar.groups) { group in
                    Text(group.section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .contextMenu {
                            Button("Hide \(group.section.title)") { model.services.hideSection(group.section) }
                            Button("Show All in Sidebar") { model.perform(.showAllInSidebar) }
                        }
                    ForEach(group.items) { item in
                        SidebarRow(item: item, isCurrent: isCurrent(item), palette: palette,
                                   open: { open(item) }, eject: { url in model.eject(volumeAt: url) })
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                drop(providers, on: item)
                            }
                            .contextMenu {
                                Button(item.removal == .remove ? "Remove from Sidebar" : "Hide from Sidebar") {
                                    model.services.removeFromSidebar(item)
                                }
                                Button("Show All in Sidebar") { model.perform(.showAllInSidebar) }
                            }
                    }
                }
                Color.clear.frame(height: 12)
            }
        }
        .background(palette.panel)
    }

    private func isCurrent(_ item: SidebarItem) -> Bool {
        switch item.target {
        case .location(let location): return location == model.focused.location
        case .savedSearch(let name):
            if case .search(let query, _) = model.focused.location { return query == model.services.savedSearches.query(named: name) }
            return false
        case .airDrop: return false
        }
    }

    private func open(_ item: SidebarItem) {
        switch item.target {
        case .location(let location): model.focused.go(location)
        case .savedSearch(let name): model.runSavedSearch(name)
        case .airDrop: AirDrop.openWindow()
        }
    }

    /// Dropping files on a folder moves or copies them there, by Finder's rules
    /// and Google Drive's (R14); dropping them on AirDrop sends them.
    private func drop(_ providers: [NSItemProvider], on item: SidebarItem) -> Bool {
        if item.target == .airDrop {
            FileDrop.load(providers) { urls in AirDrop.send(urls) }
            return true
        }
        guard let folder = item.folder else { return false }
        FileDrop.load(providers) { urls in
            model.drop(urls, into: folder, forceCopy: NSEvent.modifierFlags.contains(.option))
        }
        return true
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    let isCurrent: Bool
    let palette: Palette
    let open: () -> Void
    let eject: (URL) -> Void
    @Local private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol)
                .font(.system(size: 14))
                .foregroundStyle(isCurrent ? palette.accent : palette.dim)
                .frame(width: SidebarMetrics.symbolWidth)
            Text(item.title)
                .font(.system(size: SidebarMetrics.fontSize))
                .foregroundStyle(isCurrent ? palette.strong : palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let badge = item.badge {
                Text(badge).font(.system(size: 11)).foregroundStyle(palette.accent).lineLimit(1).fixedSize()
            } else if let detail = item.detail, hovering {
                Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(palette.faint).lineLimit(1).fixedSize()
            }
            if let volume = item.ejectable {
                Button { eject(volume) } label: {
                    Image(systemName: "eject").font(.system(size: 11)).foregroundStyle(palette.dim).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Eject \(item.title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SidebarMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? palette.selection : Color.clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help(item.detail.map { "\(item.title), \($0)" } ?? item.title)
        // A button to VoiceOver and Full Keyboard Access: VO-Space opens it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.badge ?? item.detail ?? "")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(perform: open)
        .accessibilityActions {
            if let volume = item.ejectable {
                Button("Eject \(item.title)") { eject(volume) }
            }
        }
    }
}
