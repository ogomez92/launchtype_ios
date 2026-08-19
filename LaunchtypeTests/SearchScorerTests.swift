import Testing
@testable import Launchtype

/// Ground-truth scores captured from the Rust implementation (which itself
/// asserts bit-identical scores against the original Python).
struct SearchScorerTests {
    @Test func groundTruthScores() {
        #expect(SearchScorer.subsequenceMatch(search: "gwe", target: "google website") == -7.0)
        #expect(SearchScorer.subsequenceMatch(search: "gw", target: "google website") == -8.0)
        #expect(SearchScorer.subsequenceMatch(search: "goog", target: "google website") == -7.0)
        #expect(SearchScorer.subsequenceMatch(search: "web", target: "google website") == 0.5)
        #expect(SearchScorer.subsequenceMatch(search: "code", target: "visual studio code") == 5.0)
        #expect(SearchScorer.subsequenceMatch(search: "vsc", target: "visual studio code") == -1.0)
        #expect(SearchScorer.subsequenceMatch(search: "gw", target: "visual studio code") == nil)
        #expect(SearchScorer.subsequenceMatch(search: "xyz", target: "google website") == nil)
        #expect(SearchScorer.subsequenceMatch(search: "", target: "anything") == 0.0)
    }

    @Test func spacesAreStrippedFromTheSearch() {
        #expect(SearchScorer.subsequenceMatch(search: "c ode", target: "visual studio code") == 5.0)
        #expect(SearchScorer.subsequenceMatch(search: "g w", target: "google website") == -8.0)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(SearchScorer.subsequenceMatch(search: "GWE", target: "Google Website") == -7.0)
    }

    @Test func fuzzySearchSortsAscendingAndFilters() {
        let items = ["google website", "notepad", "github repo", "visual studio code"]
        let results = SearchScorer.fuzzySearch("o", items) { $0 }
        // "google website" and "notepad" both score 0.5 (match at index 1);
        // the tie keeps insertion order — the Rust ordering ground truth.
        #expect(results.count == 4)
        #expect(results.first == "google website")
        #expect(results[1] == "notepad")
    }

    @Test func emptySearchReturnsItemsUnchanged() {
        let items = ["b", "a", "c"]
        #expect(SearchScorer.fuzzySearch("", items) { $0 } == items)
    }

    @Test func tiesKeepInsertionOrder() {
        let items = ["alpha one", "alpha two"]
        let results = SearchScorer.fuzzySearch("alpha", items) { $0 }
        #expect(results == ["alpha one", "alpha two"])
    }

    @Test func exactShortcutMatchIsCaseInsensitiveEquality() {
        let items = [("jitsi radio", "jr"), ("gmail", "gm")]
        let hit = SearchScorer.exactShortcutMatch("JR", items) { $0.1 }
        #expect(hit?.0 == "jitsi radio")
        #expect(SearchScorer.exactShortcutMatch("j", items) { $0.1 } == nil)
        #expect(SearchScorer.exactShortcutMatch("", items) { $0.1 } == nil)
    }
}
