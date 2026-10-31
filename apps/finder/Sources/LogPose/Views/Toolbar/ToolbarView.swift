import BrowserKit
import FileKit
import SwiftUI

/// Back and forward, the path bar (R5), the five views (R28) and search (R3).
struct ToolbarView: View {
    @ObservedObject var model: BrowserModel
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if !model.showSidebar { Color.clear.frame(width: 70) }
                SymbolButton(symbol: "chevron.left", help: "Back  ⌘[", palette: palette,
                             isEnabled: model.isEnabled(.back)) { model.perform(.back) }
                SymbolButton(symbol: "chevron.right", help: "Forward  ⌘]", palette: palette,
                             isEnabled: model.isEnabled(.forward)) { model.perform(.forward) }
                SymbolButton(symbol: "arrow.up", help: "Enclosing Folder  ⌘↑", palette: palette,
                             isEnabled: model.isEnabled(.enclosingFolder)) { model.perform(.enclosingFolder) }
                if model.showPathBar || model.editingPath {
                    PathBarView(model: model, pane: model.focused, palette: palette)
                        .layoutPriority(1)
                } else {
                    Spacer(minLength: 0)
                }
                ViewModePicker(model: model, palette: palette)
                SearchField(model: model, palette: palette)
                    .frame(width: 220)
                SymbolButton(symbol: "sidebar.right", help: "Inspector  ⌥⌘I", palette: palette,
                             isOn: model.showInspector) { model.perform(.toggleInspector) }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            if case .search(let query, let scope) = model.focused.location {
                SearchChips(model: model, query: query, scope: scope, palette: palette)
            }
        }
        .background(palette.background)
    }
}

struct ViewModePicker: View {
    @ObservedObject var model: BrowserModel
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                SymbolButton(symbol: mode.symbol, help: "View \(mode.title)  ⌘\(mode.number)", palette: palette,
                             isOn: model.mode == mode) {
                    model.perform([.viewIcons, .viewList, .viewColumns, .viewGallery, .viewPanes][mode.number - 1])
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.field))
        .fixedSize()
    }
}

/// Scope chips widen the search (R3); the rest describe the query in words (R2).
struct SearchChips: View {
    @ObservedObject var model: BrowserModel
    let query: String
    let scope: SearchScope
    let palette: Palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchScope.chips(from: model.searchFolder?.path), id: \.self) { chip in
                    Chip(title: title(of: chip), symbol: chip.symbol, palette: palette, isOn: chip == scope) {
                        model.focused.replace(.search(query: query, scope: chip))
                    }
                    .accessibilityIdentifier(identifier(of: chip))
                }
                Rectangle().fill(palette.line).frame(width: 1, height: 14)
                ForEach(model.queryChips(query), id: \.self) { text in
                    Chip(title: text, palette: palette)
                }
                Spacer(minLength: 0)
                Button("Save Search…") { model.perform(.saveSearch) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accent)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 30)
    }

    /// The folder chip by the name Finder shows ("Trash", not ".Trash").
    private func title(of chip: SearchScope) -> String {
        guard case .folder(let path) = chip, path != "/" else { return chip.title }
        if URL(fileURLWithPath: path).standardizedFileURL.path == model.services.paths.trash.standardizedFileURL.path { return "Trash" }
        return FileManager.default.displayName(atPath: path)
    }

    private func identifier(of chip: SearchScope) -> String {
        switch chip {
        case .folder: return "logpose.scope.folder"
        case .home: return "logpose.scope.home"
        case .drive: return "logpose.scope.drive"
        case .mac: return "logpose.scope.mac"
        }
    }
}

extension BrowserModel {
    /// The folder a search started from, for its narrowest chip.
    var searchFolder: URL? {
        if case .search(_, .folder(let path)) = focused.location { return URL(fileURLWithPath: path) }
        for location in focused.state.history.backStack.reversed() {
            if let folder = location.folderURL { return folder }
        }
        return nil
    }

    func queryChips(_ query: String) -> [String] {
        SearchPlan.make(
            query, scope: .home, home: services.paths.home.path, drives: [],
            savedSearch: { [services] in services.savedSearches.query(named: $0) }
        ).chips
    }
}
