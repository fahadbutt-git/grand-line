import AppKit
import SwiftUI

/// One pane of a Settings window: a sidebar entry and what it shows.
public struct SettingsPane: Identifiable {
    public let id: String
    public let title: String
    public let symbol: String
    let content: () -> AnyView

    public init<Content: View>(_ id: String, title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = { AnyView(content()) }
    }
}

/// Which pane is showing; the app can switch it (`sight://settings/search`).
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var pane: String

    init(_ pane: String) {
        self.pane = pane
    }
}

/// Whether the Settings window is on screen, for panes that keep something
/// fresh while it is (the index status): they stop when it closes, is
/// minimised or is covered.
@MainActor
final class SettingsVisibility: ObservableObject {
    @Published var isVisible = false
}

private struct SettingsWindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the Settings window is closed, minimised or covered.
    public var settingsWindowVisible: Bool {
        get { self[SettingsWindowVisibleKey.self] }
        set { self[SettingsWindowVisibleKey.self] = newValue }
    }
}

/// A standard macOS settings window, laid out like System Settings: the
/// panes in a translucent sidebar on the left, the chosen one on the right.
/// It draws nothing of its own colour: the window, the sidebar material, the
/// selection and the text all come from macOS, so it follows Light and Dark,
/// the accent colour and the accessibility display options as they change.
/// Every sidebar entry has the accessibility identifier
/// `<app>.settings.<pane>`, and the pane itself `<app>.settings.<pane>.pane`,
/// so the journey tests can open each one.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public let appName: String
    public let idPrefix: String
    public private(set) var window: NSWindow?
    /// Called as the window becomes and stops being the key window, so an app
    /// without a menu bar of its own can put one up while it is in front.
    public var onKeyChange: ((Bool) -> Void)?

    private let panes: [SettingsPane]
    private let selection: SettingsSelection
    private let visibility = SettingsVisibility()

    /// The frame is remembered under "<App> Settings".
    public init(appName: String, idPrefix: String, panes: [SettingsPane]) {
        self.appName = appName
        self.idPrefix = idPrefix
        self.panes = panes
        self.selection = SettingsSelection(panes.first?.id ?? "")
    }

    public var paneIDs: [String] { panes.map(\.id) }

    /// Brings the window forward, on `pane` if given (an unknown one is ignored).
    public func show(pane: String? = nil) {
        if let pane, panes.contains(where: { $0.id == pane }) { selection.pane = pane }
        let window = self.window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        updateVisibility()
    }

    private func updateVisibility(closing: Bool = false) {
        guard let window else { return }
        let visible = !closing && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if visibility.isVisible != visible { visibility.isVisible = visible }
    }

    public func windowDidChangeOcclusionState(_ notification: Notification) { updateVisibility() }
    public func windowDidMiniaturize(_ notification: Notification) { updateVisibility() }
    public func windowDidDeminiaturize(_ notification: Notification) { updateVisibility() }
    public func windowWillClose(_ notification: Notification) { updateVisibility(closing: true) }

    public var isVisible: Bool { window?.isVisible ?? false }

    private func make() -> NSWindow {
        let root = SettingsRootView(appName: appName, idPrefix: idPrefix, panes: panes, selection: selection, visibility: visibility)
        // Full size content: the sidebar's material runs up under the title
        // bar, as in System Settings, and the title itself is not drawn.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "\(appName) Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("\(idPrefix).settings")
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("\(appName) Settings")
        return window
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        onKeyChange?(true)
    }

    public func windowDidResignKey(_ notification: Notification) {
        onKeyChange?(false)
    }
}

struct SettingsRootView: View {
    let appName: String
    let idPrefix: String
    let panes: [SettingsPane]
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var visibility: SettingsVisibility

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(SidebarMaterial().ignoresSafeArea())
            Divider().ignoresSafeArea()
            detail
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .environment(\.settingsWindowVisible, visibility.isVisible)
        .frame(minWidth: 680, minHeight: 460)
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(panes) { pane in
                    SidebarEntry(pane: pane, isCurrent: pane.id == selection.pane) { selection.pane = pane.id }
                        .accessibilityIdentifier("\(idPrefix).settings.\(pane.id)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var detail: some View {
        let pane = panes.first { $0.id == selection.pane } ?? panes.first
        if let pane {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(pane.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    pane.content()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(pane.id)
            .accessibilityIdentifier("\(idPrefix).settings.\(pane.id).pane")
        }
    }
}

/// The sidebar's material, as System Settings and Finder draw theirs.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A sidebar entry in System Settings' style: the symbol in the accent
/// colour, and the selected entry filled with the accent colour with white
/// text (grey while the window is in the background, as AppKit does).
private struct SidebarEntry: View {
    let pane: SettingsPane
    let isCurrent: Bool
    let select: () -> Void
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let active = activeState == .key || activeState == .active
        let emphasised = isCurrent && active
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: pane.symbol)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(emphasised ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.accentColor))
                    .frame(width: 20)
                Text(pane.title)
                    .font(.body)
                    .foregroundStyle(emphasised ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(emphasised ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
