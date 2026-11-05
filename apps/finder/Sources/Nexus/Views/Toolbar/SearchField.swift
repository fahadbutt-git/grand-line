import BrowserKit
import SwiftUI

/// Search this folder (Cmd+F). Typing searches as you go; Escape ends it.
struct SearchField: View {
    @ObservedObject var model: BrowserModel
    let palette: Palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(NexusType.smallSymbol).foregroundStyle(palette.faint)
            TextField("Search this folder", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(NexusType.body)
                .foregroundStyle(palette.strong)
                .focused($focused)
                .onExitCommand { model.endSearch(); focused = false }
                .task(id: model.searchText) {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled, focused else { return }
                    model.search(model.searchText, scope: nil)
                }
            if model.searchText.isEmpty {
                KeyCap(text: "⌘F", palette: palette)
            } else {
                Button { model.endSearch() } label: {
                    Image(systemName: "xmark.circle.fill").font(NexusType.smallSymbol).foregroundStyle(palette.faint)
                }
                .buttonStyle(.plain)
                .help("End the search")
                .accessibilityLabel("End the search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.field))
        // The focus ring, in the theme's accent, while the field has the keys.
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(palette.accent.opacity(focused ? 0.55 : 0), lineWidth: 2)
                .allowsHitTesting(false)
        )
        .onChange(of: model.searchFocused) { _, wanted in
            if wanted { focused = true; model.searchFocused = false }
        }
    }
}
