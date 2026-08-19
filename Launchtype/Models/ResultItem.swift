import Foundation

/// One row of the results list, whatever the mode. The label is computed when
/// the list is built (timer rows need the live countdown), and the kind
/// carries what activating the row needs.
struct ResultItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A launchable command and the URL it opens.
        case command(Command, URL)
        case snippet(Snippet)
        case emoji(EmojiEntry)
        case timer(TimerDef)
        case alarm(AlarmDef)
        /// One entry of the encrypted vault. The secret is deliberately
        /// absent: rows are rebuilt on every keystroke and read out loud, so
        /// it is decrypted only when the row is activated.
        case vaultEntry(VaultEntry)
        /// A vault row that does something rather than holding a secret.
        case vaultAction(VaultAction)
    }

    let id: String
    let label: String
    let kind: Kind

    /// Whether the row offers Edit and Delete. The emoji catalog is built in,
    /// and a vault action row is an instruction rather than a thing.
    var isEditable: Bool {
        switch kind {
        case .command, .snippet, .timer, .alarm, .vaultEntry: true
        case .emoji, .vaultAction: false
        }
    }
}
