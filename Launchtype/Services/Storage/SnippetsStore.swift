import Foundation

/// Loads every file in `Documents/snippets` as a snippet: the file name up to
/// the first dot (lowercased) is the shortcut, the body is what gets copied.
@MainActor
@Observable
final class SnippetsStore {
    private(set) var snippets: [Snippet] = []

    init() {
        reload()
    }

    /// Whether another snippet already owns this shortcut. Editors use this to
    /// refuse a save that would silently overwrite a different file.
    func isShortcutTaken(_ shortcut: String, excluding original: Snippet?) -> Bool {
        snippets.contains { $0.shortcut == shortcut && $0.fileName != original?.fileName }
    }

    /// Write a snippet. `original` nil means a new file; a changed shortcut
    /// renames by deleting the old file and writing `<shortcut>.txt`.
    func save(shortcut: String, content: String, replacing original: Snippet?) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AppDirectories.snippets, withIntermediateDirectories: true)
        let fileName: String
        if let original, original.shortcut == shortcut {
            fileName = original.fileName
        } else {
            fileName = "\(shortcut).txt"
            if let original {
                try? fileManager.removeItem(at: AppDirectories.snippets.appending(path: original.fileName))
            }
        }
        try? content.write(
            to: AppDirectories.snippets.appending(path: fileName),
            atomically: true,
            encoding: .utf8
        )
        reload()
    }

    func delete(_ snippet: Snippet) {
        try? FileManager.default.removeItem(at: AppDirectories.snippets.appending(path: snippet.fileName))
        reload()
    }

    func reload() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AppDirectories.snippets, withIntermediateDirectories: true)
        let files = (try? fileManager.contentsOfDirectory(
            at: AppDirectories.snippets,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        snippets = files
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return Snippet(fileName: url.lastPathComponent, content: content)
            }
    }
}
