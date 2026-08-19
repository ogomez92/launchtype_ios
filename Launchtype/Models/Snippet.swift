import Foundation

/// One text snippet: a file in `snippets/` whose name (up to the first dot,
/// lowercased) is the shortcut and whose body is what gets copied.
struct Snippet: Identifiable, Equatable, Sendable {
    /// The file name, unique within the folder.
    var fileName: String
    var shortcut: String
    var content: String

    var id: String { fileName }

    /// What fuzzy search runs over — shortcut then contents, like the desktop.
    var searchKey: String { "\(shortcut) \(content)" }

    init(fileName: String, content: String) {
        self.fileName = fileName
        self.content = content
        let base = fileName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
        shortcut = base.lowercased()
    }
}
