import Foundation

/// First-launch seeding and notification-sound syncing. Seeding copies the
/// bundled desktop data into Documents item by item, never overwriting a file
/// the user already has, so a partially customized install survives updates.
enum DataBootstrap {
    static func run() {
        seedIfNeeded()
        syncNotificationSounds()
    }

    private static func seedIfNeeded() {
        guard let seed = AppDirectories.seedData else {
            return
        }
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: seed, includingPropertiesForKeys: nil)) ?? []
        for source in contents {
            let destination = AppDirectories.documents.appending(path: source.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path()) {
                try? fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    /// iOS only plays custom notification sounds from `Library/Sounds`, so the
    /// user-visible `Documents/sounds` folder is mirrored there each launch —
    /// a file replaced through the Files app takes effect on next start.
    /// Internal so a backup import can re-mirror immediately.
    static func syncNotificationSounds() {
        let fileManager = FileManager.default
        let library = AppDirectories.librarySounds
        try? fileManager.createDirectory(at: library, withIntermediateDirectories: true)
        let playable: Set<String> = ["wav", "caf", "aiff", "aif"]
        let sounds = (try? fileManager.contentsOfDirectory(at: AppDirectories.sounds, includingPropertiesForKeys: nil)) ?? []
        for source in sounds where playable.contains(source.pathExtension.lowercased()) {
            let destination = library.appending(path: source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path()) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }
}
