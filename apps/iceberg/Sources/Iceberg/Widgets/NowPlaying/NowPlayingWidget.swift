import AppKit
import SwiftUI
import IcebergKit

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
    /// The cover's strongest colour, for the closed notch's bars; nil for a
    /// grey cover or none.
    @Published private(set) var artworkTint: RGB?

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
            let tint = artwork.flatMap(Self.coverTint)
            if tint != artworkTint { artworkTint = tint }
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

    func shutDown() {
        adapter?.stop()
        adapter = nil
        let center = DistributedNotificationCenter.default()
        for token in observers { center.removeObserver(token) }
        observers = []
    }

    /// The cover drawn small, then its strongest hue (once per track).
    static func coverTint(_ image: NSImage) -> RGB? {
        let side = ArtworkTint.sampleSide
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? ArtworkTint.dominant(rgba: bytes) : nil
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
    @Local private var hovering = false

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

/// The closed notch while music plays: the cover in the left wing and
/// playing bars in the right, each one notch height wide, so the wings read
/// as part of the notch.
struct LiveActivityView: View {
    @ObservedObject var model: NowPlayingWidget
    @EnvironmentObject var theme: ThemeStore
    /// The closed notch's height.
    let height: CGFloat
    /// The flare at each top corner, which nothing is drawn in.
    let inset: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let pad = NotchGeometry.wingPadding(collapsedHeight: height)
        let side = NotchGeometry.wingArtworkSide(collapsedHeight: height)
        let wing = NotchGeometry.wingWidth(collapsedHeight: height)
        let tint = ArtworkTint.tint(cover: model.artworkTint, accent: theme.theme.accent).color
        HStack(spacing: 0) {
            CoverThumb(image: model.artwork, side: side)
                .padding(.leading, pad)
                .frame(width: wing, height: height, alignment: .leading)
            Spacer(minLength: 0)
            PlayingBars(playing: model.isPlaying, color: tint, reduceMotion: reduceMotion)
                .frame(width: side * 0.8, height: side * 0.7)
                .padding(.trailing, pad)
                .frame(width: wing, height: height, alignment: .trailing)
        }
        .padding(.horizontal, inset)
        .frame(height: height)
        .help([model.state.title, model.state.artist].compactMap { $0 }.joined(separator: " – "))
    }
}

/// The cover in a rounded square (a quarter of its side), filled without
/// stretching, with a faint inner line so a dark cover still shows on black.
struct CoverThumb: View {
    let image: NSImage?
    let side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: side * 0.5)).foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
    }
}

/// Five thin bars that move while music plays, and rest low when paused.
/// With Reduce Motion they stay still.
struct PlayingBars: View {
    let playing: Bool
    let color: Color
    let reduceMotion: Bool
    static let count = 5

    var body: some View {
        if playing && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: false)) { context in
                bars(Self.levels(at: context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            bars(playing ? [0.5, 0.8, 0.45, 0.7, 0.5] : Array(repeating: 0.2, count: Self.count))
        }
    }

    private func bars(_ levels: [Double]) -> some View {
        GeometryReader { g in
            let width = max(1.5, g.size.width / CGFloat(Self.count * 2 - 1))
            HStack(alignment: .center, spacing: width) {
                ForEach(0..<Self.count, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: width, height: max(width, g.size.height * CGFloat(levels[i])))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    /// Smooth, uneven heights from a few sine waves, 0.2 to 1.
    static func levels(at t: Double) -> [Double] {
        (0..<count).map { i in
            let d = Double(i)
            let a = sin(t * (5.3 + d * 1.7) + d * 1.3)
            let b = sin(t * (2.1 + d * 0.9) + d * 2.1)
            return 0.2 + 0.8 * abs(a * 0.6 + b * 0.4)
        }
    }
}
