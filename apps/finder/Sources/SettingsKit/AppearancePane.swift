import AppIcon
import AppKit
import Combine
import SwiftUI
import ThemeKit

/// The Appearance pane's state. Choosing a theme or dark, light or Follow
/// macOS runs the package's `theme` command with an argument list, exactly as
/// `theme set <family>` and `theme mode` do from the menu; the apps then
/// recolour through their theme watchers. Density is the app's own setting
/// (its defaults domain), unless the theme sets UI_DENSITY.
@MainActor
public final class AppearanceModel: ObservableObject {
    @Published public private(set) var families: [ThemeFamily] = []
    @Published public private(set) var activeName: String
    @Published public private(set) var appearance: ThemeAppearance
    @Published public private(set) var busy = false
    @Published public private(set) var message: String?
    @Published public private(set) var density: Density
    @Published public private(set) var theme: Theme

    public let location: ThemeLocation
    let defaults: UserDefaults
    /// Called after the density changes, so the app can lay its rows out again.
    public var onDensityChange: ((Density) -> Void)?
    private var sink: AnyCancellable?

    public init(theme: SettingsTheme, location: ThemeLocation = ThemeLocation(), defaults: UserDefaults = .standard) {
        self.location = location
        self.defaults = defaults
        self.theme = theme.theme
        self.activeName = location.activeName() ?? ThemeLocation.fallbackName
        self.appearance = location.followsSystem() ? .system : (theme.theme.isDark ? .dark : .light)
        self.density = Density.current(theme: theme.theme, defaults: defaults)
        reloadFamilies()
        sink = theme.$theme.sink { [weak self] fresh in
            MainActor.assumeIsolated { self?.themeChanged(fresh) }
        }
    }

    public func reloadFamilies() {
        families = ThemeCatalog.families(in: location.themesFolder)
    }

    private func themeChanged(_ fresh: Theme) {
        theme = fresh
        activeName = location.activeName() ?? ThemeLocation.fallbackName
        appearance = location.followsSystem() ? .system : (fresh.isDark ? .dark : .light)
        density = Density.current(theme: fresh, defaults: defaults)
    }

    public var currentFamily: ThemeFamily? {
        ThemeCatalog.family(of: activeName, in: families) ?? ThemeCatalog.family(of: theme.name, in: families)
    }

    /// The variant a card shows: the one that choosing it would apply now.
    public func previewVariant(_ family: ThemeFamily) -> ThemeVariant? {
        switch appearance {
        case .dark: return family.variant(dark: true)
        case .light: return family.variant(dark: false)
        case .system: return family.variant(dark: SystemAppearance.isDark())
        }
    }

    public func isActive(_ family: ThemeFamily) -> Bool {
        family.contains(activeName)
    }

    // MARK: Choices

    public func choose(_ family: ThemeFamily) {
        run(ThemeCommand.setArguments(family, appearance: appearance, systemIsDark: SystemAppearance.isDark()))
    }

    public func setAppearance(_ choice: ThemeAppearance) {
        guard choice != appearance else { return }
        do {
            try location.setFollowsSystem(choice == .system)
        } catch {
            message = "The setting could not be saved: \(error.localizedDescription)"
            return
        }
        appearance = choice
        guard let family = currentFamily, family.hasPair else { return }
        switch choice {
        case .system:
            run(ThemeCommand.setArguments(family, appearance: .system, systemIsDark: SystemAppearance.isDark()))
        case .dark, .light:
            run(["mode", choice.rawValue])
        }
    }

    public func setDensity(_ choice: Density) {
        guard theme.density == nil else { return }
        defaults.set(choice.rawValue, forKey: Density.defaultsKey)
        density = choice
        onDensityChange?(choice)
    }

    private func run(_ arguments: [String]) {
        guard !busy else { return }
        guard FileManager.default.isExecutableFile(atPath: location.themeCommand.path) else {
            message = "The theme command is not installed at \(location.themeCommand.path)."
            return
        }
        busy = true
        message = nil
        let location = self.location
        Task { [weak self] in
            let outcome = await ThemeCommand.run(arguments, location: location)
            guard let self else { return }
            self.busy = false
            self.message = outcome.status == 0 ? nil : (outcome.lastLine.isEmpty ? "The theme could not be changed." : outcome.lastLine)
            self.activeName = location.activeName() ?? ThemeLocation.fallbackName
        }
    }
}

/// Settings, Appearance: theme cards, dark, light or Follow macOS, the icon
/// style the theme sets, and row density. Shared by Nexus and Sight.
public struct AppearancePane: View {
    @EnvironmentObject private var settingsTheme: SettingsTheme
    @ObservedObject var model: AppearanceModel
    let idPrefix: String

