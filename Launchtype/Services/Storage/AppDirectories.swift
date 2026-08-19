import Foundation

/// Where the app's data lives. Everything the desktop app kept next to its
/// executable lives in Documents here, exposed through the Files app so the
/// user can drop their real data in.
enum AppDirectories {
    static var documents: URL { URL.documentsDirectory }

    static var snippets: URL { documents.appending(path: "snippets") }

    /// The encrypted vault, portable in exactly the way the desktop app's is:
    /// drop the folder in through the Files app and the same master password
    /// opens it.
    static var vault: URL { documents.appending(path: VaultFile.directoryName) }

    static var sounds: URL { documents.appending(path: "sounds") }

    /// Where iOS looks for custom notification sounds.
    static var librarySounds: URL {
        URL.libraryDirectory.appending(path: "Sounds")
    }

    /// The bundled copy of the desktop data used to seed Documents.
    static var seedData: URL? {
        Bundle.main.url(forResource: "SeedData", withExtension: nil)
    }
}
