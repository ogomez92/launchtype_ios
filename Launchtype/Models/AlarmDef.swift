import Foundation

/// One entry of `alarms.json`, schema-compatible with the desktop app.
struct AlarmDef: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var kind: String
    var title: String
    var description: String
    var hour: Int
    var minute: Int
    var sound: String?
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
        case title
        case description
        case hour
        case minute
        case sound
        case enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "alarm"
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        sound = try container.decodeIfPresent(String.self, forKey: .sound)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        description: String = "",
        hour: Int,
        minute: Int,
        sound: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        kind = "alarm"
        self.title = title
        self.description = description
        self.hour = hour
        self.minute = minute
        self.sound = sound
        self.enabled = enabled
    }

    /// The desktop list label: `"wake - 07:05 (on)"`.
    var label: String {
        let hh = hour < 10 ? "0\(hour)" : "\(hour)"
        let mm = minute < 10 ? "0\(minute)" : "\(minute)"
        let state = enabled ? "on" : "off"
        return "\(title) - \(hh):\(mm) (\(state))"
    }
}
