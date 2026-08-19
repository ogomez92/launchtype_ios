import UserNotifications

/// While the app is foregrounded it plays its own cue and speaks its own
/// announcement, so the system banner and sound are suppressed and the event
/// is handed to the model instead. Main-actor isolated (and therefore
/// Sendable); the nonisolated delegate callback hops over.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Set once at startup.
    var onForegroundDelivery: ((String) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        await MainActor.run {
            onForegroundDelivery?(identifier)
        }
        return []
    }
}
