import Testing
@testable import Launchtype

/// Mirrors the desktop `emoji.rs` tests against the same bundled table.
@MainActor
struct EmojiRankerTests {
    @Test func catalogParses() {
        let table = EmojiCatalog.table(language: "en")
        #expect(table.count > 1500)
    }

    @Test func emptyQueryIsWholeTableInPaletteOrder() {
        let all = EmojiRanker.search(language: "en", query: "")
        #expect(all.count == EmojiCatalog.table(language: "en").count)
        #expect(all.first?.emoji == "😀")
    }

    @Test func thePlainNameWins() {
        #expect(EmojiRanker.search(language: "en", query: "fire").first?.emoji == "🔥")
        #expect(EmojiRanker.search(language: "en", query: "rocket").first?.emoji == "🚀")
        #expect(EmojiRanker.search(language: "en", query: "heart").first?.emoji == "\u{2764}\u{fe0f}")
    }

    @Test func keywordsFindWhatTheNameDoesNotSay() {
        #expect(EmojiRanker.search(language: "en", query: "coffee").first?.emoji == "☕")
        #expect(EmojiRanker.search(language: "en", query: "tada").first?.emoji == "🎉")
    }

    @Test func accentsAreOptional() {
        let bare = EmojiRanker.search(language: "es", query: "corazon").map(\.emoji)
        let accented = EmojiRanker.search(language: "es", query: "corazón").map(\.emoji)
        #expect(bare == accented)
        #expect(!bare.isEmpty)
    }

    @Test func spanishNamesAreSearchedInSpanish() {
        #expect(EmojiRanker.search(language: "es", query: "fuego").first?.emoji == "🔥")
        #expect(EmojiRanker.search(language: "es", query: "cohete").first?.emoji == "🚀")
    }

    @Test func unknownLanguageFallsBackToEnglish() {
        #expect(EmojiRanker.search(language: "de", query: "fire").first?.emoji == "🔥")
    }

    @Test func noMatchIsEmptyRatherThanEverything() {
        #expect(EmojiRanker.search(language: "en", query: "zzzzqqqq").isEmpty)
    }

    @Test func descriptionSpreadAcrossNameAndKeywordsMatches() {
        let results = EmojiRanker.search(language: "en", query: "crying cat")
        #expect(results.contains { $0.emoji == "😿" })
    }
}
