import Foundation

/// A coding key over arbitrary strings, used to walk every key of a JSON
/// object so unknown ones can be preserved round-trip.
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
