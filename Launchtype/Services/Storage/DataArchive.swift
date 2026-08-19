import Foundation

/// Whole-app backup. Export zips everything in Documents — every commands
/// file, the snippets and sounds folders, timers, alarms, and settings — via
/// the system's coordinated-read zipping. Import validates a backup zip
/// (every recognized JSON file must decode against the real schema) before a
/// single byte is written into Documents.
enum DataArchive {
    struct ImportSummary {
        var commands = 0
        var commandFiles = 0
        var snippets = 0
        var timers = 0
        var alarms = 0
        var soundFiles = 0
        var settingsFiles = 0
        /// Encrypted vault entries. Nothing is decrypted on the way in — the
        /// files are copied as they are, and the master password opens them
        /// afterwards exactly as it did on the machine they came from.
        var vaultEntries = 0

        var announcement: String {
            let base = "Import complete: \(commands) commands, \(snippets) snippets, "
                + "\(timers) timers, \(alarms) alarms"
            return vaultEntries == 0 ? base : base + ", \(vaultEntries) vault entries"
        }
    }

    enum ArchiveError: Error, LocalizedError {
        case unreadable
        case nothingRecognized
        case invalidFile(String)
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "The file could not be read."
            case .nothingRecognized: "The archive contains no Launchtype data."
            case .invalidFile(let name): "\(name) is not valid Launchtype data."
            case .exportFailed: "The backup could not be created."
            }
        }
    }

    /// Folders whose names identify data even at the zip root, so wrapper
    /// stripping never mistakes them for a wrapper.
    private static let dataFolders: Set<String> = ["snippets", "sounds", "vault"]

    // MARK: - Export

    /// Zip the whole Documents folder and return the archive's temporary URL.
    static func exportZip() throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appending(path: "LaunchtypeExport", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        defer { try? fileManager.removeItem(at: staging) }
        // Copy into a folder named "Launchtype" so the zip root reads well.
        let root = staging.appending(path: "Launchtype", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(
            at: AppDirectories.documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in items {
            try fileManager.copyItem(at: item, to: root.appending(path: item.lastPathComponent))
        }

        // A coordinated read for uploading hands back the folder as a zip.
        var coordinationError: NSError?
        var copyError: Error?
        var archiveURL: URL?
        NSFileCoordinator().coordinate(
            readingItemAt: root,
            options: .forUploading,
            error: &coordinationError
        ) { zipped in
            let stamp = Date.now.formatted(Date.ISO8601FormatStyle().year().month().day())
            let destination = fileManager.temporaryDirectory.appending(path: "Launchtype-\(stamp).zip")
            do {
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: zipped, to: destination)
                archiveURL = destination
            } catch {
                copyError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
        guard let archiveURL else {
            throw ArchiveError.exportFailed
        }
        return archiveURL
    }

    // MARK: - Import

    /// Validate a backup zip and write its recognized files into Documents.
    /// Throws before writing anything if any recognized file fails to decode.
    static func importZip(at url: URL) throws -> ImportSummary {
        guard let data = try? Data(contentsOf: url) else {
            throw ArchiveError.unreadable
        }
        let reader = try ZipReader(data: data)
        let relativePaths = normalized(paths: reader.entries.map(\.path))
        var summary = ImportSummary()
        var payloads: [(path: String, contents: Data)] = []
        for (entry, relativePath) in zip(reader.entries, relativePaths) {
            guard let relativePath else {
                continue
            }
            let contents = try reader.contents(of: entry)
            if try validate(path: relativePath, contents: contents, into: &summary) {
                payloads.append((relativePath, contents))
            }
        }
        guard !payloads.isEmpty else {
            throw ArchiveError.nothingRecognized
        }
        let fileManager = FileManager.default
        for payload in payloads {
            let destination = AppDirectories.documents.appending(path: payload.path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.contents.write(to: destination, options: .atomic)
        }
        return summary
    }

    /// Map raw zip entry paths to Documents-relative paths. Folder entries,
    /// AppleDouble/hidden junk, and traversal attempts map to nil, and one
    /// wrapper folder — the root this app's export or Finder compression adds
    /// — is stripped, unless that root is itself a data folder.
    static func normalized(paths: [String]) -> [String?] {
        var result: [String?] = paths.map { path in
            guard !path.hasSuffix("/"), !path.hasPrefix("/") else {
                return nil
            }
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty,
                  !components.contains(where: { $0 == ".." || $0 == "__MACOSX" || $0.hasPrefix(".") }) else {
                return nil
            }
            return components.joined(separator: "/")
        }
        let kept = result.compactMap(\.self)
        let roots = Set(kept.compactMap { $0.split(separator: "/").first.map(String.init) })
        if roots.count == 1, let root = roots.first,
           !dataFolders.contains(root.lowercased()),
           kept.allSatisfy({ $0.contains("/") }) {
            result = result.map { path in
                path.map { String($0.dropFirst(root.count + 1)) }
            }
        }
        return result
    }

    /// Check one file and count what it contains. Returns whether the file is
    /// recognized and should be written; unknown files are skipped, and a
    /// recognized file that fails to decode aborts the whole import.
    private static func validate(
        path: String,
        contents: Data,
        into summary: inout ImportSummary
    ) throws -> Bool {
        let decoder = JSONDecoder()
        let lowered = path.lowercased()
        if lowered.hasPrefix("snippets/") {
            guard String(data: contents, encoding: .utf8) != nil else {
                throw ArchiveError.invalidFile(path)
            }
            summary.snippets += 1
            return true
        }
        if lowered.hasPrefix("sounds/") {
            summary.soundFiles += 1
            return true
        }
        if lowered.hasPrefix("vault/") {
            return try validateVaultFile(path: path, contents: contents, into: &summary)
        }
        guard !path.contains("/") else {
            return false
        }
        if lowered == "timers.json" {
            guard let defs = try? decoder.decode([TimerDef].self, from: contents) else {
                throw ArchiveError.invalidFile(path)
            }
            summary.timers += defs.count
            return true
        }
        if lowered == "alarms.json" {
            guard let defs = try? decoder.decode([AlarmDef].self, from: contents) else {
                throw ArchiveError.invalidFile(path)
            }
            summary.alarms += defs.count
            return true
        }
        if lowered == "settings.json" {
            guard (try? decoder.decode(AppSettings.self, from: contents)) != nil else {
                throw ArchiveError.invalidFile(path)
            }
            summary.settingsFiles += 1
            return true
        }
        if lowered.hasSuffix(".json") {
            // Any other root-level JSON is a commands file (commands.json,
            // work.json, …), like the desktop app allows.
            guard let file = try? decoder.decode(CommandsFile.self, from: contents) else {
                throw ArchiveError.invalidFile(path)
            }
            summary.commands += file.commands.count
            summary.commandFiles += 1
            return true
        }
        return false
    }

    /// One file out of a backup's `vault/` folder. The two shapes it can have
    /// are checked as far as they can be without the master password — a key
    /// file that parses, an entry file with the right magic — so a mangled
    /// vault is refused at import rather than at unlock, when the user would
    /// have no way to tell a bad file from a mistyped password.
    private static func validateVaultFile(
        path: String,
        contents: Data,
        into summary: inout ImportSummary
    ) throws -> Bool {
        let name = path.split(separator: "/").dropFirst().joined(separator: "/")
        if name.lowercased() == VaultFile.metaName {
            guard (try? JSONDecoder().decode(VaultFile.Meta.self, from: contents)) != nil else {
                throw ArchiveError.invalidFile(path)
            }
            return true
        }
        guard name.lowercased().hasSuffix(".\(VaultFile.entryExtension)"), !name.contains("/") else {
            return false
        }
        guard VaultFile.looksLikeEntry(contents) else {
            throw ArchiveError.invalidFile(path)
        }
        summary.vaultEntries += 1
        return true
    }
}
