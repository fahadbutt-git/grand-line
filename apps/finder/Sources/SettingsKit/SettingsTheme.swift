import AppKit
import Combine
import SwiftUI
import ThemeKit

/// The theme the Settings window draws with, kept current from the app's own
/// theme store, so the window recolours with every `theme set`.
@MainActor
public final class SettingsTheme: ObservableObject {
    @Published public private(set) var theme: Theme
    private var sink: AnyCancellable?

    public init(_ theme: Theme, updates: AnyPublisher<Theme, Never>) {
        self.theme = theme
        sink = updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fresh in
                MainActor.assumeIsolated {
                    guard let self, fresh != self.theme else { return }
                    self.theme = fresh
                }
            }
    }

    public var background: Color { Color(theme.background) }
    public var panel: Color { Color(theme.panel) }
    public var field: Color { Color(theme.field) }
    public var line: Color { Color(theme.line) }
    public var hairline: Color { Color(theme.hairline) }
    public var text: Color { Color(theme.text) }
    public var strong: Color { Color(theme.strong) }
    public var dim: Color { Color(theme.dim) }
    public var faint: Color { Color(theme.faint) }
    public var selection: Color { Color(theme.selection) }
    public var selectionText: Color { Color(theme.selectionText) }
    public var accent: Color { Color(theme.accent) }
    public var highlight: Color { Color(theme.highlight) }
    public var chip: Color { Color(theme.chip) }
    public var colorScheme: ColorScheme { theme.colorScheme }
    public var appearance: NSAppearance? { NSAppearance(named: theme.appearanceName) }
}
