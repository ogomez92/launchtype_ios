import Foundation

/// The whole of a commands JSON file (`commands.json`, `work.json`, …):
/// the command list plus the lifetime `total_runs` counter, with any
/// unknown top-level keys preserved.
struct CommandsFile: Equatable, Sendable {
    var commands: [Command] = []
    var totalRuns: UInt64?
    var extra: [String: JSONValue] = [:]

    /// Bump a command's run count and the lifetime total. The total counts
    /// even when the id is unknown, matching the desktop app.
    mutating func recordRun(id: String) {
        if let index = commands.firstIndex(where: { $0.id == id }) {
            commands[index].runCount = (commands[index].runCount ?? 0) + 1
        }
        totalRuns = (totalRuns ?? 0) + 1
    }

    /// Replace the command with the same id, or append when the id is new.
    mutating func upsert(_ command: Command) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
        } else {
            commands.append(command)
        }
    }

    mutating func remove(id: String) {
        commands.removeAll { $0.id == id }
    }
}

extension CommandsFile: Codable {
    private static let knownKeys: Set<String> = ["commands", "total_runs"]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        commands = try container.decodeIfPresent([Command].self, forKey: AnyCodingKey("commands")) ?? []
        totalRuns = try container.decodeIfPresent(UInt64.self, forKey: AnyCodingKey("total_runs"))
        extra = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(commands, forKey: AnyCodingKey("commands"))
        try container.encodeIfPresent(totalRuns, forKey: AnyCodingKey("total_runs"))
        for (key, value) in extra {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}
