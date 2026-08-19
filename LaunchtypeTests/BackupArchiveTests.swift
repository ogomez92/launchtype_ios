import Foundation
import Testing
@testable import Launchtype

struct BackupArchiveTests {
    /// A system-made zip (the same coordinated-read mechanism export uses)
    /// must read back byte-identical through our ZipReader.
    @Test func zipRoundTripReadsBackContents() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ZipTest-\(UUID().uuidString)")
        let folder = root.appending(path: "Launchtype")
        try fileManager.createDirectory(
            at: folder.appending(path: "snippets"),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }
        try #"{"commands": []}"#.write(
            to: folder.appending(path: "commands.json"), atomically: true, encoding: .utf8
        )
        let body = String(repeating: "hello snippets ", count: 500)
        try body.write(
            to: folder.appending(path: "snippets/greet.txt"), atomically: true, encoding: .utf8
        )

        var coordinationError: NSError?
        var zipData: Data?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinationError
        ) { url in
            zipData = try? Data(contentsOf: url)
        }
        #expect(coordinationError == nil)

        let reader = try ZipReader(data: try #require(zipData))
        let paths = Set(reader.entries.filter { !$0.isDirectory }.map(\.path))
        #expect(paths.contains("Launchtype/commands.json"))
        #expect(paths.contains("Launchtype/snippets/greet.txt"))
        let entry = try #require(reader.entries.first { $0.path.hasSuffix("greet.txt") })
        #expect(try reader.contents(of: entry) == Data(body.utf8))
    }

    @Test func normalizationStripsWrapperAndJunk() {
        let normalized = DataArchive.normalized(paths: [
            "Launchtype/",
            "Launchtype/commands.json",
            "Launchtype/snippets/a.txt",
            "__MACOSX/Launchtype/._commands.json",
            "Launchtype/.DS_Store",
        ])
        #expect(normalized == [nil, "commands.json", "snippets/a.txt", nil, nil])
    }

    @Test func dataFolderAtRootIsNotTreatedAsWrapper() {
        let normalized = DataArchive.normalized(paths: ["snippets/a.txt", "snippets/b.txt"])
        #expect(normalized == ["snippets/a.txt", "snippets/b.txt"])
    }

    @Test func traversalAndAbsolutePathsAreDropped() {
        let normalized = DataArchive.normalized(paths: [
            "../outside.txt",
            "/etc/passwd",
            "timers.json",
        ])
        #expect(normalized == [nil, nil, "timers.json"])
    }

    @Test func garbageIsNotAZip() {
        #expect(throws: ZipReader.ZipError.self) {
            _ = try ZipReader(data: Data("definitely not a zip archive".utf8))
        }
    }
}
