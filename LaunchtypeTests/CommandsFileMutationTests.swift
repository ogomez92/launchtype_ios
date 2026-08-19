import Testing
@testable import Launchtype

struct CommandsFileMutationTests {
    private func command(id: String, name: String) -> Command {
        Command(path: "{{browser}}", name: name, args: "https://example.com", shortcut: nil, id: id, runAsAdmin: nil, runCount: nil)
    }

    @Test func upsertAppendsNewIds() {
        var file = CommandsFile()
        file.upsert(command(id: "a", name: "first"))
        file.upsert(command(id: "b", name: "second"))
        #expect(file.commands.map(\.id) == ["a", "b"])
    }

    @Test func upsertReplacesInPlaceKeepingOrder() {
        var file = CommandsFile()
        file.upsert(command(id: "a", name: "first"))
        file.upsert(command(id: "b", name: "second"))
        file.upsert(command(id: "a", name: "renamed"))
        #expect(file.commands.map(\.id) == ["a", "b"])
        #expect(file.commands[0].name == "renamed")
    }

    @Test func removeDeletesById() {
        var file = CommandsFile()
        file.upsert(command(id: "a", name: "first"))
        file.upsert(command(id: "b", name: "second"))
        file.remove(id: "a")
        #expect(file.commands.map(\.id) == ["b"])
        file.remove(id: "ghost")
        #expect(file.commands.map(\.id) == ["b"])
    }
}
