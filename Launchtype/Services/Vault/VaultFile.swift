import Foundation

/// The on-disk shapes of the vault, which are the desktop app's and must stay
/// byte-compatible with it: a vault folder copied from Windows has to open
/// here, and one made here has to open there.
enum VaultFile {
    /// The vault folder, inside Documents (so it is reachable through the
    /// Files app, like `snippets/`).
    static let directoryName = "vault"

    /// Holds the wrapped vault key. Its absence is what "the vault has not
    /// been set up yet" means.
    static let metaName = "vault.meta"

    static let entryExtension = "enc"

    /// First four bytes of every entry file, so a truncated or unrelated file
    /// is rejected before anything is fed to the cipher.
    static let magic = Data("LTV1".utf8)

    /// Associated data for the wrapped vault key: it is not an entry, so it
    /// must not be interchangeable with one.
    static let metaAssociatedData = Data("launchtype-vault-key".utf8)

    static let keyLength = 32
    static let saltLength = 16

    /// `vault/vault.meta`. Field names and order are the desktop app's.
    struct Meta: Codable, Sendable {
        var version: Int
        var kdf: String
        var mCost: UInt32
        var tCost: UInt32
        var pCost: UInt32
        /// Argon2id salt, base64.
        var salt: String
        /// nonce + sealed vault key, base64.
        var wrappedKey: String

        enum CodingKeys: String, CodingKey {
            case version
            case kdf
            case mCost = "m_cost"
            case tCost = "t_cost"
            case pCost = "p_cost"
            case salt
            case wrappedKey = "wrapped_key"
        }

        var parameters: Argon2id.Parameters {
            Argon2id.Parameters(memoryKiB: mCost, iterations: tCost, parallelism: pCost)
        }

        init(parameters: Argon2id.Parameters, salt: Data, wrappedKey: Data) {
            version = 1
            kdf = "argon2id"
            mCost = parameters.memoryKiB
            tCost = parameters.iterations
            pCost = parameters.parallelism
            self.salt = salt.base64EncodedString()
            self.wrappedKey = wrappedKey.base64EncodedString()
        }
    }

    /// The sealed payload of an entry file.
    struct EntryData: Codable, Sendable {
        var name: String
        var shortcut: String
        var secret: String

        init(name: String, shortcut: String, secret: String) {
            self.name = name
            self.shortcut = shortcut
            self.secret = secret
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            // The desktop app defaults a missing shortcut rather than failing.
            shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
            secret = try container.decode(String.self, forKey: .secret)
        }
    }

    /// Whether `data` could be a vault entry file at all — the check the zip
    /// importer runs before writing one into Documents.
    static func looksLikeEntry(_ data: Data) -> Bool {
        // Magic, a 12-byte nonce and a 16-byte tag, so anything this short
        // cannot be an entry whatever it claims.
        data.count > magic.count + 28 && data.prefix(magic.count) == magic
    }
}
