import BrowserKit
import SwiftUI

/// View Options (Cmd+J), as in Finder: sort, grouping, folders on top, icon size, hidden files, and
/// whether this folder keeps its own view (R6).
struct ViewOptionsView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pane.location.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.strong)
                .lineLimit(1)
                .truncationMode(.middle)
            Picker("Sort By", selection: sortBinding) {
                ForEach(SortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            .font(.system(size: 13))
            Picker("Group By", selection: orderBinding(\.grouping)) {
                ForEach(ItemGrouping.allCases, id: \.self) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .font(.system(size: 13))
            Toggle("Keep folders on top", isOn: orderBinding(\.foldersFirst))
                .font(.system(size: 13))
            HStack(spacing: 8) {
                Text("Icon size").font(.system(size: 13)).foregroundStyle(palette.text).lineLimit(1).fixedSize()
                Slider(value: iconBinding, in: ViewSettings.iconSizes, step: 16)
            }
            Toggle("Show hidden files", isOn: Binding(get: { model.showHidden }, set: { _ in model.perform(.toggleHidden) }))
                .font(.system(size: 13))
            Divider()
            HStack(spacing: 8) {
                Button("Remember for This Folder") { model.perform(.rememberView) }
                    .lineLimit(1).fixedSize()
                Button("Use as Default") { model.perform(.useAsDefaultView) }
                    .lineLimit(1).fixedSize()
            }
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(palette.panel)
    }

    private var sortBinding: Binding<SortField> {
        Binding(
            get: { pane.state.settings.sort.field },
            set: { field in model.choose(pane, sort: field) }
        )
    }

    /// One part of the sort, changed on its own.
    private func orderBinding<Value>(_ part: WritableKeyPath<ItemSort, Value>) -> Binding<Value> {
        Binding(
            get: { pane.state.settings.sort[keyPath: part] },
            set: { value in
                var settings = pane.state.settings
                settings.sort[keyPath: part] = value
                pane.setSettings(settings)
            }
        )
    }

    private var iconBinding: Binding<Double> {
        Binding(
            get: { pane.state.settings.iconSize },
            set: { size in
                var settings = pane.state.settings
                settings.iconSize = size
                pane.setSettings(settings)
            }
        )
    }
}
