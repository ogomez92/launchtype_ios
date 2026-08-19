import Foundation

/// JSON load/save with the desktop app's tolerance: a missing or corrupt file
/// decodes to the caller's default instead of failing, and writes are atomic
/// so a crash never leaves a half-written data file.
enum AtomicJSON {
    static func load<T: Decodable>(_ type: T.Type, from url: URL, default fallback: T) -> T {
        guard let data = try? Data(contentsOf: url) else {
            return fallback
        }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    /// Standard `JSONEncoder` output — the desktop's Python-style byte
    /// formatting is not replicated; only losslessness matters, and the
    /// desktop app parses standard JSON fine.
    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
