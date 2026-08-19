import Foundation

/// The subset of `settings.json` this port reads. The file is owned by the
/// desktop app and edited through the Files app; iOS never writes it, so the
/// desktop's other keys are left untouched on disk.
struct AppSettings: Sendable {
    /// Long enough to look several secrets up in one sitting, short enough
    /// that walking away from the device closes the vault behind you.
    static let defaultVaultLockMinutes = 5

    /// Long enough to switch apps and paste, short enough that a password is
    /// not still on the clipboard an hour later.
    static let defaultVaultClipboardSeconds = 30

    var enableSounds = true
    var commandSortByUses = false
    var commandsFile = "commands.json"
    var language = "system"

    /// Minutes the encrypted vault stays unlocked without being used before
    /// its key is dropped. 0 additionally re-locks it the moment a secret has
    /// been copied, so the master password is asked for every single time.
    var vaultLockMinutes = AppSettings.defaultVaultLockMinutes

    /// Seconds after which a copied vault secret leaves the clipboard,
    /// provided nothing else has been copied since. 0 never clears.
    var vaultClipboardSeconds = AppSettings.defaultVaultClipboardSeconds

    /// The emoji table language: an explicit `en`/`es`, or the device
    /// language when set to `system`.
    var emojiLanguage: String {
        if language == "system" {
            return Locale.current.language.languageCode?.identifier == "es" ? "es" : "en"
        }
        return language
    }
}

extension AppSettings: Decodable {
    enum CodingKeys: String, CodingKey {
        case enableSounds = "enable_sounds"
        case commandSortByUses = "command_sort_by_uses"
        case commandsFile = "commands_file"
        case language
        case vaultLockMinutes = "vault_lock_minutes"
        case vaultClipboardSeconds = "vault_clipboard_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableSounds = try container.decodeIfPresent(Bool.self, forKey: .enableSounds) ?? true
        commandSortByUses = try container.decodeIfPresent(Bool.self, forKey: .commandSortByUses) ?? false
        commandsFile = try container.decodeIfPresent(String.self, forKey: .commandsFile) ?? "commands.json"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "system"
        // A settings.json written before the vault existed must not read as
        // "never lock" / "never clear the clipboard".
        vaultLockMinutes = try container.decodeIfPresent(Int.self, forKey: .vaultLockMinutes)
            ?? Self.defaultVaultLockMinutes
        vaultClipboardSeconds = try container.decodeIfPresent(Int.self, forKey: .vaultClipboardSeconds)
            ?? Self.defaultVaultClipboardSeconds
    }
}
