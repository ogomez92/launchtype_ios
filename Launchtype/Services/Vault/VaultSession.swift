import CryptoKit
import Foundation

/// The encrypted vault behind `*` mode: passwords and other secrets living in
/// `Documents/vault` as AES-256-GCM `.enc` files that only exist in the clear
/// inside this process, for as long as the vault is unlocked.
///
/// # How it is keyed
///
/// Two keys, not one. `vault/vault.meta` holds a random 32-byte *vault key*
/// wrapped with a *master key* that Argon2id stretches out of the master
/// password; the entries are sealed with the vault key. The indirection buys
/// two things: changing the master password rewrites one small file instead of
/// re-encrypting every entry, and the password itself is never the thing an
/// entry file was encrypted with.
///
/// # What an attacker with the folder learns
///
/// Only how many entries there are and roughly how long each one is. An entry
/// file is named after a random uuid and holds nothing but a nonce and
/// ciphertext — the entry's *name* and shortcut are inside the sealed payload
/// along with the secret, because "amazon" or "work vpn" sitting in a file
/// name gives away most of what a password list is worth. The uuid is
/// authenticated as associated data, so entry files cannot be swapped around.
///
/// The format is the desktop app's, exactly: a `vault` folder copied off a
/// Windows install opens here with the same master password, and one made here
/// opens there.
@MainActor
@Observable
final class VaultSession {
    /// Master passwords shorter than this are refused outright. Everything in
    /// the vault is only ever as strong as this one string.
    nonisolated static let minimumPasswordLength = 8

    private let directory: URL
    private let kdf: Argon2id.Parameters

    /// Minutes of inactivity before the key is dropped; 0 additionally means
    /// "lock the moment a secret has been copied" (see ``locksOnUse``).
    var lockAfterMinutes: Int

    /// Entry names and shortcuts, sorted by name; empty while locked.
    private(set) var entries: [VaultEntry] = []

    /// The vault key, in memory only, only while unlocked. `SymmetricKey`
    /// zeroes its own storage when it goes away, which is why the key is kept
    /// as one rather than as `Data`.
    private var key: SymmetricKey?
    private var lastUsed: Date?

    init(
        directory: URL = AppDirectories.vault,
        lockAfterMinutes: Int,
        kdf: Argon2id.Parameters = .strong
    ) {
        self.directory = directory
        self.lockAfterMinutes = lockAfterMinutes
        self.kdf = kdf
    }

    // MARK: - State

    /// True when there is no vault yet, so the next visit asks for a master
    /// password to create one.
    var isNew: Bool {
        !FileManager.default.fileExists(atPath: metaURL.path())
    }

    var isUnlocked: Bool {
        key != nil
    }

    /// Whether the vault re-locks as soon as a secret has been copied.
    var locksOnUse: Bool {
        lockAfterMinutes == 0
    }

    /// Encrypted entries sitting in the folder without the `vault.meta` that
    /// holds the key to them. Normally zero; anything else means the key file
    /// was lost or the folder was half-copied, and creating a fresh vault
    /// would strand them — so the app says so before it does.
    var orphanCount: Int {
        entryIDs.count
    }

    /// Drop the key and the entry list. Idempotent.
    func lock() {
        key = nil
        entries = []
        lastUsed = nil
    }

    /// Push the idle deadline out; called after every successful use.
    func touch(_ now: Date = .now) {
        if key != nil {
            lastUsed = now
        }
    }

    /// Lock if the vault has gone untouched for the configured time. Returns
    /// whether it locked, so the caller can react.
    ///
    /// A zero timeout means "lock after each copy", which the copy path does
    /// itself; here it is read as one minute, so a vault unlocked and then
    /// abandoned without copying anything still does not stay open.
    @discardableResult
    func expire(_ now: Date = .now) -> Bool {
        guard let lastUsed else {
            return false
        }
        let idle = TimeInterval(max(lockAfterMinutes, 1) * 60)
        guard now.timeIntervalSince(lastUsed) >= idle else {
            return false
        }
        lock()
        return true
    }

    // MARK: - Opening and closing

    /// Create the vault and unlock it. Fails if one is already there.
    func create(password: String, now: Date = .now) async throws {
        guard isNew else {
            throw VaultError.alreadyExists
        }
        guard password.count >= Self.minimumPasswordLength else {
            throw VaultError.passwordTooShort
        }
        try makeDirectory()
        let vaultKey = SymmetricKey(size: .bits256)
        try await writeMeta(password: password, vaultKey: vaultKey)
        key = vaultKey
        entries = readEntries()
        lastUsed = now
    }

