import Foundation

/// Everything that can go wrong with the vault, in the desktop app's terms.
enum VaultError: Error, LocalizedError, Equatable {
    /// The master key did not unwrap the vault key: the password is wrong (or
    /// `vault.meta` belongs to a different vault).
    case wrongPassword
    /// A file is not a vault file, or has been altered since it was written.
    case damaged
    /// An operation that needs the key was attempted while locked.
    case locked
    case noSuchEntry
    /// Creating a vault where one already exists. Refused rather than obliged:
    /// a second `vault.meta` would hold a different vault key, and every entry
    /// written under the first one would become unopenable.
    case alreadyExists
    case passwordTooShort
    case io(String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword: "That is not the master password."
        case .damaged: "That vault file is damaged, or is not a vault file."
        case .locked: "The vault is locked."
        case .noSuchEntry: "That entry is no longer in the vault."
        case .alreadyExists: "There is already a vault in that folder."
        case .passwordTooShort:
            "The master password must be at least \(VaultSession.minimumPasswordLength) characters long."
        case .io(let message): message
        }
    }
}
