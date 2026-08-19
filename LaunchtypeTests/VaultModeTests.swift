import Foundation
import Testing
@testable import Launchtype

/// The vault's edges outside the crypto: the mode trigger, the settings it
/// reads, and the checks a vault file has to pass before it is written into
/// Documents.
struct VaultModeTests {
    @Test func asteriskSwitchesToVaultMode() {
        #expect(Mode.forTrigger("*") == .vault)
        #expect(Mode.vault.triggerChar == "*")
        // Every mode still owns its own character.
        #expect(Set(Mode.allCases.map(\.triggerChar)).count == Mode.allCases.count)
    }

    @Test func aSettingsFileFromBeforeTheVaultGetsTheVaultDefaults() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"enable_sounds": true}"#.utf8)
        )
        #expect(settings.vaultLockMinutes == AppSettings.defaultVaultLockMinutes)
        #expect(settings.vaultClipboardSeconds == AppSettings.defaultVaultClipboardSeconds)
    }

    @Test func theDesktopSettingsForTheVaultAreRead() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"vault_lock_minutes": 0, "vault_clipboard_seconds": 90}"#.utf8)
        )
        #expect(settings.vaultLockMinutes == 0, "0 means lock after every copy, not 'unset'")
        #expect(settings.vaultClipboardSeconds == 90)
    }

    @Test func onlyRealEntryFilesAreRecognized() {
        let nonce = Data(repeating: 0, count: 12)
        let ciphertextAndTag = Data(repeating: 0, count: 17)
        #expect(VaultFile.looksLikeEntry(Data("LTV1".utf8) + nonce + ciphertextAndTag))

        // Right magic, but too short to hold a nonce, a tag and any content.
        #expect(!VaultFile.looksLikeEntry(Data("LTV1".utf8) + nonce))
        #expect(!VaultFile.looksLikeEntry(Data("LTV1".utf8)))
        // Something else entirely.
        #expect(!VaultFile.looksLikeEntry(Data(repeating: 0x41, count: 200)))
        #expect(!VaultFile.looksLikeEntry(Data()))
    }

    /// A zip of the vault folder on its own must not have `vault/` stripped as
    /// if it were a wrapper folder — that would scatter the entries into
    /// Documents and leave the vault unopenable.
    @Test func aVaultFolderAtTheZipRootIsNotTreatedAsAWrapper() {
        let normalized = DataArchive.normalized(paths: [
            "vault/vault.meta",
            "vault/2feb3621-f822-4549-bf86-7b06924885e1.enc",
        ])
        #expect(normalized == [
            "vault/vault.meta",
            "vault/2feb3621-f822-4549-bf86-7b06924885e1.enc",
        ])
    }

    @Test func aWholeBackupKeepsItsVaultFolder() {
        let normalized = DataArchive.normalized(paths: [
            "Launchtype/commands.json",
            "Launchtype/vault/vault.meta",
            "Launchtype/vault/2feb3621-f822-4549-bf86-7b06924885e1.enc",
        ])
        #expect(normalized == [
            "commands.json",
            "vault/vault.meta",
            "vault/2feb3621-f822-4549-bf86-7b06924885e1.enc",
        ])
    }
}
