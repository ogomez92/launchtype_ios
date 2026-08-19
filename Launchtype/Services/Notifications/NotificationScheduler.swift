import UserNotifications

/// Local notifications for timers and alarms, so they ring with the app in
/// the background. Permission is requested lazily — the first time a timer
/// starts or an alarm is enabled — never during launch, where a surprise
/// permission dialog would steal focus from the search field.
@MainActor
final class NotificationScheduler {
    private var permissionRequested = false

    func scheduleTimer(_ timer: TimerDef, remaining: TimeInterval) {
        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = timer.title
        content.body = timer.description
        content.sound = notificationSound(named: timer.sound, fallback: "timer.wav")
        // A repeating trigger repeats from schedule time, which matches the
        // engine's toggle-time-based schedule closely enough.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(remaining, 1),
            repeats: timer.repeating
        )
        let request = UNNotificationRequest(identifier: timer.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelTimer(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func scheduleAlarm(_ alarm: AlarmDef) {
        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = alarm.title
        content.body = alarm.description
        content.sound = notificationSound(named: alarm.sound, fallback: "alarm.caf")
        var components = DateComponents()
        components.hour = alarm.hour
        components.minute = alarm.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: alarm.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelAlarm(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func requestPermissionIfNeeded() {
        guard !permissionRequested else {
            return
        }
        permissionRequested = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Notification sounds must live in `Library/Sounds` and be wav/caf/aiff —
    /// flac is not supported, so the desktop's `alarm.flac` maps to the
    /// converted `alarm.caf`. An unknown file falls back to the default tone.
    private func notificationSound(named name: String?, fallback: String) -> UNNotificationSound {
        var candidate = name?.isEmpty == false ? name! : fallback
        // Stored values may be folder-relative ("alarms/dawn.wav"); Library/
        // Sounds is flat, so only the file name matters.
        candidate = candidate.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? candidate
        if candidate.lowercased().hasSuffix(".flac") {
            candidate = String(candidate.dropLast(5)) + ".caf"
        }
        let installed = AppDirectories.librarySounds.appending(path: candidate)
        guard FileManager.default.fileExists(atPath: installed.path()) else {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(candidate))
    }
}
