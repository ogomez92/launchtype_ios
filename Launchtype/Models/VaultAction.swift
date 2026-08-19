import Foundation

/// A vault row that does something rather than holding a secret.
///
/// The locked vault shows exactly one of these, so there is always something
/// to activate and never a dead end; the rest sit at the bottom of an unlocked
/// vault's list, and only when nothing has been typed, so they never come
/// between the user and the entry they are looking for.
enum VaultAction: String, Identifiable, Sendable {
    case create
    case unlock
    case lock
    case add
    case changePassword

    var id: String { rawValue }

    var label: String {
        switch self {
        case .create: "Set up the vault: choose a master password"
        case .unlock: "Unlock the vault"
        case .lock: "Lock the vault now"
        case .add: "The vault is empty. Activate this row to put a secret in it."
        case .changePassword: "Change the master password"
        }
    }
}
