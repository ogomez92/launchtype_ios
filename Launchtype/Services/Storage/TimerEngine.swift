import Foundation

/// Countdown timer engine — a pure port of the desktop `timers.rs`, with the
/// clock injected so the semantics are unit-testable. Definitions persist to
/// `timers.json`; live deadlines are in-memory only.
final class TimerEngine {
    private(set) var timers: [TimerDef]
    /// Timer id → next deadline. Absent means inactive.
    private var nextFire: [String: Date] = [:]

    /// Repeating timers default to on whenever they are loaded.
    init(timers: [TimerDef], now: Date) {
        self.timers = timers
        for timer in timers where timer.repeating {
            nextFire[timer.id] = now.addingTimeInterval(timer.period)
        }
    }

    var anyActive: Bool { !nextFire.isEmpty }

    func isActive(_ timerId: String) -> Bool {
        nextFire[timerId] != nil
    }

    /// Run/toggle a timer. Returns the new active state, or nil for an
    /// unknown id. Non-repeating timers (re)start their countdown each run.
    func toggle(_ timerId: String, now: Date) -> Bool? {
        guard let timer = timers.first(where: { $0.id == timerId }) else {
            return nil
        }
        if timer.repeating, isActive(timerId) {
            nextFire[timerId] = nil
            return false
        }
        nextFire[timerId] = now.addingTimeInterval(timer.period)
        return true
    }

    /// Add a definition. Repeating timers activate immediately, matching how
    /// they come up on load.
    func add(_ timer: TimerDef, now: Date) {
        timers.append(timer)
        if timer.repeating {
            nextFire[timer.id] = now.addingTimeInterval(timer.period)
        }
    }

    /// Replace a definition by id. The old deadline no longer means anything,
    /// so a repeating timer restarts its countdown and a one-shot stops.
    func update(_ timer: TimerDef, now: Date) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else {
            return
        }
        timers[index] = timer
        nextFire[timer.id] = timer.repeating ? now.addingTimeInterval(timer.period) : nil
    }

    func remove(_ timerId: String) {
        timers.removeAll { $0.id == timerId }
        nextFire[timerId] = nil
    }

    /// Seconds left until the timer next fires, or nil when inactive.
    func remainingSeconds(_ timerId: String, now: Date) -> Int? {
        guard let deadline = nextFire[timerId] else {
            return nil
        }
        return max(0, Int((deadline.timeIntervalSince(now)).rounded()))
    }

    /// Timers whose deadline has passed; repeating ones reschedule from `now`,
    /// one-shot ones deactivate.
    func due(now: Date) -> [TimerDef] {
        var fired: [TimerDef] = []
        for timer in timers {
            guard let deadline = nextFire[timer.id], now >= deadline else {
                continue
            }
            fired.append(timer)
            nextFire[timer.id] = timer.repeating ? now.addingTimeInterval(timer.period) : nil
        }
        return fired
    }

    /// The desktop's "{title} - {descriptor} ({state})" list label.
    func itemLabel(for timer: TimerDef, now: Date) -> String {
        let state: String
        if let remaining = remainingSeconds(timer.id, now: now) {
            let verb = timer.repeating ? "until repeat" : "left"
            state = "running, \(Self.formatRemaining(remaining)) \(verb)"
        } else {
            state = "stopped"
        }
        let descriptor = timer.repeating
            ? "every \(timer.minutes) min, repeating"
            : "\(timer.minutes) min"
        return "\(timer.title) - \(descriptor) (\(state))"
    }

    /// Render remaining seconds as `M:SS` (or `H:MM:SS` past an hour).
    static func formatRemaining(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        let paddedSecs = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSecs)"
        }
        return "\(minutes):\(paddedSecs)"
    }
}
