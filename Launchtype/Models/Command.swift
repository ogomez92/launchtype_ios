import Foundation

/// One entry of `commands.json`, byte-compatible with the desktop app's
/// schema. Unknown keys survive in `extra` so the file can round-trip
/// between this port and the desktop app without loss.
struct Command: Equatable, Sendable {
    var path: String
    var name: String
    var args: String?
    var shortcut: String?
    var id: String
    var runAsAdmin: Bool?
    var runCount: UInt64?
    var extra: [String: JSONValue] = [:]
}

extension Command: Codable {
    private static let knownKeys: Set<String> = [
        "path", "name", "args", "shortcut", "id", "run_as_admin", "run_count",
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        path = try container.decode(String.self, forKey: AnyCodingKey("path"))
        name = try container.decode(String.self, forKey: AnyCodingKey("name"))
        args = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("args"))
        shortcut = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("shortcut"))
        id = try container.decode(String.self, forKey: AnyCodingKey("id"))
        runAsAdmin = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("run_as_admin"))
        runCount = try container.decodeIfPresent(UInt64.self, forKey: AnyCodingKey("run_count"))
        extra = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(path, forKey: AnyCodingKey("path"))
        try container.encode(name, forKey: AnyCodingKey("name"))
        try container.encodeIfPresent(args, forKey: AnyCodingKey("args"))
        try container.encodeIfPresent(shortcut, forKey: AnyCodingKey("shortcut"))
        try container.encode(id, forKey: AnyCodingKey("id"))
        try container.encodeIfPresent(runAsAdmin, forKey: AnyCodingKey("run_as_admin"))
        try container.encodeIfPresent(runCount, forKey: AnyCodingKey("run_count"))
        for (key, value) in extra {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}
