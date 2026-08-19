import Foundation

/// Timers: persistence, the live tick loop, and firing. Wraps `TimerEngine`
/// (the pure ported semantics) with `timers.json` persistence, sounds,
/// announcements, and local-notification scheduling for background firing.
@MainActor
@Observable
final class TimerStore {
    private var engine: TimerEngine
    private let url: URL
    private let sounds: SoundPlayer
    private let announcer: Announcer
    private let scheduler: NotificationScheduler

    /// Bumped every second while a countdown runs, so timer row labels
    /// rebuilt from computed results stay live.
    private(set) var tickCount = 0

    private var ticker: Task<Void, Never>?

    init(sounds: SoundPlayer, announcer: Announcer, scheduler: NotificationScheduler) {
        url = AppDirectories.documents.appending(path: "timers.json")
        self.sounds = sounds
        self.announcer = announcer
        self.scheduler = scheduler
        let defs = AtomicJSON.load([TimerDef].self, from: url, default: [])
        engine = TimerEngine(timers: defs, now: Date())
        // Repeating timers woke up active; cover their background firing too.
        for timer in engine.timers where engine.isActive(timer.id) {
            scheduler.scheduleTimer(timer, remaining: timer.period)
        }
        ensureTicking()
    }

    var timers: [TimerDef] { engine.timers }

    /// Rebuild from disk — after a backup import replaced `timers.json`. All
    /// pending notifications are rescheduled to match the new definitions.
    func reload() {
        for timer in engine.timers {
            scheduler.cancelTimer(id: timer.id)
        }
        let defs = AtomicJSON.load([TimerDef].self, from: url, default: [])
        engine = TimerEngine(timers: defs, now: Date())
        for timer in engine.timers where engine.isActive(timer.id) {
            scheduler.scheduleTimer(timer, remaining: timer.period)
        }
        ensureTicking()
        tickCount += 1
    }

    func label(for timer: TimerDef) -> String {
        engine.itemLabel(for: timer, now: Date())
    }

    func add(_ timer: TimerDef) {
        engine.add(timer, now: Date())
        if engine.isActive(timer.id) {
            scheduler.scheduleTimer(timer, remaining: timer.period)
            ensureTicking()
        }
        save()
    }

    func update(_ timer: TimerDef) {
        scheduler.cancelTimer(id: timer.id)
        engine.update(timer, now: Date())
        if engine.isActive(timer.id) {
            scheduler.scheduleTimer(timer, remaining: timer.period)
            ensureTicking()
        }
        save()
    }

    func delete(id: String) {
        scheduler.cancelTimer(id: id)
        engine.remove(id)
        save()
    }

    /// Persist the definitions and poke `tickCount` so the computed results
    /// list rebuilds — the engine itself is not observable.
    private func save() {
        AtomicJSON.save(engine.timers, to: url)
        tickCount += 1
    }

    /// Toggle a timer and return its new active state.
    func toggle(_ timerId: String) -> Bool? {
        guard let timer = engine.timers.first(where: { $0.id == timerId }),
              let active = engine.toggle(timerId, now: Date()) else {
            return nil
        }
        if active {
            scheduler.scheduleTimer(timer, remaining: timer.period)
            ensureTicking()
        } else {
            scheduler.cancelTimer(id: timerId)
        }
        tickCount += 1
        return active
    }

    private func ensureTicking() {
        guard ticker == nil, engine.anyActive else {
            return
        }
        ticker = Task {
            while !Task.isCancelled, engine.anyActive {
                try? await Task.sleep(for: .seconds(1))
                tick()
            }
            ticker = nil
        }
    }

    private func tick() {
        let fired = engine.due(now: Date())
        for timer in fired {
            sounds.playAlert(named: timer.sound, fallback: .timer)
            let message = timer.description.isEmpty ? timer.title : "\(timer.title): \(timer.description)"
            announcer.say(message, high: true)
            if !timer.repeating {
                scheduler.cancelTimer(id: timer.id)
            }
        }
        tickCount += 1
    }
}
