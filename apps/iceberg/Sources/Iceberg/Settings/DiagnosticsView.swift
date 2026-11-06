import AppKit
import SwiftUI
import IcebergKit

/// Settings › Diagnostics: for each widget in the panel, how often it ran,
/// how long it takes, what it last printed and its last error. A widget
/// that runs too often or too long shows up here first.
struct DiagnosticsView: View {
    @ObservedObject var user: UserWidgets
    @EnvironmentObject var palette: SystemPalette
    let settings: IcebergSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let reason = user.gate.reason {
                    Text("\(reason): only widgets with always = true run until it ends.")
                        .foregroundStyle(palette.foreground)
                }
                Text("At most \(settings.maxConcurrent) commands at once (max_concurrent). Files reload when saved"
                     + (user.lastReload.map { "; last read at \($0.formatted(date: .omitted, time: .standard))." } ?? "."))
                    .foregroundStyle(palette.muted)
            }
            .font(TypeScale.caption)

            if user.widgets.isEmpty {
                Text("No widget is in the panel.")
                    .font(TypeScale.body).foregroundStyle(palette.muted)
            }
            ForEach(user.widgets) { w in
                DiagnosticsRow(widget: w, stats: user.stats[w.id] ?? WidgetStats(), status: user.status(of: w),
                               display: user.displays[w.id], busy: user.running.contains(w.id)) {
                    user.runNow(w.id)
                }
            }
        }
    }
}

private struct DiagnosticsRow: View {
    @EnvironmentObject var palette: SystemPalette
    let widget: WidgetConfig
    let stats: WidgetStats
    let status: String?
    let display: WidgetDisplay?
    let busy: Bool
    let runNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(widget.title).font(TypeScale.body.weight(.medium)).foregroundStyle(palette.foreground)
                Text(widget.mode.description).font(TypeScale.caption).foregroundStyle(palette.muted)
                Spacer(minLength: 8)
                Button(widget.stream ? "Restart" : "Run now", action: runNow)
                    .controlSize(.small)
                    .disabled(busy && !widget.stream)
            }
            Text(line).font(TypeScale.caption).foregroundStyle(palette.muted)
            if let status {
                Text(status).font(TypeScale.caption).foregroundStyle(palette.foreground)
            }
            if let output = stats.lastOutput, !output.isEmpty {
                labelled("Last output", output, colour: palette.foreground)
            }
            if let error = stats.lastError {
                let when = stats.lastErrorAt.map { " at " + $0.formatted(date: .omitted, time: .standard) } ?? ""
                labelled("Last error" + when, error, colour: palette.color(.named(.red)) ?? palette.foreground)
            }
        }
        .padding(.vertical, 3)
    }

    private var line: String {
        var parts = [stats.summary]
        if let last = stats.lastRun {
            parts.append("last " + last.formatted(date: .omitted, time: .standard))
        }
        if let d = stats.lastDuration, !widget.stream {
            parts.append(String(format: "took %.2f s", d))
        }
        return parts.joined(separator: ", ")
    }

    private func labelled(_ label: String, _ text: String, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(TypeScale.label).foregroundStyle(palette.muted)
            Text(text)
                .font(TypeScale.code)
                .foregroundStyle(colour)
                .lineLimit(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One problem: where (file:line), what, and the fix in plain words.
struct ProblemRow: View {
    @EnvironmentObject var palette: SystemPalette
    let issue: ConfigIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(issue.severity == .error ? (palette.color(.named(.red)) ?? palette.muted) : palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.location)
                        .font(TypeScale.code.weight(.medium))
                        .foregroundStyle(palette.foreground)
                    Text(issue.message)
                        .font(TypeScale.caption)
                        .foregroundStyle(palette.foreground)
                }
                if let fix = issue.fix {
                    Text("Fix: " + fix)
                        .font(TypeScale.caption)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
        }
    }
}

/// Which Now Playing source is in use, and what to do when none works.
struct NowPlayingHealthRow: View {
    @ObservedObject var model: NowPlayingWidget
    @EnvironmentObject var palette: SystemPalette

    var body: some View {
        let health = model.health
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(health.source))
                .font(TypeScale.body)
                .foregroundStyle(health.source == .none ? (palette.color(.named(.red)) ?? palette.muted) : palette.highlight)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.summary)
                    .font(TypeScale.body)
                    .foregroundStyle(palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix = health.fix {
                    Text(fix).font(TypeScale.caption).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let at = health.lastCheckAt {
                    Text("Last checked at \(at.formatted(date: .omitted, time: .standard)).")
                        .font(TypeScale.caption).foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 8)
            if health.adapterBundled {
                Button(model.checking ? "Checking…" : "Check again") { model.checkHealth() }
                    .controlSize(.small)
                    .disabled(model.checking)
            }
        }
        .padding(.vertical, 3)
    }

    private func symbol(_ source: MediaSource) -> String {
        switch source {
        case .adapter: return "checkmark.circle"
        case .appleScript: return "exclamationmark.circle"
        case .none: return "xmark.circle"
        }
    }
}
