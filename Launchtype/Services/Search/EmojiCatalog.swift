import Foundation

/// The emoji catalogue behind `:` mode, parsed from the bundled `emoji.txt` —
/// the same CLDR-derived table the desktop app compiles in. One tab-separated
/// row per emoji, in palette order: `emoji`, then a name and keywords per
/// language (`en` then `es`).
@MainActor
enum EmojiCatalog {
    /// The languages the table carries, in column order: language `i` has its
    /// name in column `1 + i * 2` and its keywords in the column after that.
    private static let languages = ["en", "es"]
    private static let columns = 1 + languages.count * 2

    private static var cache: [String: [EmojiEntry]] = [:]

    /// Every emoji, named in `language`, falling back to English for a
    /// language the table has no column for. Parsed once per language.
    static func table(language: String) -> [EmojiEntry] {
        let index = languages.firstIndex(of: language) ?? 0
        let key = languages[index]
        if let cached = cache[key] {
            return cached
        }
        let parsed = parse(languageIndex: index)
        cache[key] = parsed
        return parsed
    }

    private static func parse(languageIndex: Int) -> [EmojiEntry] {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let nameColumn = 1 + languageIndex * 2
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            // A short row would mean a corrupt file; drop it rather than crash.
            guard fields.count == columns else { return nil }
            let name = String(fields[nameColumn])
            return EmojiEntry(
                emoji: String(fields[0]),
                name: name,
                nameKey: TextFolding.fold(name),
                keywordsKey: TextFolding.fold(String(fields[nameColumn + 1]))
            )
        }
    }
}
