import Foundation

/// What the presented sheet is showing. Emoji has no editor — the catalog is
/// built in — so emoji rows and emoji mode map to nil.
///
/// The vault's password prompts are sheets like the editors are, and live here
/// for the same reason: one presentation at a time, driven by one value.
enum EditorSheet: Identifiable {
    case newCommand
    case editCommand(Command)
    case newSnippet
    case editSnippet(Snippet)
    case newTimer
    case editTimer(TimerDef)
    case newAlarm
    case editAlarm(AlarmDef)
    case newVaultEntry
    /// Editing carries the decrypted entry: the sheet is the only place a
    /// secret is ever shown.
    case editVaultEntry(VaultEntryDraft)
    case vaultUnlock
    case vaultSetup
    case vaultChangePassword

    var id: String {
        switch self {
        case .newCommand: "new-command"
        case .editCommand(let command): "command-\(command.id)"
        case .newSnippet: "new-snippet"
        case .editSnippet(let snippet): "snippet-\(snippet.id)"
        case .newTimer: "new-timer"
        case .editTimer(let timer): "timer-\(timer.id)"
        case .newAlarm: "new-alarm"
        case .editAlarm(let alarm): "alarm-\(alarm.id)"
        case .newVaultEntry: "new-vault-entry"
        case .editVaultEntry(let draft): "vault-entry-\(draft.id ?? "")"
        case .vaultUnlock: "vault-unlock"
        case .vaultSetup: "vault-setup"
        case .vaultChangePassword: "vault-password"
        }
    }

    /// The "add new" sheet the header button opens in this mode. The vault's
    /// is only reachable once it is unlocked, which ``AppModel/add()`` sorts
    /// out before this is consulted.
    static func newItem(for mode: Mode) -> EditorSheet? {
        switch mode {
        case .commands: .newCommand
        case .snippets: .newSnippet
        case .emoji: nil
        case .timers: .newTimer
        case .alarms: .newAlarm
        case .vault: .newVaultEntry
        }
    }
}
