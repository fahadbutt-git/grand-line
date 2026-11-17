import AppKit
import SwiftUI
import IcebergKit

/// The Pomodoro card in the panel. The timer itself is the app's one
/// `PomodoroModel` (it keeps running while the card is off, so the
/// `iceberg pomodoro` command and the closed notch work either way).
@MainActor
final class PomodoroWidget: NotchWidget {
    let id = "pomodoro"
    let placement = WidgetPlacement.section
    private let model: PomodoroModel

    init(context: WidgetContext) {
        model = context.pomodoro
    }

    func makeView() -> AnyView { AnyView(PomodoroView(model: model)) }
}

extension PomodoroPhase {
    /// A quiet tint per phase, from the system colours: orange to focus,
    /// green for a short break, cyan for the long one.
    var tint: Color {
        switch self {
        case .focus: return .orange
        case .shortBreak: return .green
        case .longBreak: return .cyan
        }
    }

    var symbol: String { isBreak ? "cup.and.saucer.fill" : "timer" }
}

/// The time left. It redraws once a second, on the second, only while it
/// is on screen and the timer runs; paused or idle it is drawn once.
struct PomodoroClock: View {
    let timer: PomodoroTimer
    /// False while the displays sleep: nothing is drawn then.
    var live = true

    var body: some View {
        if live, timer.status == .running, let end = timer.endsAt {
            // Ticks fall just after each whole second before the end, so
            // the digits change exactly as a second runs out.
            let anchor = end.addingTimeInterval(-max(0, end.timeIntervalSinceNow.rounded(.up)) - 1 + 0.05)
            TimelineView(.periodic(from: anchor, by: 1)) { context in
                Text(timer.clock(at: context.date))
            }
        } else {
            Text(timer.clock(at: Date()))
        }
    }
}

/// One dot per focus round before the long break: filled when done, a ring
/// round the one running.
struct RoundDots: View {
    let timer: PomodoroTimer
    @EnvironmentObject var palette: SystemPalette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(timer.dots.enumerated()), id: \.offset) { index, done in
                let current = timer.phase == .focus && timer.status != .idle && index == timer.completed
                Circle()
                    .fill(done ? timer.phase.tint.opacity(timer.phase == .focus ? 1 : 0.85) : palette.foreground.opacity(0.18))
                    .overlay {
                        if current {
                            Circle().strokeBorder(PomodoroPhase.focus.tint, lineWidth: max(1, PixelGrid.hairline(scale: displayScale) * 2))
                        }
                    }
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(timer.round) of \(timer.rounds), \(timer.completed) done")
    }
}

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    @EnvironmentObject var palette: SystemPalette
    @ObservedObject private var display = DisplayOptions.shared

    var body: some View {
        let timer = model.timer
        let change = Motion.content(reduceMotion: display.reduceMotion)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                SectionCaption(text: timer.status == .paused ? "\(timer.phase.title), paused" : timer.phase.title)
                Spacer(minLength: 4)
                RoundDots(timer: timer)
            }
            Button { PomodoroLengthMenu.show(model) } label: {
                PomodoroClock(timer: timer)
                    .font(TypeScale.timer)
                    .foregroundStyle(timer.status == .paused ? palette.muted : palette.foreground)
                    .lineLimit(1)
            }
            .buttonStyle(PanelButtonStyle(kind: .text))
            .help("Choose the focus length")
            .accessibilityLabel("\(timer.phase.title), \(PomodoroTimer.spoken(timer.remaining(at: Date()))) left")
            .accessibilityHint("Choose the focus length")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    controls(timer)
                    Spacer(minLength: 10)
                    lengthControl
                }
                controls(timer)
            }
            Spacer(minLength: 0)
        }
        .animation(change, value: timer.phase)
        .animation(change, value: timer.status)
    }

    private func controls(_ timer: PomodoroTimer) -> some View {
        let primary: (symbol: String, help: String)
        switch timer.status {
        case .idle: primary = ("play.fill", "Start")
        case .running: primary = ("pause.fill", "Pause")
        case .paused: primary = ("play.fill", "Resume")
        }
        return HStack(spacing: 14) {
            PomodoroButton(symbol: primary.symbol, font: SymbolScale.transportPrimary, help: primary.help) { model.toggle() }
            PomodoroButton(symbol: "arrow.counterclockwise", font: SymbolScale.transport, help: "Reset") { model.reset() }
                .disabled(timer.isFresh(config: model.config))
            PomodoroButton(symbol: "forward.end.fill", font: SymbolScale.transport,
                           help: timer.phase == .focus ? "Skip to the break" : "Skip to focus") { model.skip() }
        }
    }

    /// The focus length, with 5 fewer and 5 more minutes either side.
    private var lengthControl: some View {
        let focus = model.config.focus
        return HStack(spacing: 2) {
            PomodoroButton(symbol: "minus", font: SymbolScale.accessory, help: "5 fewer minutes of focus", size: 16) {
                model.setFocus(model.config.focus(steppedBy: -1))
            }
            .disabled(focus <= PomodoroConfig.focusRange.lowerBound)
            Button { PomodoroLengthMenu.show(model) } label: {
                Text("\(focus) min")
                    .font(TypeScale.numeral)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(PanelButtonStyle(kind: .text))
            .help("Focus length. Click to choose another.")
            .accessibilityLabel("Focus length, \(focus) minutes")
            PomodoroButton(symbol: "plus", font: SymbolScale.accessory, help: "5 more minutes of focus", size: 16) {
                model.setFocus(model.config.focus(steppedBy: 1))
            }
            .disabled(focus >= PomodoroConfig.focusRange.upperBound)
        }
    }
}