    /// Unwrap the vault key with `password` and read the entry list in.
    func unlock(password: String, now: Date = .now) async throws {
        let vaultKey = try await unwrapKey(password: password)
        key = vaultKey
        entries = readEntries()
        lastUsed = now
    }

    /// Re-wrap the vault key under a new master password. The entries are not
    /// touched — they were never encrypted with the password to begin with.
    func changePassword(current: String, new: String) async throws {
        guard new.count >= Self.minimumPasswordLength else {
            throw VaultError.passwordTooShort
        }
        let vaultKey = try await unwrapKey(password: current)
        try await writeMeta(password: new, vaultKey: vaultKey)
    }

    // MARK: - Entries

    /// Decrypt one entry's secret. Reads the file each time rather than
    /// holding secrets in the session, so an unlocked vault only ever has the
    /// one being used in memory.
    func secret(id: String) throws -> String {
        try readEntry(id: id).secret
    }

    /// The stored name, shortcut and secret, for the edit sheet.
    func draft(id: String) throws -> VaultEntryDraft {
        let data = try readEntry(id: id)
        return VaultEntryDraft(id: id, name: data.name, shortcut: data.shortcut, secret: data.secret)
    }

    /// Add (`id` = nil) or overwrite an entry, and return its id. Every write
    /// reseals with a fresh nonce.
    @discardableResult
    func save(id: String?, name: String, shortcut: String, secret: String) throws -> String {
        guard let key else {
            throw VaultError.locked
        }
        let id = id ?? UUID().uuidString.lowercased()
        let data = VaultFile.EntryData(
            name: name.trimmingCharacters(in: .whitespaces),
            shortcut: shortcut.trimmingCharacters(in: .whitespaces).lowercased(),
            secret: secret
        )
        guard let plaintext = try? JSONEncoder().encode(data) else {
            throw VaultError.damaged
        }
        let sealed = try seal(plaintext, using: key, authenticating: Data(id.utf8))
        try makeDirectory()
        try write(VaultFile.magic + sealed, to: entryURL(id))

        let entry = VaultEntry(id: id, name: data.name, shortcut: data.shortcut)
        if let existing = entries.firstIndex(where: { $0.id == id }) {
            entries[existing] = entry
        } else {
            entries.append(entry)
        }
        entries = Self.sorted(entries)
        return id
    }

