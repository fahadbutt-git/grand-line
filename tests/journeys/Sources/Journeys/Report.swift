import Foundation

/// Results on the terminal, in results.tsv, and as GitHub Actions annotations.
enum Report {
    /// GitHub shows at most ten annotations of a kind per step, so nine are
    /// itemised and the tenth sums up the rest.
    static let annotationLimit = 9

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    static func escapeTitle(_ text: String) -> String {
        escape(text).replacingOccurrences(of: ":", with: "%3A").replacingOccurrences(of: ",", with: "%2C")
    }

    static func printJourney(_ r: JourneyResult) {
        let state = r.passed ? "passed" : "FAILED"
        print(String(format: "== %@ %@ in %.1f s", r.journey.name, state, r.seconds)
              + (r.metrics.isEmpty ? "" : " (" + r.metrics.joined(separator: ", ") + ")"))
    }

    static func write(_ results: [JourneyResult], options: Options) {
        let fm = FileManager.default
        try? fm.createDirectory(at: options.output, withIntermediateDirectories: true)
        var tsv = "journey\tapp\tstep\tstatus\tseconds\tscreenshot\tmessage\n"
        for r in results {
            for s in r.steps {
                let message = s.message.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " / ")
                tsv += "\(r.journey.name)\t\(r.appName)\t\(s.name)\t\(s.status.rawValue)\t\(String(format: "%.2f", s.seconds))\t\(s.screenshot)\t\(message)\n"
            }
        }
        try? tsv.write(to: options.output.appendingPathComponent("results.tsv"), atomically: true, encoding: .utf8)
        let failed = results.filter { !$0.passed }.count
        print("\n\(results.count - failed) of \(results.count) journeys passed. Screenshots and results.tsv in \(options.output.path)")
        if options.github { annotate(results) }
    }

    static func annotate(_ results: [JourneyResult]) {
        // One notice per journey: pass or fail, its time, each step's time.
        let notices = results.map { r -> String in
            let head = String(format: "%@ in %.1f s", r.passed ? "passed" : "FAILED", r.seconds)
            var lines = [head + (r.metrics.isEmpty ? "" : "; " + r.metrics.joined(separator: ", "))]
            for s in r.steps {
                let extra = s.status == .skipped ? " (skipped: \(s.message))" : ""
                lines.append(String(format: "%@ %.1f s  %@%@", s.status.rawValue, s.seconds, s.name, extra))
            }
            lines += r.notes.map { "note: " + $0 }
            return "::notice title=\(escapeTitle("\(r.appName) journey \(r.journey.name)"))::\(escape(lines.joined(separator: "\n")))"
        }
        emit(notices, kind: "notice", summary: "more journeys")

        // One error per failed journey, with the step, why, and the screenshot.
        let failures = results.filter { !$0.passed }
        var errors: [String] = []
        for r in failures {
            guard let s = r.failed else { continue }
            let body = ["step \"\(s.name)\" failed:", s.message, "screenshot: \(r.journey.name)/\(s.screenshot)"]
            errors.append("::error title=\(escapeTitle("\(r.appName) journey \(r.journey.name)"))::\(escape(body.joined(separator: "\n")))")
        }
        if errors.count > annotationLimit + 1 {
            let rest = failures.dropFirst(annotationLimit).map { "\($0.journey.name): \($0.failed?.name ?? "")" }
            errors = Array(errors.prefix(annotationLimit))
            errors.append("::error title=\(escapeTitle("\(rest.count) more journeys failed"))::\(escape(rest.joined(separator: "\n")))")
        }
        errors.forEach { print($0) }

        // The step summary page: a table of every journey.
        if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"], let handle = FileHandle(forWritingAtPath: path) {
            var md = "\n| Journey | App | Result | Time | Failed step |\n| --- | --- | --- | --- | --- |\n"
            for r in results {
                md += "| \(r.journey.name) | \(r.appName) | \(r.passed ? "passed" : "failed") | \(String(format: "%.1f s", r.seconds)) | \(r.failed?.name ?? "") |\n"
            }
            handle.seekToEndOfFile()
            handle.write(md.data(using: .utf8)!)
            try? handle.close()
        }
    }

    private static func emit(_ lines: [String], kind: String, summary: String) {
        if lines.count <= annotationLimit + 1 {
            lines.forEach { print($0) }
            return
        }
        lines.prefix(annotationLimit).forEach { print($0) }
        print("::\(kind) title=\(escapeTitle("\(lines.count - annotationLimit) \(summary)"))::see results.tsv in the screenshots artifact")
    }
}
