import Foundation
import Testing
@testable import Launchtype

/// The vault, exercised through its own API. Every test runs at a throwaway
/// Argon2 cost — the shipped one takes about a second per unlock, and the
/// suite would spend minutes stretching passwords.
@MainActor
struct VaultSessionTests {
    private static let password = "correct horse battery"

    /// A temp folder that the caller deletes, and a session pointed at it.
    private func makeVault() throws -> (session: VaultSession, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VaultTest-\(UUID().uuidString)")
        return (VaultSession(directory: directory, lockAfterMinutes: 5, kdf: .weak), directory)
    }

    private func openVault() async throws -> (session: VaultSession, directory: URL) {
        let made = try makeVault()
        try await made.session.create(password: Self.password)
        return made
    }

    @Test func aMissingFolderReadsAsAVaultThatHasNotBeenSetUp() async throws {
        let (session, directory) = try makeVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(session.isNew)
        #expect(!session.isUnlocked)
        #expect(session.orphanCount == 0)

        try await session.create(password: Self.password)
        #expect(!session.isNew)
        #expect(session.isUnlocked)
    }

    @Test func entriesRoundTripThroughALockAndAFreshUnlock() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        try session.save(id: nil, name: "bank", shortcut: "", secret: "1234-5678")

        session.lock()
        #expect(session.entries.isEmpty, "locking drops the entry list")
        #expect(throws: VaultError.locked) { try session.secret(id: id) }