    /// Delete an entry's file. Unrecoverable, which is why the UI asks first.
    func delete(id: String) throws {
        guard entries.contains(where: { $0.id == id }) else {
            throw VaultError.noSuchEntry
        }
        do {
            try FileManager.default.removeItem(at: entryURL(id))
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
        entries.removeAll { $0.id == id }
    }

    // MARK: - Keys

    /// Derive the master key from `password` and unwrap the vault key with it.
    private func unwrapKey(password: String) async throws -> SymmetricKey {
        let raw: Data
        do {
            raw = try Data(contentsOf: metaURL)
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
        guard let meta = try? JSONDecoder().decode(VaultFile.Meta.self, from: raw),
              let salt = Data(base64Encoded: meta.salt),
              let wrapped = Data(base64Encoded: meta.wrappedKey) else {
            throw VaultError.damaged
        }
        // The vault's own recorded cost, not this session's: raising the cost
        // must never orphan a vault made under the old one.
        let master = try await Self.deriveMasterKey(
            password: password,
            salt: salt,
            parameters: meta.parameters
        )
        let plain = try open(
            wrapped,
            using: master,
            authenticating: VaultFile.metaAssociatedData,
            onTagFailure: .wrongPassword
        )
        guard plain.count == VaultFile.keyLength else {
            throw VaultError.damaged
        }
        return SymmetricKey(data: plain)
    }

    /// Wrap `vaultKey` under a master key freshly derived from `password` (new
    /// salt every time) and write `vault.meta`.
    private func writeMeta(password: String, vaultKey: SymmetricKey) async throws {
        let salt = Self.randomBytes(count: VaultFile.saltLength)
        let master = try await Self.deriveMasterKey(password: password, salt: salt, parameters: kdf)
        let wrapped = try vaultKey.withUnsafeBytes { raw in
            try seal(Data(raw), using: master, authenticating: VaultFile.metaAssociatedData)
        }
        let meta = VaultFile.Meta(parameters: kdf, salt: salt, wrappedKey: wrapped)
        let encoder = JSONEncoder()
        // Indented, with the base64 left alone rather than backslash-escaped,
        // so the file reads like the desktop app's. Key order is whatever
        // JSONEncoder picks; the desktop parses the keys, not their order.
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(meta) else {
            throw VaultError.damaged
        }
        try makeDirectory()
        try write(json, to: metaURL)
    }

    /// Stretch the master password. Argon2id at the shipped cost allocates
    /// 256 MiB and runs for about a second, so it happens off the main actor —
    /// the one part of the vault that is not main-actor work.
    private nonisolated static func deriveMasterKey(
        password: String,
        salt: Data,
        parameters: Argon2id.Parameters
    ) async throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        let derived = await Task.detached(priority: .userInitiated) {
            Argon2id.hash(
                password: passwordBytes,
                salt: saltBytes,
                parameters: parameters,
                length: VaultFile.keyLength
            )
        }.value
        guard var derived else {
            // Only reachable from cost parameters Argon2 does not define,
            // which means a `vault.meta` that has been damaged or edited.
            throw VaultError.damaged
        }
        defer { Zeroize.wipe(&derived) }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(count: Int) -> Data {
        // The system CSPRNG, by way of the one key generator CryptoKit exposes.
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    // MARK: - Sealing

    /// Seal `plaintext`, returning `nonce || ciphertext || tag` — the layout
    /// the desktop app's `aes-gcm` crate writes.
    private func seal(_ plaintext: Data, using key: SymmetricKey, authenticating aad: Data) throws -> Data {
        guard let sealed = try? AES.GCM.seal(plaintext, using: key, authenticating: aad),
              let combined = sealed.combined else {
            throw VaultError.damaged
        }
        return combined
    }

    /// The inverse of ``seal(_:using:authenticating:)``. A failed tag check is
    /// reported as `wrongPassword` or `damaged` depending on what the caller
    /// was doing: the same AEAD failure means "you typed the wrong password"
    /// when unwrapping the vault key and "this file has been altered" for an
    /// entry.
    private func open(
        _ sealed: Data,
        using key: SymmetricKey,
        authenticating aad: Data,
        onTagFailure: VaultError
    ) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: sealed) else {
            throw VaultError.damaged
        }
        guard let plain = try? AES.GCM.open(box, using: key, authenticating: aad) else {
            throw onTagFailure
        }
        return plain
    }

    // MARK: - Files

    private var metaURL: URL {
        directory.appending(path: VaultFile.metaName)
    }

    private func entryURL(_ id: String) -> URL {
        directory.appending(path: "\(id).\(VaultFile.entryExtension)")
    }

    /// The uuids of every `.enc` file in the vault folder.
    private var entryIDs: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == VaultFile.entryExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private func readEntry(id: String) throws -> VaultFile.EntryData {
        guard let key else {
            throw VaultError.locked
        }
        let raw: Data
        do {
            raw = try Data(contentsOf: entryURL(id))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw VaultError.noSuchEntry
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
        guard VaultFile.looksLikeEntry(raw) else {
            throw VaultError.damaged
        }
        // The uuid is authenticated, so an entry file renamed onto another
        // entry's name fails here rather than impersonating it.
        let plain = try open(
            raw.dropFirst(VaultFile.magic.count),
            using: key,
            authenticating: Data(id.utf8),
            onTagFailure: .damaged
        )
        guard let data = try? JSONDecoder().decode(VaultFile.EntryData.self, from: plain) else {
            throw VaultError.damaged
        }
        return data
    }

    /// Decrypt every entry in the folder for its name and shortcut. A file
    /// that will not open is skipped rather than failing the unlock: one
    /// damaged entry must not take the rest of the vault down with it.
    private func readEntries() -> [VaultEntry] {
        let entries = entryIDs.compactMap { id -> VaultEntry? in
            guard let data = try? readEntry(id: id) else {
                return nil
            }
            return VaultEntry(id: id, name: data.name, shortcut: data.shortcut)
        }
        return Self.sorted(entries)
    }

    /// By name, case-insensitively, with the id breaking ties so the list
    /// order is stable across unlocks.
    private static func sorted(_ entries: [VaultEntry]) -> [VaultEntry] {
        entries.sorted { first, second in
            let left = first.name.lowercased()
            let right = second.name.lowercased()
            return left == right ? first.id < second.id : left < right
        }
    }

    private func makeDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                // Nothing in here is readable while the device is locked. The
                // rest of Documents settles for the weaker default; a folder
                // of passwords should not.
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
    }
}
