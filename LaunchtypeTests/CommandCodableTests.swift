import Foundation
import Testing
@testable import Launchtype

struct CommandCodableTests {
    @Test func unknownKeysSurviveRoundTrip() throws {
        let json = """
        {"commands": [{"path": "{{firefox}}", "name": "jitsi radio", \
        "args": "https://meet.gomsen.com/radio", "shortcut": "jr", \
        "id": "6bb2507a", "type": "command", "custom": {"nested": [1, 2]}}], \
        "total_runs": 1446, "future_key": true}
        """
        let decoded = try JSONDecoder().decode(CommandsFile.self, from: Data(json.utf8))
        #expect(decoded.commands.count == 1)
        #expect(decoded.commands[0].extra["type"] == .string("command"))
        #expect(decoded.totalRuns == 1446)
        #expect(decoded.extra["future_key"] == .bool(true))

        let reencoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode(CommandsFile.self, from: reencoded)
        #expect(again == decoded)
    }

    @Test func legacyRecordWithoutOptionalsDecodes() throws {
        let json = """
        {"commands": [{"path": "x", "name": "n", "id": "abc"}]}
        """
        let decoded = try JSONDecoder().decode(CommandsFile.self, from: Data(json.utf8))
        #expect(decoded.commands[0].args == nil)
        #expect(decoded.commands[0].shortcut == nil)
        #expect(decoded.commands[0].runCount == nil)
        #expect(decoded.totalRuns == nil)
    }

    @Test func recordRunBumpsCommandAndTotal() {
        var file = CommandsFile(commands: [
            Command(path: "p", name: "n", args: nil, shortcut: nil, id: "one"),
        ])
        file.recordRun(id: "one")
        #expect(file.commands[0].runCount == 1)
        #expect(file.totalRuns == 1)
        // The lifetime total counts even for an unknown id, like the desktop.
        file.recordRun(id: "missing")
        #expect(file.totalRuns == 2)
    }
}