/// A symbol button: a plate on hover, smaller on mouse-down, and the
/// symbol's own replace effect when it changes (play and pause).
private struct PomodoroButton: View {
    @EnvironmentObject var palette: SystemPalette
    @ObservedObject private var display = DisplayOptions.shared
    let symbol: String
    let font: Font
    let help: String
    var size: CGFloat = 24
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .foregroundStyle(palette.foreground)
                .contentTransition(.symbolEffect(.replace))
                .animation(Motion.content(reduceMotion: display.reduceMotion), value: symbol)
                .frame(width: size, height: 22)
        }
        .buttonStyle(PanelButtonStyle(kind: .icon))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The focus lengths to choose from, as a menu at the pointer: 15, 25, 45
/// and 50 minutes, and 5 more or fewer. The choice is written to
/// iceberg.toml (`pomodoro_focus`).
@MainActor
enum PomodoroLengthMenu {
    static func show(_ model: PomodoroModel) {
        let menu = NSMenu()
        let focus = model.config.focus
        let header = NSMenuItem(title: "Focus length", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for minutes in PomodoroConfig.presets {
            let item = ActionMenuItem(title: "\(minutes) minutes") { model.setFocus(minutes) }
            item.state = minutes == focus ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let more = ActionMenuItem(title: "5 More Minutes") { model.setFocus(model.config.focus(steppedBy: 1)) }
        more.isEnabled = focus < PomodoroConfig.focusRange.upperBound
        menu.addItem(more)
        let fewer = ActionMenuItem(title: "5 Fewer Minutes") { model.setFocus(model.config.focus(steppedBy: -1)) }
        fewer.isEnabled = focus > PomodoroConfig.focusRange.lowerBound
        menu.addItem(fewer)
        menu.autoenablesItems = false
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() {
        MainActor.assumeIsolated { handler() }
    }
}

/// The closed notch while the timer runs or is paused: the phase's symbol
/// in the left wing, tinted by phase, and the time left in the right. It
/// takes the place of the music's wings while it shows (a HUD still shows
/// over it for a moment).
struct PomodoroActivityView: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject private var display = DisplayOptions.shared
    /// The closed notch's height.
    let height: CGFloat
    /// The flare at each top corner, which nothing is drawn in.
    let inset: CGFloat
    /// False while the displays sleep: the time is not redrawn then.
    let live: Bool

    var body: some View {
        let timer = model.timer
        let wing = NotchGeometry.hudWingWidth(collapsedHeight: height)
        let pad = NotchGeometry.wingPadding(collapsedHeight: height) + 4
        let paused = timer.status == .paused
        HStack(spacing: 0) {
            // Sized to the notch, as the HUDs' symbols are.
            Image(systemName: paused ? "pause.fill" : timer.phase.symbol)
                .font(.system(size: (height * 0.42).rounded(), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(paused ? Color.white.opacity(0.55) : timer.phase.tint)
                .contentTransition(.symbolEffect(.replace))
                .animation(Motion.content(reduceMotion: display.reduceMotion), value: paused)
                .padding(.leading, pad)
                .frame(width: wing, height: height, alignment: .leading)
            Spacer(minLength: 0)
            PomodoroClock(timer: timer, live: live)
                .font(TypeScale.numeral.weight(.medium))
                .foregroundStyle(Color.white.opacity(paused ? 0.55 : (display.increaseContrast ? 1 : 0.9)))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, pad)
                .frame(width: wing, height: height, alignment: .trailing)
        }
        .padding(.horizontal, inset)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timer.phase.title)\(paused ? ", paused" : ""), \(PomodoroTimer.spoken(timer.remaining(at: Date()))) left")
        .help("\(timer.phase.title)\(paused ? ", paused" : ""). Open the panel for the controls.")
    }
}
