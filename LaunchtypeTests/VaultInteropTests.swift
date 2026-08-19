import Foundation
import Testing
@testable import Launchtype

/// The point of the whole vault: a folder written by the desktop app opens
/// here with the same master password.
///
/// The fixture below is a real vault produced by `launchtype-core`'s own
/// `VaultSession` (at its test-only Argon2 cost, so the suite stays fast),
/// base64 into this file rather than added as a bundle resource so that
/// nothing about the test target's packaging can quietly stop it running.
/// If the format ever drifts on either side, this is what fails.
@MainActor
struct VaultInteropTests {
    private static let password = "correct horse battery"

    private static let meta = """
        ewogICJ2ZXJzaW9uIjogMSwKICAia2RmIjogImFyZ29uMmlkIiwKICAibV9jb3N0IjogOCwKICAidF9jb3N0Ijog\
        MSwKICAicF9jb3N0IjogMSwKICAic2FsdCI6ICJ5aXBXK1c2R3Q1RHV6NmpMakNZSWVRPT0iLAogICJ3cmFwcGVk\
        X2tleSI6ICIvaFU4UW1CNFBKNUFOSG81eUI0cVJUOWNuT1Y3V3MxT2pPeHVuUUkyOUtVajZZNk5tdlBlWndnNGxk\
        VDF2WnAzSkxNa0sxSk4wSzhQc3k1SyIKfQ==
        """

    /// id → file contents, as the desktop app wrote them.
    private static let entries: [(id: String, contents: String)] = [
        (
            "2feb3621-f822-4549-bf86-7b06924885e1",
            """
            TFRWMdy0oqU5BUb7vbydgIIWfh/P2aA+0sYvbVbYMXZHnxwdoVJv598hsikuj7YRE4/RhCsvx05JkFON/SqT\
            U/mOtAeJIRmPzWdhX3ygosH0nxWZ
            """
        ),
        (
            "0385904c-3225-4dcd-8abc-f5be54ad81a1",
            """
            TFRWMaCFDunKjQoNl6QzP5/KOT/ZK8dbwUji8VFOXnNJJtAzDrPdRCksMvcxnBFd9y2j7E7uz3viHaMBlm9R\
            wPj7CAVip563sRRCvPyWWMOY7VoK8Z8iWoySvn0diXI=
            """
        ),
        (
            "f8e26416-1ebe-494c-81c0-1bb09fc9620d",
            """
            TFRWMWqpNwT9Ra/Ntx/07Ipg1ryF7j3aPJwLyc5j+nYGDEPpGqoRYh4a950fUY2WTtbE3gAX+Y56zA+hfJ9+\
            hyfRmMcRBbia7L2t3sXwhEEPvHikXTHVHLpjBPeAVUMmhLp7
            """
        ),
    ]

    /// Write the desktop vault out to a temp folder, exactly as copying the
    /// folder off a Windows machine would.
    private func desktopVault() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DesktopVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(Data(base64Encoded: Self.meta, options: .ignoreUnknownCharacters))
            .write(to: directory.appending(path: "vault.meta"))
        for entry in Self.entries {
            try #require(Data(base64Encoded: entry.contents, options: .ignoreUnknownCharacters))
                .write(to: directory.appending(path: "\(entry.id).enc"))
        }
        return directory
    }

    @Test func aVaultFromTheDesktopAppOpensWithTheSamePassword() async throws {
        let directory = try desktopVault()
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = VaultSession(directory: directory, lockAfterMinutes: 5)
        #expect(!session.isNew, "the desktop's vault.meta is what makes it not new")

        try await session.unlock(password: Self.password)
        #expect(session.entries.map(\.name) == ["bank", "github", "Ñandú café"])
        #expect(session.entries.map(\.shortcut) == ["", "gh", "ñ"])

        #expect(try session.secret(id: Self.entries[0].id) == "hunter2")
        #expect(
            try session.secret(id: Self.entries[1].id) == "1234-5678\nsecond line",
            "multi-line secrets survive the crossing"
        )
        #expect(
            try session.secret(id: Self.entries[2].id) == "contraseña ✅",
            "and so does anything outside ASCII"
        )
    }

    @Test func theWrongPasswordDoesNotOpenTheDesktopVault() async throws {
        let directory = try desktopVault()
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = VaultSession(directory: directory, lockAfterMinutes: 5)
        await #expect(throws: VaultError.wrongPassword) {
            try await session.unlock(password: "correct horse batteryy")
        }
        #expect(!session.isUnlocked)
    }

    /// Editing an imported entry has to keep it openable by the app it came
    /// from, which means resealing it with the same vault key rather than a
    /// new one.
    @Test func anImportedVaultCanBeAddedToAndEdited() async throws {
        let directory = try desktopVault()
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = VaultSession(directory: directory, lockAfterMinutes: 5)
        try await session.unlock(password: Self.password)
        let added = try session.save(id: nil, name: "phone pin", shortcut: "pin", secret: "4821")
        try session.save(
            id: Self.entries[0].id,
            name: "github",
            shortcut: "gh",
            secret: "hunter3"
        )

        session.lock()
        try await session.unlock(password: Self.password)
        #expect(session.entries.count == 4)
        #expect(try session.secret(id: added) == "4821")
        #expect(try session.secret(id: Self.entries[0].id) == "hunter3")
        #expect(
            try session.secret(id: Self.entries[2].id) == "contraseña ✅",
            "the entries that were not touched still open"
        )
    }

    /// What a vault written here looks like on disk — the shape the desktop
    /// app parses. A vault that only this app can read would pass every other
    /// test in the suite.
    @Test func aVaultWrittenHereHasTheFormatTheDesktopAppReads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VaultFormat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = VaultSession(directory: directory, lockAfterMinutes: 5, kdf: .weak)
        try await session.create(password: Self.password)
        let id = try session.save(id: nil, name: "github", shortcut: "gh", secret: "hunter2")

        let metaData = try Data(contentsOf: directory.appending(path: "vault.meta"))
        let json = try #require(
            JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        )
        #expect(json["version"] as? Int == 1)
        #expect(json["kdf"] as? String == "argon2id")
        #expect(json["m_cost"] as? Int == 8)
        #expect(json["t_cost"] as? Int == 1)
        #expect(json["p_cost"] as? Int == 1)
        let saltText = try #require(json["salt"] as? String)
        let salt = try #require(Data(base64Encoded: saltText))
        #expect(salt.count == 16)
        let wrappedText = try #require(json["wrapped_key"] as? String)
        let wrapped = try #require(Data(base64Encoded: wrappedText))
        // 12-byte nonce, 32-byte key, 16-byte tag.
        #expect(wrapped.count == 60)

        let entry = try Data(contentsOf: directory.appending(path: "\(id).enc"))
        #expect(entry.prefix(4) == Data("LTV1".utf8))
        #expect(entry.count > 4 + 12 + 16)
    }
}
