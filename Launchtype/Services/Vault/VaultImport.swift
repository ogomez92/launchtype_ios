import Foundation

/// Bringing a vault over from the desktop app.
///
/// The vault is portable by design — a folder of `vault.meta` plus one `.enc`
/// file per entry, all of it useless without the master password — so
/// importing is a copy and nothing more. What this adds is the checking: that
/// the folder really is a vault, and that copying it will not strand entries
/// that are already on the phone.
///
/// A backup zip that contains a `vault/` folder is handled by ``DataArchive``
/// instead; this is the path for the folder itself, dropped in through the
/// Files app or picked from iCloud Drive.
enum VaultImport {
    enum ImportError: Error, LocalizedError, Equatable {
        case notAVault
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notAVault:
                "That folder is not a Launchtype vault: it has no vault.meta file in it."
            case .unreadable(let message):
                message
            }
        }
    }

    /// A vault folder that has been read and checked but not yet written.
    struct Candidate {
        var meta: Data
        var entries: [(name: String, contents: Data)]

        var entryCount: Int { entries.count }
    }

    /// What the import did, for the announcement afterwards.
    struct Summary: Equatable {
        var entries: Int
        /// Whether a vault that was already on this device was replaced. Its
        /// entries, if any, can no longer be opened by any password.
        var replacedExistingVault: Bool

        var announcement: String {
            entries == 1
                ? "Vault imported: 1 entry"
                : "Vault imported: \(entries) entries"
        }
    }

    /// Read the vault out of `folder`, which may be the vault folder itself or
    /// a folder with one inside it (the whole Launchtype folder, say).
    ///
    /// Everything is read and checked before anything is written, so a folder
    /// that turns out not to be a vault leaves the device's own vault alone.
    static func candidate(at folder: URL) throws -> Candidate {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        var root = folder
        if !fileManager.fileExists(atPath: root.appending(path: VaultFile.metaName).path()) {
            root = folder.appending(path: VaultFile.directoryName)
        }
        guard let meta = try? Data(contentsOf: root.appending(path: VaultFile.metaName)),
              (try? JSONDecoder().decode(VaultFile.Meta.self, from: meta)) != nil else {
            throw ImportError.notAVault
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }

        var entries: [(name: String, contents: Data)] = []
        for url in contents where url.pathExtension == VaultFile.entryExtension {
            guard let data = try? Data(contentsOf: url) else {
                throw ImportError.unreadable("\(url.lastPathComponent) could not be read.")
            }
            // A file that is not an entry is skipped rather than copied in to
            // fail later at unlock time.
            if VaultFile.looksLikeEntry(data) {
                entries.append((url.lastPathComponent, data))
            }
        }
        return Candidate(meta: meta, entries: entries)
    }

    /// Whether writing `candidate` would replace a vault already on the
    /// device — which the caller must confirm first, because the entries here
    /// now would stop opening: they are sealed with the vault key inside the
    /// `vault.meta` about to be overwritten.
    static func wouldReplaceExistingVault() -> Bool {
        FileManager.default.fileExists(
            atPath: AppDirectories.vault.appending(path: VaultFile.metaName).path()
        )
    }

    /// Write a checked candidate into `Documents/vault`.
    @discardableResult
    static func write(_ candidate: Candidate) throws -> Summary {
        let replacing = wouldReplaceExistingVault()
        let directory = AppDirectories.vault
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try candidate.meta.write(
                to: directory.appending(path: VaultFile.metaName),
                options: [.atomic, .completeFileProtection]
            )
            for entry in candidate.entries {
                try entry.contents.write(
                    to: directory.appending(path: entry.name),
                    options: [.atomic, .completeFileProtection]
                )
            }
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        return Summary(entries: candidate.entries.count, replacedExistingVault: replacing)
    }
}
