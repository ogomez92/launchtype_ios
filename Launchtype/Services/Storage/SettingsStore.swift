import Foundation

/// Loads `settings.json` once at startup. Read-only: the file belongs to the
/// desktop app and is edited through the Files app; never rewriting it means
/// never dropping the desktop-only keys.
@MainActor
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings

    init() {
        let url = AppDirectories.documents.appending(path: "settings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }
}
