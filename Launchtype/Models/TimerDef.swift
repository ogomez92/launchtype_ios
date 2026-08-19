import Foundation

/// One entry of `timers.json`, schema-compatible with the desktop app.
struct TimerDef: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var kind: String
    var title: String
    var description: String
    var minutes: UInt64
    var repeating: Bool
    var sound: String?

    var period: TimeInterval { TimeInterval(minutes * 60) }

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
        case title
        case description
        case minutes
        case repeating
        case sound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "timer"
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        minutes = try container.decode(UInt64.self, forKey: .minutes)
        repeating = try container.decode(Bool.self, forKey: .repeating)
        sound = try container.decodeIfPresent(String.self, forKey: .sound)
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        description: String = "",
        minutes: UInt64,
        repeating: Bool = false,
        sound: String? = nil
    ) {
        self.id = id
        kind = "timer"
        self.title = title
        self.description = description
        self.minutes = minutes
        self.repeating = repeating
        self.sound = sound
    }
}
