import Foundation

/// The tiered emoji ranker — an exact port of the desktop `emoji::search`.
/// It deliberately does not use `SearchScorer`: that scorer is tuned for short
/// command names and pays most for a match near the start, which buries emoji
/// whose match lives deep in a keyword list.
@MainActor
enum EmojiRanker {
    /// The emoji `query` describes, best match first. An empty query is every
    /// emoji, in palette order.
    static func search(language: String, query: String) -> [EmojiEntry] {
        let table = EmojiCatalog.table(language: language)
        let folded = TextFolding.fold(query).trimmingCharacters(in: .whitespaces)
        if folded.isEmpty {
            return table
        }
        // Shorter name first within a tier (the plainer, more canonical emoji),
        // counted in characters; exact ties keep palette order — Swift's sort
        // is not guaranteed stable, so the index is part of the sort key.
        return table.enumerated()
            .compactMap { index, entry in
                rank(entry, query: folded).map { (tier: $0, length: entry.name.count, index: index, entry: entry) }
            }
            .sorted { ($0.tier, $0.length, $0.index) < ($1.tier, $1.length, $1.index) }
            .map(\.entry)
    }

    /// How well `query` (already folded and trimmed) describes `entry`, as a
    /// tier where lower is better, or nil for no match at all.
    ///
    /// Plain `contains`/`hasPrefix` on the pre-folded keys is deliberate — not
    /// `localizedStandardContains` — because folding already normalized case
    /// and diacritics and the ordering must match the desktop app exactly.
    private static func rank(_ entry: EmojiEntry, query: String) -> Int? {
        if entry.nameKey == query {
            return 0
        }
        if startsAWord(of: entry.nameKey, prefix: query) {
            return 1
        }
        if entry.nameKey.contains(query) {
            return 2
        }
        if startsAWord(of: entry.keywordsKey, prefix: query) {
            return 3
        }
        if entry.keywordsKey.contains(query) {
            return 4
        }
        // Last resort, for a description whose words are spread across the
        // name and the keywords ("crying cat", "red car").
        let allWordsFound = query.split(separator: " ").allSatisfy { word in
            entry.nameKey.contains(word) || entry.keywordsKey.contains(word)
        }
        return allWordsFound ? 5 : nil
    }

    /// Whether any word of `text` starts with `prefix`, so that "heart" finds
    /// "red heart" and "laugh" finds "rolling on the floor laughing".
    private static func startsAWord(of text: String, prefix: String) -> Bool {
        text.split(separator: " ", omittingEmptySubsequences: false).contains { $0.hasPrefix(prefix) }
    }
}
