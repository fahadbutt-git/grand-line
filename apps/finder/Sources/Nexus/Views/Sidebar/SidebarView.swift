import BrowserKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar (R29): 14 pt text in 30 pt rows, SF Symbols, sections Places,
/// Active projects, Saved searches and Locations with every mounted drive.
/// It sits on the macOS sidebar material, tinted with the theme's panel
/// colour, and a row is chosen on mouse-down, as in Finder.
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
                        .font(NexusType.section)
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
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
        .background(SidebarBackground(palette: palette))
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
    @Local private var pressed = false

    var body: some View {
        let traits: AccessibilityTraits = isCurrent ? [.isButton, .isSelected] : .isButton
        let value: String = item.badge ?? item.detail ?? ""
        let help: String = item.detail.map { "\(item.title), \($0)" } ?? item.title
        return row
            .help(help)
            // A button to VoiceOver and Full Keyboard Access: VO-Space opens it.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.title)
            .accessibilityValue(value)
            .accessibilityAddTraits(traits)
            .accessibilityAction { open() }
            .accessibilityActions { ejectAction }
    }

    @ViewBuilder private var ejectAction: some View {
        if let volume = item.ejectable {
            Button("Eject \(item.title)") { eject(volume) }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol)
                .font(NexusType.sidebarSymbol)
                .imageScale(.small)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isCurrent ? palette.accent : palette.dim)
                .frame(width: SidebarMetrics.symbolWidth)
            Text(item.title)
                .font(NexusType.sidebar)
                .foregroundStyle(isCurrent ? palette.strong : palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let badge = item.badge {
                Text(badge).font(NexusType.labelNumbers).foregroundStyle(palette.accent).lineLimit(1).fixedSize()
            } else if let detail = item.detail, hovering {
                Text(detail).font(NexusType.labelNumbers).foregroundStyle(palette.faint).lineLimit(1).fixedSize()
            }
            if let volume = item.ejectable {
                Button { eject(volume) } label: {
                    Image(systemName: "eject").font(NexusType.smallSymbol).foregroundStyle(palette.dim).frame(width: 18, height: 18)
                }
                .buttonStyle(ToolbarButtonStyle(palette: palette))
                .help("Eject \(item.title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SidebarMetrics.rowHeight)
        .background(SelectionFill(palette: palette, isSelected: isCurrent, isHovered: hovering || pressed))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        // Opens on mouse-down, as Finder's sidebar does; the row shows it is
        // pressed until the place has loaded under it.
        .onPress({ pressed = true; open() }, release: { _ in pressed = false })
        .onHover { hovering = $0 }
    }
}
