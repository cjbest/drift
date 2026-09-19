import Foundation

/// A new writing session begins after five minutes fully in the background.
/// Inactive-only interruptions never start this timer.
struct LaunchSessionPolicy {
    let interval: TimeInterval
    private var backgroundedAt: Date?

    init(interval: TimeInterval = 300) { self.interval = interval }

    mutating func enteredBackground(at date: Date = .now) {
        if backgroundedAt == nil { backgroundedAt = date }
    }

    mutating func becameActive(at date: Date = .now) -> Bool {
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return false }
        return date.timeIntervalSince(backgroundedAt) >= interval
    }

    static func configured() -> Self {
        #if DEBUG && targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if let folder = environment["DRIFT_TEST_FOLDER"], !folder.isEmpty,
           let value = environment["DRIFT_TEST_RESUME_INTERVAL"],
           let interval = TimeInterval(value), interval.isFinite, interval > 0 {
            return Self(interval: interval)
        }
        #endif
        return Self()
    }
}
