import SwiftUI
import ThemeKit

/// A group of rows under a heading, on a raised card with hairlines between
/// rows, in the theme's colours (DESIGN.md: hairline dividers, no shadows).
public struct SettingsSection<Content: View>: View {
    @EnvironmentObject private var theme: SettingsTheme
    let title: String
    let note: String?
    let content: Content

    public init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.strong)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)
            // Every row draws a hairline above itself; the first one is clipped away.
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -1)
                .clipped()
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairline, lineWidth: 1))
        }
    }
}

/// One line of a section: a title and an optional line of detail on the left,
/// the control on the right.
public struct SettingsRow<Control: View>: View {
    @EnvironmentObject private var theme: SettingsTheme
    let title: String
    let detail: String?
    let symbol: String?
    let control: Control

    public init(_ title: String, detail: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.dim)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }
}

public extension SettingsRow where Control == EmptyView {
    init(_ title: String, detail: String? = nil, symbol: String? = nil) {
        self.init(title, detail: detail, symbol: symbol) { EmptyView() }
    }
}

/// A switch bound to a setting, as a row.
public struct SettingsToggle: View {
    let title: String
    let detail: String?
    let id: String?
    let isOn: Binding<Bool>

    public init(_ title: String, detail: String? = nil, id: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.id = id
        self.isOn = isOn
    }

    public var body: some View {
        SettingsRow(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier(id ?? "")
                .accessibilityLabel(title)
        }
    }
}

/// A pop-up menu bound to a setting, as a row.
public struct SettingsPicker<Value: Hashable>: View {
    let title: String
    let detail: String?
    let id: String?
    let selection: Binding<Value>
    let options: [(Value, String)]

    public init(_ title: String, detail: String? = nil, id: String? = nil, selection: Binding<Value>, options: [(Value, String)]) {
        self.title = title
        self.detail = detail
        self.id = id
        self.selection = selection
        self.options = options
    }

    public var body: some View {
        SettingsRow(title, detail: detail) {
            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier(id ?? "")
            .accessibilityLabel(title)
        }
    }
}

/// Up and down arrows for a row in an ordered list.
public struct ReorderButtons: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    public init(canMoveUp: Bool, canMoveDown: Bool, move: @escaping (Int) -> Void) {
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.move = move
    }

    public var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.up", enabled: canMoveUp, help: "Move up") { move(-1) }
            arrow("chevron.down", enabled: canMoveDown, help: "Move down") { move(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A short line under a control: a result, or why something is off.
public struct SettingsNote: View {
    @EnvironmentObject private var theme: SettingsTheme
    let text: String
    let symbol: String?

    public init(_ text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(theme.dim) }
            Text(text)
                .foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}
