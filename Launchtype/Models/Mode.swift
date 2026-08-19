import Foundation

/// The six launcher modes, in tab order. Each mirrors a desktop Launchtype
/// mode and keeps its trigger character: typing that character alone in an
/// empty search field switches mode, exactly like the desktop app.
enum Mode: String, CaseIterable, Identifiable, Sendable {
    case commands
    case snippets
    case emoji
    case timers
    case alarms
    case vault

    var id: String { rawValue }

    /// The character that switches to this mode when typed into an empty
    /// field. `.` returns to commands, matching the desktop app.
    var triggerChar: Character {
        switch self {
        case .commands: "."
        case .snippets: "-"
        case .emoji: ":"
        case .timers: "["
        case .alarms: "]"
        case .vault: "*"
        }
    }

    /// Tab label.
    var title: String {
        switch self {
        case .commands: "Commands"
        case .snippets: "Snippets"
        case .emoji: "Emoji"
        case .timers: "Timers"
        case .alarms: "Alarms"
        case .vault: "Vault"
        }
    }

    /// The singular noun for one item of this mode, for "Add command"-style
    /// button labels.
    var itemName: String {
        switch self {
        case .commands: "command"
        case .snippets: "snippet"
        case .emoji: "emoji"
        case .timers: "timer"
        case .alarms: "alarm"
        case .vault: "vault entry"
        }
    }

    /// What VoiceOver announces on entering the mode — the desktop phrases.
    var announcement: String {
        switch self {
        case .commands: "commands mode"
        case .snippets: "snippet mode"
        case .emoji: "emoji mode, type a description and press enter to copy"
        case .timers: "timers mode"
        case .alarms: "alarms mode"
        case .vault: "encrypted vault mode"
        }
    }

    static func forTrigger(_ character: Character) -> Mode? {
        allCases.first { $0.triggerChar == character }
    }
}