    public init(model: AppearanceModel, idPrefix: String) {
        self.model = model
        self.idPrefix = idPrefix
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Mode", note: "Dark and light switch every app, the terminal and the menus together.") {
                SettingsRow("Appearance", detail: modeDetail) {
                    Picker("Appearance", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                        ForEach(ThemeAppearance.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(model.busy)
                    .accessibilityIdentifier("\(idPrefix).settings.appearance.mode")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Theme").font(.system(size: 13, weight: .semibold)).foregroundStyle(settingsTheme.strong)
                    if model.busy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(model.families) { family in
                        ThemeCard(family: family, variant: model.previewVariant(family), isActive: model.isActive(family)) {
                            model.choose(family)
                        }
                        .disabled(model.busy)
                        .accessibilityIdentifier("\(idPrefix).settings.theme.\(family.id)")
                    }
                }
                if let message = model.message {
                    SettingsNote(message, symbol: "exclamationmark.triangle")
                }
            }

            SettingsSection("App icons", note: "The icon style comes from the theme (ICON_STYLE). Edit the theme file to change it.") {
                SettingsRow("Style: \(model.theme.icon.style.rawValue.capitalized)", detail: iconDetail) {
                    HStack(spacing: 6) {
                        ForEach([IconGlyph.nexus, .sight, .iceberg], id: \.self) { glyph in
                            Image(nsImage: IconRenderer.image(glyph, theme: model.theme.icon))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 28, height: 28)
                                .accessibilityLabel(glyph.rawValue.capitalized)
                        }
                    }
                }
            }

            SettingsSection("Density", note: densityNote) {
                SettingsRow("Rows") {
                    Picker("Density", selection: Binding(get: { model.density }, set: { model.setDensity($0) })) {
                        ForEach(Density.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(model.theme.density != nil)
                    .accessibilityIdentifier("\(idPrefix).settings.appearance.density")
                }
            }
        }
        .onAppear { model.reloadFamilies() }
    }

    private var modeDetail: String {
        guard let family = model.currentFamily else { return "" }
        if !family.hasPair { return "\(family.label) has one variant, so it stays as it is." }
        switch model.appearance {
        case .system: return "\(family.label) switches between dark and light with macOS."
        case .dark: return "\(family.label), dark variant."
        case .light: return "\(family.label), light variant."
        }
    }

    private var iconDetail: String {
        switch model.theme.icon.style {
        case .line: return "A dark tile, a light glyph and each app's colour."
        case .solid: return "Each app's colour as the tile, with a dark glyph."
        case .mono: return "A black tile with the glyph in each app's colour."
        }
    }

    private var densityNote: String {
        model.theme.density == nil
            ? "How tightly this app packs its rows. Kept for this app only."
            : "Set by the theme (UI_DENSITY)."
    }
}

/// One theme as a small preview drawn from its own colours: a Nexus row with
/// a kind tag, a Sight row with a highlighted match, and Iceberg's pill.
struct ThemeCard: View {
    @EnvironmentObject var settingsTheme: SettingsTheme
    let family: ThemeFamily
    let variant: ThemeVariant?
    let isActive: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 0) {
                if let variant { preview(variant) }
                HStack(spacing: 6) {
                    Text(family.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(settingsTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(family.hasPair ? "Dark and light" : (family.dark != nil ? "Dark" : "Light"))
                        .font(.system(size: 11))
                        .foregroundStyle(settingsTheme.dim)
                        .lineLimit(1)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(settingsTheme.highlight)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(settingsTheme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? settingsTheme.highlight : settingsTheme.hairline, lineWidth: isActive ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.label)
        .accessibilityValue(isActive ? "Current theme" : "")
        .help("Use \(family.label)")
    }

    private func preview(_ variant: ThemeVariant) -> some View {
        let t = variant.theme
        let values = variant.values
        func hex(_ key: String) -> Color? { values[key].flatMap { ThemeColor(hex: $0) }.map { Color($0) } }
        let pdf = t.kinds[.pdf]
        let folder = t.kinds[.folder]
        return VStack(alignment: .leading, spacing: 6) {
            // Nexus: a selected folder row and a file row with its kind tag.
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(Color(folder))
                Text("Projects").font(.system(size: 10)).foregroundStyle(Color(t.selectionText))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(t.selection)))
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 10)).foregroundStyle(Color(t.dim))
                Text("Review.pdf").font(.system(size: 10)).foregroundStyle(Color(t.text))
                KindMark(style: t.kinds.style, color: pdf, label: "PDF", background: t.background)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 16)
            // Sight: the field with a highlighted match.
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(Color(t.dim))
                (Text("conj").foregroundColor(Color(t.highlight)) + Text(" flap").foregroundColor(Color(t.text)))
                    .font(.system(size: 10))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(t.field)))
            // Iceberg: the pill, black where it meets the camera, its panel colour below.
            HStack {
                Spacer(minLength: 0)
                ZStack {
                    Capsule().fill(hex("NOTCH_PANEL") ?? Color(t.background))
                    Capsule().fill(Color.black).padding(.bottom, 6)
                    HStack(spacing: 3) {
                        Circle().fill(hex("ICON_NOTCH") ?? Color(t.accent)).frame(width: 5, height: 5)
                        Capsule().fill(hex("NOTCH_CARD") ?? Color(t.panel)).frame(width: 22, height: 4)
                    }
                    .offset(y: 4)
                }
                .frame(width: 64, height: 16)
                .overlay(Capsule().strokeBorder(hex("NOTCH_LINE") ?? Color(t.line), lineWidth: 0.5))
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(t.background))
        .environment(\.colorScheme, t.colorScheme)
        .accessibilityHidden(true)
    }
}

/// A file's kind as the theme's KIND_STYLE shows it: a tinted tag, a dot, a
/// filled tag or the name in colour.
public struct KindMark: View {
    let style: KindStyle
    let color: ThemeColor
    let label: String
    let background: ThemeColor

    public init(style: KindStyle, color: ThemeColor, label: String, background: ThemeColor) {
        self.style = style
        self.color = color
        self.label = label
        self.background = background
    }

    public var body: some View {
        switch style {
        case .tag:
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(color))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(background.mixed(with: color, 0.2))))
        case .dot:
            Circle().fill(Color(color)).frame(width: 6, height: 6)
        case .solid:
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(color.luminance > 0.4 ? ThemeColor.black : ThemeColor.white))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(color)))
        case .text:
            Text(label).font(.system(size: 9)).foregroundStyle(Color(color))
        }
    }
}
