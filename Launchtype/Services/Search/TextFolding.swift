import Foundation

/// Case and accent folding — an exact port of the desktop app's `i18n::fold`.
/// The map is deliberately the same explicit Spanish-oriented table, not
/// generic Unicode folding, so emoji ranking matches the desktop bit for bit.
enum TextFolding {
    static func fold(_ text: String) -> String {
        String(text.lowercased().map { character in
            switch character {
            case "á", "à", "ä", "â", "ã", "å": "a"
            case "é", "è", "ë", "ê": "e"
            case "í", "ì", "ï", "î": "i"
            case "ó", "ò", "ö", "ô", "õ": "o"
            case "ú", "ù", "ü", "û": "u"
            case "ñ": "n"
            case "ç": "c"
            default: character
            }
        })
    }
}
