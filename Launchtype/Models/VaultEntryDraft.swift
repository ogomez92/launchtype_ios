import Foundation

/// What the add/edit sheet reads and writes: an entry with its secret, which
/// only exists while that sheet is up.
///
/// `id` is nil for a new entry and the existing uuid when editing, so saving
/// replaces the entry rather than making a second one.
struct VaultEntryDraft: Equatable, Sendable {
    var id: String?
    var name = ""
    var shortcut = ""
    var secret = ""
}
