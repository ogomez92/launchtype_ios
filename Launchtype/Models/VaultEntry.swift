import Foundation

/// One entry of the encrypted vault as the results list knows it.
///
/// Deliberately has no `secret`: rows are rebuilt on every keystroke and read
/// out by VoiceOver, so the secret is decrypted only when a row is actually
/// activated, one at a time.
struct VaultEntry: Identifiable, Equatable, Sendable {
    /// The uuid naming the entry's `.enc` file.
    var id: String
    var name: String
    /// Optional lowercase shortcut; an exact match jumps straight to the entry.
    var shortcut: String

    /// The row label, in the same shape as a command row.
    var label: String {
        shortcut.isEmpty ? name : "\(name) (\(shortcut))"
    }
}
