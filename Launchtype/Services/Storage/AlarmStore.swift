import Foundation

/// Alarms: `alarms.json` persistence plus calendar-notification scheduling.
/// There is no in-app minute poller — a repeating calendar notification rings
/// whether the app is up or not, and the foreground delegate replays the cue.
@MainActor
@Observable
final class AlarmStore {
    private(set) var alarms: [AlarmDef]
    private let url: URL
    private let scheduler: NotificationScheduler

    init(scheduler: NotificationScheduler) {
        url = AppDirectories.documents.appending(path: "alarms.json")
        self.scheduler = scheduler
        alarms = AtomicJSON.load([AlarmDef].self, from: url, default: [])
        for alarm in alarms where alarm.enabled {
            scheduler.scheduleAlarm(alarm)
        }
    }

    /// Rebuild from disk — after a backup import replaced `alarms.json`. All
    /// pending notifications are rescheduled to match the new definitions.
    func reload() {
        for alarm in alarms {
            scheduler.cancelAlarm(id: alarm.id)
        }
        alarms = AtomicJSON.load([AlarmDef].self, from: url, default: [])
        for alarm in alarms where alarm.enabled {
            scheduler.scheduleAlarm(alarm)
        }
    }

    /// Add a new alarm or replace an edited one, keyed by id, and reschedule
    /// its notification to match.
    func upsert(_ alarm: AlarmDef) {
        scheduler.cancelAlarm(id: alarm.id)
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        AtomicJSON.save(alarms, to: url)
        if alarm.enabled {
            scheduler.scheduleAlarm(alarm)
        }
    }

    func delete(id: String) {
        scheduler.cancelAlarm(id: id)
        alarms.removeAll { $0.id == id }
        AtomicJSON.save(alarms, to: url)
    }

    /// Toggle an alarm's activation state and return the new enabled state.
    func toggle(_ alarmId: String) -> Bool? {
        guard let index = alarms.firstIndex(where: { $0.id == alarmId }) else {
            return nil
        }
        alarms[index].enabled.toggle()
        AtomicJSON.save(alarms, to: url)
        if alarms[index].enabled {
            scheduler.scheduleAlarm(alarms[index])
        } else {
            scheduler.cancelAlarm(id: alarmId)
        }
        return alarms[index].enabled
    }

    func alarm(withId id: String) -> AlarmDef? {
        alarms.first { $0.id == id }
    }
}
