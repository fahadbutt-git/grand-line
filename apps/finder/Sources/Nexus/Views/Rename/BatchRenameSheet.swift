import AppKit
import BrowserKit
import SwiftUI

/// Rename N Items (F2 or File › Rename with several items selected, as in
/// Finder): Replace Text, Add Text and Format, plus a regular expression and
/// case changes, with every new name shown before anything changes. Rename
/// runs as one task that one Undo reverses.
struct BatchRenameSheet: View {
    @ObservedObject var model: BrowserModel
    let items: [URL]
    let palette: Palette
    @Local private var rename = BatchRename()
    @Local private var listings: [URL: Set<String>] = [:]
    @Local private var now = Date()

    var body: some View {
        let rows = rename.preview(items, date: now) { listings[$0] ?? [] }
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(ItemFormat.count(items.count))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.strong)
            Picker("", selection: $rename.mode) {
                ForEach(BatchRename.Mode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("nexus.rename.mode")
            fields
            HStack(spacing: 12) {
                Picker("Case", selection: $rename.textCase) {
                    ForEach(BatchRename.TextCase.allCases, id: \.self) { textCase in Text(textCase.title).tag(textCase) }
                }
                .fixedSize()
                Toggle("Change the extension too", isOn: $rename.includeExtension)
            }
            .font(.system(size: 13))
            preview(rows)
            HStack {
                Text(summary(rows))
                    .font(.system(size: 11))
                    .foregroundStyle(rows.contains { $0.problem != nil } ? Color(nsColor: .systemRed) : palette.dim)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    model.renameItems(rows)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!BatchRename.canApply(rows))
                .accessibilityIdentifier("nexus.rename.apply")
            }
        }
        .padding(20)
        .frame(width: 580)
        .background(palette.panel)
        .onAppear(perform: readFolders)
    }

    @ViewBuilder private var fields: some View {
        switch rename.mode {
        case .replace:
            textField("Find", $rename.find, id: "nexus.rename.find")
            textField("Replace with", $rename.replacement, id: "nexus.rename.replace")
            Toggle("Match case", isOn: $rename.matchCase).font(.system(size: 13))
        case .regex:
            textField("Pattern, such as (\\d+)-(.*)", $rename.find, id: "nexus.rename.find")
            textField("Replace with, using $1, $2", $rename.replacement, id: "nexus.rename.replace")
            HStack {
                Toggle("Match case", isOn: $rename.matchCase).font(.system(size: 13))
                if let problem = rename.patternProblem {
                    Text(problem).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemRed))
                }
            }
        case .add:
            HStack {
                textField("Text to add", $rename.addText, id: "nexus.rename.add")
                Picker("", selection: $rename.addPosition) {
                    ForEach(BatchRename.Position.allCases, id: \.self) { position in Text(position.title).tag(position) }
                }
                .labelsHidden()
                .fixedSize()
            }
        case .format:
            HStack {
                Picker("", selection: $rename.format) {
                    ForEach(BatchRename.Format.allCases, id: \.self) { format in Text(format.title).tag(format) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("", selection: $rename.formatPosition) {
                    ForEach(BatchRename.Position.allCases, id: \.self) { position in Text(position.title).tag(position) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                textField("Custom format, such as Trip", $rename.customFormat, id: "nexus.rename.format")
                if rename.format != .date {
                    Text("Start at").font(.system(size: 13)).foregroundStyle(palette.dim)
                    TextField("1", value: $rename.startAt, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
    }

    private func textField(_ placeholder: String, _ text: Binding<String>, id: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .accessibilityIdentifier(id)
    }

    private func preview(_ rows: [BatchRename.Row]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(500).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text(row.old).foregroundStyle(palette.dim).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(palette.faint)
                        Text(row.new)
                            .foregroundStyle(row.problem != nil ? Color(nsColor: .systemRed) : (row.changes ? palette.strong : palette.dim))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(row.problem ?? "")
                    }
                    .font(.system(size: 12))
                    .frame(height: 22)
                }
            }
            .padding(8)
        }
        .frame(height: 200)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.field))
        .accessibilityIdentifier("nexus.rename.preview")
    }

    private func summary(_ rows: [BatchRename.Row]) -> String {
        if let problem = rows.first(where: { $0.problem != nil }) {
            return "\(problem.new): \(problem.problem ?? "")"
        }
        let changing = rows.filter(\.changes).count
        return changing == 0 ? "No names change yet." : "\(ItemFormat.count(changing)) will be renamed. Undo puts every name back."
    }

    /// The names already in each folder, read once, so clashes show in the preview.
    private func readFolders() {
        var found: [URL: Set<String>] = [:]
        for folder in Set(items.map { $0.deletingLastPathComponent() }) {
            found[folder] = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        }
        listings = found
        now = Date()
    }

    private func close() {
        model.batchRenameItems = []
    }
}
