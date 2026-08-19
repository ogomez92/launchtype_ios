import Foundation

/// Fuzzy subsequence search — an exact port of the desktop app's
/// `launchtype-core/src/search.rs` (itself a port of the original Python).
/// Scores must stay numerically identical; the unit tests assert ground-truth
/// values captured from the Rust implementation.
enum SearchScorer {
    private static let wordBoundaries: Set<Character> = [" ", "-", "_", ".", "/", "\\"]

    /// Check whether `search` is a subsequence of `target`.
    ///
    /// Returns the score on match (lower is better), nil otherwise. An empty
    /// search string matches everything with score 0.
    ///
    /// Scoring:
    /// - spread penalty: distance between first and last matched positions
    /// - word-boundary bonus: −10 for a match at position 0, −5 after ` -_./\`
    /// - early-match bonus: + first position × 0.5
    static func subsequenceMatch(search: String, target: String) -> Double? {
        if search.isEmpty {
            return 0.0
        }

        // Spaces are stripped from the search string for more flexible matching.
        let searchChars = Array(search.lowercased()).filter { $0 != " " }
        let targetChars = Array(target.lowercased())

        var matchPositions: [Int] = []
        matchPositions.reserveCapacity(searchChars.count)
        var searchIndex = 0
        for (targetIndex, character) in targetChars.enumerated() {
            if searchIndex >= searchChars.count {
                break
            }
            if searchChars[searchIndex] == character {
                matchPositions.append(targetIndex)
                searchIndex += 1
            }
        }

        if searchIndex < searchChars.count {
            return nil
        }

        var score = 0.0

        if matchPositions.count > 1, let first = matchPositions.first, let last = matchPositions.last {
            score += Double(last - first)
        }

        for position in matchPositions {
            if position == 0 {
                score -= 10.0
            } else if wordBoundaries.contains(targetChars[position - 1]) {
                score -= 5.0
            }
        }

        if let first = matchPositions.first {
            score += Double(first) * 0.5
        }

        return score
    }

    /// Filter and rank `items` by subsequence match on `key(item)`. An empty
    /// search returns the items unchanged. Ties keep insertion order — Swift's
    /// sort is not guaranteed stable, so the original index breaks ties.
    static func fuzzySearch<T>(_ search: String, _ items: [T], key: (T) -> String) -> [T] {
        if search.isEmpty {
            return items
        }
        return items.enumerated()
            .compactMap { index, item in
                subsequenceMatch(search: search, target: key(item)).map { (score: $0, index: index, item: item) }
            }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map(\.item)
    }

    /// The single item whose shortcut equals `search` case-insensitively, if
    /// any — an exact shortcut hit short-circuits fuzzy search entirely.
    static func exactShortcutMatch<T>(_ search: String, _ items: [T], shortcut: (T) -> String?) -> T? {
        let lowered = search.lowercased()
        guard !lowered.isEmpty else { return nil }
        return items.first { item in
            guard let value = shortcut(item), !value.isEmpty else { return false }
            return value.lowercased() == lowered
        }
    }
}
