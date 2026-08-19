import Foundation

/// One emoji from the bundled CLDR table: the characters to copy, the name a
/// screen reader gives it, and pre-folded keys the ranker matches against.
struct EmojiEntry: Identifiable, Equatable, Sendable {
    /// The exact character sequence to put on the clipboard.
    var emoji: String
    /// CLDR's short name — what a screen reader calls this emoji.
    var name: String
    /// Folded `name`, for matching a folded query.
    var nameKey: String
    /// Folded, space-separated keywords. Searched but never shown.
    var keywordsKey: String

    var id: String { emoji }
}
