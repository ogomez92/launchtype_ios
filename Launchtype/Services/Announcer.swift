import Accessibility
import SwiftUI

/// VoiceOver speech, the modern SwiftUI way: `AccessibilityNotification`
/// announcements, never `UIAccessibility.post`. High priority interrupts
/// current speech — used for mode switches, action confirmations, and
/// timer/alarm fires; result narration stays at default priority because it
/// is already debounced.
@MainActor
struct Announcer {
    func say(_ text: String, high: Bool = false) {
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = high ? .high : .default
        AccessibilityNotification.Announcement(message).post()
    }
}
