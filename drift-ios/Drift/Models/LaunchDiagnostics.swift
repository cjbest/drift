import Foundation

/// Sideload diagnostics contain timing, counts, and flags only. Never log note
/// titles, contents, filenames, folder paths, bookmarks, or recovery text.
@MainActor
enum LaunchDiagnostics {
    #if DEBUG
    private static let started = ProcessInfo.processInfo.systemUptime
    private static let writer = DispatchQueue(label: "Drift.LaunchDiagnostics", qos: .utility)
    private static var events: [[String: Any]] = []
    private static var recorded = Set<String>()
    #endif

    static func record(_ event: String, counts: [String: Int] = [:],
                       flags: [String: Bool] = [:], once: Bool = false) {
        #if DEBUG
        if once, !recorded.insert(event).inserted { return }
        events.append(["event": event,
                       "elapsed_ms": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                       "counts": counts, "flags": flags])
        if events.count > 80 { events.removeFirst(events.count - 80) }
        guard let data = try? JSONSerialization.data(withJSONObject: ["events": events],
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        writer.async {
            let fm = FileManager.default
            guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true) else { return }
            var directory = support.appendingPathComponent("Drift/Diagnostics", isDirectory: true)
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                try data.write(to: directory.appendingPathComponent("launch-latest.json"), options: .atomic)
            } catch { /* Diagnostics must never affect notebook behavior. */ }
        }
        #endif
    }
}
