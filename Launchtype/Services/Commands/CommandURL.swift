import Foundation

/// Decides which desktop commands survive on iOS: only those whose arguments
/// resolve to something a URL can open. A phone cannot spawn `xp.exe`, but a
/// `{{firefox}}` command whose argument is a URL — or a bare domain a browser
/// would have resolved — opens fine in Safari.
enum CommandURL {
    /// The URL running `command` would open, or nil when the command is not
    /// launchable on iOS (and should be hidden from the list).
    static func launchURL(for command: Command) -> URL? {
        let browser = BrowserPaths.isBrowserPath(command.path)
        let args = command.args ?? ""

        // The whole trimmed argument string first — a URL may itself contain a
        // comma, which the segment split below would cut in half.
        var candidates = [unquote(args.trimmingCharacters(in: .whitespaces))]
        candidates.append(contentsOf: argSegments(args))

        for candidate in candidates where !candidate.isEmpty {
            if looksLikeURL(candidate), let url = URL(string: candidate) {
                return url
            }
            // Only a browser may assume a bare `gmail.com` is a website; for
            // any other target that rewrite would break a file argument.
            if browser, looksLikeBareDomain(candidate), let url = URL(string: "https://\(candidate)") {
                return url
            }
        }
        return nil
    }

    /// Whether `value` starts with a URL scheme (`https://`, `steam://`,
    /// `mailto:`). Exact port of the desktop `looks_like_url`: a drive letter
    /// (`D:\…`) is not a scheme.
    static func looksLikeURL(_ value: String) -> Bool {
        let characters = Array(value)
        guard let colon = characters.firstIndex(of: ":"), colon > 1 else {
            return false
        }
        return characters[..<colon].allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber
                || character == "+" || character == "-" || character == ".")
        }
    }

    /// Whether `value` reads like an address-bar domain (`gmail.com`,
    /// `calendar.google.com/foo`) rather than a flag, a path, or a template.
    static func looksLikeBareDomain(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              !value.hasPrefix("/"),
              value.contains("."),
              !value.contains(":") else {
            return false
        }
        return !value.contains { character in
            character.isWhitespace || character == "\\" || character == "{" || character == "\""
        }
    }

    /// The individual arguments of a comma-separated argument string, unquoted
    /// and trimmed — the same split the desktop runner performs.
    static func argSegments(_ args: String) -> [String] {
        if args.trimmingCharacters(in: .whitespaces).isEmpty {
            return []
        }
        return args
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
