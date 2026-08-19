import Foundation

/// The commands file: loads the one `settings.commands_file` names, exposes
/// the URL-launchable subset in display order, and persists run counts.
@MainActor
@Observable
final class CommandsStore {
    /// A command that survived the iOS filter, paired with the URL it opens.
    struct VisibleCommand: Identifiable, Sendable {
        let command: Command
        let url: URL

        var id: String { command.id }
    }

    private(set) var file: CommandsFile
    private let url: URL
    private let sortByUses: Bool

    /// URL-launchable commands in display order: file order ("last modified"),
    /// or stable descending run count when the setting asks for it.
    private(set) var visible: [VisibleCommand] = []

    init(fileName: String, sortByUses: Bool) {
        url = AppDirectories.documents.appending(path: fileName)
        self.sortByUses = sortByUses
        file = AtomicJSON.load(CommandsFile.self, from: url, default: CommandsFile())
        rebuildVisible()
    }

    /// Re-read the file from disk — after a backup import replaced it.
    func reload() {
        file = AtomicJSON.load(CommandsFile.self, from: url, default: CommandsFile())
        rebuildVisible()
    }

    func recordRun(id: String) {
        file.recordRun(id: id)
        save()
    }

    /// Add a new command or replace an edited one, keyed by id.
    func upsert(_ command: Command) {
        file.upsert(command)
        save()
    }

    func delete(id: String) {
        file.remove(id: id)
        save()
    }

    private func save() {
        AtomicJSON.save(file, to: url)
        rebuildVisible()
    }

    private func rebuildVisible() {
        let launchable = file.commands.compactMap { command in
            CommandURL.launchURL(for: command).map { VisibleCommand(command: command, url: $0) }
        }
        if sortByUses {
            // Stable: equal run counts keep file order.
            visible = launchable.enumerated()
                .sorted { left, right in
                    let leftCount = left.element.command.runCount ?? 0
                    let rightCount = right.element.command.runCount ?? 0
                    if leftCount != rightCount {
                        return leftCount > rightCount
                    }
                    return left.offset < right.offset
                }
                .map(\.element)
        } else {
            visible = launchable
        }
    }
}
