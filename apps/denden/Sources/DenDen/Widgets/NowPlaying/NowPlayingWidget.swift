import AppKit
import SwiftUI
import DenDenKit

/// Now Playing for any player macOS knows about (Spotify, Music, browsers),
/// with artwork and play, pause, next and previous.
///
/// This is the one widget that keeps working while the panel is closed, so
/// the closed notch can show the artwork. It still uses no timer: updates are
/// pushed by the adapter, or by Spotify and Music themselves in the fallback.
@MainActor
final class NowPlayingWidget: ObservableObject, NotchWidget {
    let id = "now-playing"
    let placement = WidgetPlacement.section

    @Published private(set) var state = NowPlayingState()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var appName: String?

    private var adapter: MediaAdapter?
    private var observers: [NSObjectProtocol] = []

    init(context: WidgetContext) {
        if let location = MediaAdapter.bundled() {
            let adapter = MediaAdapter(location: location,
                                       onLine: { [weak self] line in self?.handle(line: line) },
                                       onGiveUp: { [weak self] in self?.useNotifications() })
            self.adapter = adapter
            adapter.start()
        } else {
            Log.info("Now Playing adapter not bundled; using the Spotify and Music notices")
            useNotifications()
        }
    }

    func makeView() -> AnyView { AnyView(NowPlayingView(model: self)) }

    /// True while something is playing, for the closed notch's live activity.
    var isPlaying: Bool { state.hasMedia && state.isPlaying }

    private func handle(line: String) {
        var next = state
        guard next.apply(line: line) else { return }
        update(to: next)
    }

    private func update(to next: NowPlayingState) {
        if next.artworkDiffers(from: state) {
            artwork = next.artworkBase64
                .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
                .flatMap { NSImage(data: $0) }
        }
        if next.bundleIdentifier != state.bundleIdentifier {
            appName = next.bundleIdentifier.flatMap(Self.appName(for:))
        }
        if next != state { state = next }
    }

    /// The fallback: Spotify's and Music's own change notices.
    private func useNotifications() {
        adapter?.stop()
        adapter = nil
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for name in [PlayerNotification.spotify, PlayerNotification.music] {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                guard let bundle = PlayerNotification.bundleIdentifier(forNotification: note.name.rawValue) else { return }
                let info = (note.userInfo as? [String: Any]) ?? [:]
                let payload = PlayerNotification.payload(bundleIdentifier: bundle, info: info)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var next = self.state
                    // A pause from one app should not clear what the other plays.
                    if payload.isEmpty, self.state.bundleIdentifier != bundle { return }
                    next.apply(payload: payload, diff: false)
                    self.update(to: next)
                }
            }
            observers.append(token)
        }
    }

    func send(_ command: MediaCommand) {
        if MediaRemote.send(command) { return }
        if let adapter { adapter.send(command.rawValue); return }
        MediaRemote.sendWithAppleScript(command, bundleIdentifier: state.bundleIdentifier)
    }

    func openPlayer() {
        guard let id = state.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    static func appName(for bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

struct NowPlayingView: View {
    @ObservedObject var model: NowPlayingWidget
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: model.state.hasMedia ? (model.appName ?? "Now playing") : "Now playing")
            if model.state.hasMedia {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: model.openPlayer) {
                        ArtworkView(image: model.artwork, side: 64, radius: 5)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(model.appName ?? "the player")")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.state.title ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                        Text([model.state.artist, model.state.album].compactMap { $0 }.joined(separator: " – "))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                        PlaybackProgress(state: model.state)
                            .padding(.top, 4)
                        HStack(spacing: 18) {
                            ControlButton(symbol: "backward.fill", help: "Previous") { model.send(.previous) }
                            ControlButton(symbol: model.state.isPlaying ? "pause.fill" : "play.fill",
                                          help: model.state.isPlaying ? "Pause" : "Play") { model.send(.toggle) }
                            ControlButton(symbol: "forward.fill", help: "Next") { model.send(.next) }
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                EmptyNote(text: "Nothing playing")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ControlButton: View {
    @EnvironmentObject var theme: ThemeStore
    let symbol: String
    let help: String
    let action: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(hovering ? theme.highlight : theme.foreground)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A thin bar with elapsed and remaining time. It redraws once a second,
/// and only while it is on screen (the panel is open and something plays).
private struct PlaybackProgress: View {
    @EnvironmentObject var theme: ThemeStore
    let state: NowPlayingState

    var body: some View {
        if let duration = state.duration, duration > 0 {
            if state.isPlaying {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    bar(position: state.position(at: context.date) ?? 0, duration: duration)
                }
            } else {
                bar(position: state.position(at: Date()) ?? 0, duration: duration)
            }
        }
    }

    func bar(position: TimeInterval, duration: TimeInterval) -> some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.selection)
                    Capsule().fill(theme.muted)
                        .frame(width: max(3, g.size.width * CGFloat(min(1, position / duration))))
                }
            }
            .frame(height: 3)
            HStack {
                Text(Self.clock(position))
                Spacer()
                Text("-" + Self.clock(max(0, duration - position)))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(theme.muted)
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Album artwork, or a quiet placeholder.
struct ArtworkView: View {
    @EnvironmentObject var theme: ThemeStore
    let image: NSImage?
    let side: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    theme.raised
                    Image(systemName: "music.note").font(.system(size: side * 0.4)).foregroundStyle(theme.muted)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The closed notch while music plays: artwork to the left of the camera, a
/// still playing mark to the right (an animated one would keep the GPU busy).
struct LiveActivityView: View {
    @ObservedObject var model: NowPlayingWidget
    @EnvironmentObject var theme: ThemeStore
    let height: CGFloat
    let inset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: model.artwork, side: max(12, height - 12), radius: 4)
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.highlight)
        }
        .padding(.horizontal, inset)
        .frame(height: height)
        .help([model.state.title, model.state.artist].compactMap { $0 }.joined(separator: " – "))
    }
}
