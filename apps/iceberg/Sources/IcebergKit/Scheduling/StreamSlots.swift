import Foundation

/// Which stream widgets run, at most `max` at once (`max_concurrent`).
public enum StreamSlots {
    /// The wanted streams, in panel order, that start now, and those left
    /// waiting for a slot. Running ones keep their slot; ones waiting to be
    /// restarted after a failure are neither started nor counted as waiting.
    /// `eligible`, when given, limits who may start (after a stream ends by
    /// itself, only the waiting ones take its slot, not the one that ended).
    public static func plan(wanted: [String], running: Set<String>, restarting: Set<String>, max: Int,
                            eligible: Set<String>? = nil) -> (start: [String], waiting: [String]) {
        var used = running.count
        var start: [String] = []
        var waiting: [String] = []
        for id in wanted where !running.contains(id) && !restarting.contains(id) {
            if let eligible, !eligible.contains(id) { continue }
            if used < max {
                start.append(id)
                used += 1
            } else {
                waiting.append(id)
            }
        }
        return (start, waiting)
    }
}