        try await session.unlock(password: Self.password)
        #expect(session.entries.map(\.name) == ["bank", "github"], "sorted by name")
        #expect(try session.secret(id: id) == "hunter2")
        #expect(session.entries[1].shortcut == "gh")
    }

    @Test func theWrongPasswordIsRejectedAndChangesNothing() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        session.lock()

        await #expect(throws: VaultError.wrongPassword) {
            try await session.unlock(password: "not it at all")
        }
        #expect(!session.isUnlocked)
        try await session.unlock(password: Self.password)
        #expect(session.entries.count == 1)
    }

    @Test func nothingReadableIsLeftOnDisk() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")

        let raw = try Data(contentsOf: directory.appending(path: "\(id).enc"))
        #expect(raw.prefix(4) == Data("LTV1".utf8))
        for plaintext in ["github", "gh", "hunter2"] {
            #expect(
                raw.range(of: Data(plaintext.utf8)) == nil,
                "\(plaintext) is readable in the entry file"
            )
        }
        // The file name gives nothing away either.
        #expect(UUID(uuidString: id) != nil)
    }

    @Test func aTamperedEntryIsRefusedRatherThanTrusted() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        let url = directory.appending(path: "\(id).enc")

        var raw = try Data(contentsOf: url)
        raw[raw.count - 1] ^= 0x01
        try raw.write(to: url)
        #expect(throws: VaultError.damaged) { try session.secret(id: id) }

        // ...and so is an entry file moved onto another entry's name: the id
        // is authenticated alongside the ciphertext.
        let other = try session.save(id: nil, name: "bank", shortcut: "", secret: "1234")
        let sealed = try Data(contentsOf: directory.appending(path: "\(other).enc"))
        try sealed.write(to: url)
        #expect(throws: VaultError.damaged) { try session.secret(id: id) }
    }

    @Test func savingOverAnEntryReplacesItInsteadOfAddingASecond() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        let same = try session.save(id: id, name: "github work", shortcut: "gh", secret: "hunter3")

        #expect(same == id)
        #expect(session.entries.count == 1)
        #expect(session.entries[0].name == "github work")
        #expect(try session.secret(id: id) == "hunter3")
    }

    @Test func editingReadsBackEverythingTheSheetNeeds() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(
            id: nil,
            name: "  recovery codes  ",
            shortcut: " RC ",
            secret: "one\ntwo\nthree"
        )

        let draft = try session.draft(id: id)
        #expect(draft.id == id)
        #expect(draft.name == "recovery codes", "the name is trimmed on the way in")
        #expect(draft.shortcut == "rc", "shortcuts are lowercased, like every other mode")
        #expect(draft.secret == "one\ntwo\nthree", "a multi-line secret survives intact")
    }

    @Test func deletingTakesTheFileWithIt() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        let url = directory.appending(path: "\(id).enc")

        try session.delete(id: id)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
        #expect(session.entries.isEmpty)
        #expect(throws: VaultError.noSuchEntry) { try session.delete(id: id) }
    }

    @Test func changingTheMasterPasswordLeavesTheEntriesAlone() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        let before = try Data(contentsOf: directory.appending(path: "\(id).enc"))

        await #expect(throws: VaultError.wrongPassword) {
            try await session.changePassword(current: "wrong", new: "a new long password")
        }
        try await session.changePassword(current: Self.password, new: "a new long password")

        let after = try Data(contentsOf: directory.appending(path: "\(id).enc"))
        #expect(before == after, "entry files are not rewritten")

        session.lock()
        await #expect(throws: VaultError.wrongPassword) {
            try await session.unlock(password: Self.password)
        }
        try await session.unlock(password: "a new long password")
        #expect(try session.secret(id: id) == "hunter2")
    }

    /// A second create would write a `vault.meta` holding a different vault
    /// key, and every entry written under the first one would stop opening.
    @Test func aVaultIsNeverCreatedOnTopOfAnExistingOne() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")

        await #expect(throws: VaultError.alreadyExists) {
            try await session.create(password: "a different password")
        }
        session.lock()
        try await session.unlock(password: Self.password)
        #expect(try session.secret(id: id) == "hunter2")
    }

    @Test func shortMasterPasswordsAreRefused() async throws {
        let (session, directory) = try makeVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: VaultError.passwordTooShort) {
            try await session.create(password: "short")
        }
        #expect(session.isNew)

        try await session.create(password: Self.password)
        await #expect(throws: VaultError.passwordTooShort) {
            try await session.changePassword(current: Self.password, new: "tiny")
        }
    }

    @Test func theVaultLocksItselfOnceTheIdleTimeHasPassed() async throws {
        let (session, directory) = try makeVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await session.create(password: Self.password, now: start)
        try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")

        #expect(!session.expire(start.addingTimeInterval(4 * 60)))
        #expect(session.isUnlocked)

        // Using it pushes the deadline out.
        session.touch(start.addingTimeInterval(4 * 60))
        #expect(!session.expire(start.addingTimeInterval(8 * 60)))

        #expect(session.expire(start.addingTimeInterval(10 * 60)))
        #expect(!session.isUnlocked)
        #expect(session.entries.isEmpty)
        #expect(!session.expire(start.addingTimeInterval(3600)), "already locked")
    }

    /// A zero timeout means "lock after each copy", which the UI does itself.
    /// The idle sweep must still close an abandoned vault rather than reading
    /// zero as "never".
    @Test func aZeroTimeoutStillExpiresAfterAMinute() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VaultTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = VaultSession(directory: directory, lockAfterMinutes: 0, kdf: .weak)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await session.create(password: Self.password, now: start)

        #expect(session.locksOnUse)
        #expect(!session.expire(start.addingTimeInterval(30)))
        #expect(session.expire(start.addingTimeInterval(61)))
    }

    @Test func entryFilesWithoutAKeyFileAreCountedRatherThanStrandedSilently() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        try FileManager.default.removeItem(at: directory.appending(path: "vault.meta"))

        let fresh = VaultSession(directory: directory, lockAfterMinutes: 5, kdf: .weak)
        #expect(fresh.isNew)
        #expect(fresh.orphanCount == 1)
    }

    @Test func oneDamagedEntryDoesNotTakeTheOthersDown() async throws {
        let (session, directory) = try await openVault()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")
        try session.save(id: nil, name: "bank", shortcut: "", secret: "1234")
        try Data("LTV1 not a vault file at all, but long enough to look like one".utf8)
            .write(to: directory.appending(path: "\(broken).enc"))

        session.lock()
        try await session.unlock(password: Self.password)
        #expect(session.entries.count == 1)
        #expect(session.entries[0].name == "bank")
    }
}
