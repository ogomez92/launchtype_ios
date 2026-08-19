import Foundation
import Testing
@testable import Launchtype

/// The vault's key derivation, checked against the published vectors rather
/// than against itself: an Argon2id that is subtly wrong would still round
/// trip perfectly here and open nothing that came from the desktop app.
struct Argon2idTests {
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return byte < 0x10 ? "0" + digits : digits
        }
        .joined()
    }

    /// RFC 9106, section 5.3 — the Argon2id test vector, secret and
    /// associated data included.
    @Test func matchesTheRFC9106TestVector() throws {
        let tag = try #require(Argon2id.hash(
            password: [UInt8](repeating: 0x01, count: 32),
            salt: [UInt8](repeating: 0x02, count: 16),
            parameters: Argon2id.Parameters(memoryKiB: 32, iterations: 3, parallelism: 4),
            length: 32,
            secret: [UInt8](repeating: 0x03, count: 8),
            associatedData: [UInt8](repeating: 0x04, count: 12)
        ))
        #expect(hex(tag) == "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
    }

    /// RFC 7693 appendix A: BLAKE2b-512 of "abc". Argon2 is built out of this
    /// hash, so a wrong one would fail every vector above in the same way.
    @Test func blake2bMatchesItsOwnVector() {
        let digest = Blake2b.hash(digestLength: 64, Array("abc".utf8))
        #expect(hex(digest) == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
            + "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
    }

    /// The empty-input vector, which catches an off-by-one in the block
    /// padding that "abc" is too short to expose.
    @Test func blake2bHashesEmptyInput() {
        let digest = Blake2b.hash(digestLength: 64, [])
        #expect(hex(digest) == "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419"
            + "d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce")
    }

    /// More than one block of input, to prove the counter and the last-block
    /// flag are handled where it matters — 300 bytes of "a", which is two full
    /// blocks and a part.
    @Test func blake2bHashesMoreThanOneBlock() {
        let digest = Blake2b.hash(digestLength: 64, [UInt8](repeating: 0x61, count: 300))
        #expect(hex(digest) == "a2ff3040eda405b929c2fc2fd93e8add6ac3bb5369b679bae170ac6956863ca0"
            + "06285f132a868000fc3fae5bc696e5d17fe3fddfb4a342876c40451184742986")

        // Feeding the same bytes in three pieces must give the same answer:
        // Argon2 always builds its inputs out of several updates.
        var hasher = Blake2b(digestLength: 64)
        hasher.update([UInt8](repeating: 0x61, count: 128))
        hasher.update([UInt8](repeating: 0x61, count: 1))
        hasher.update([UInt8](repeating: 0x61, count: 171))
        #expect(hex(hasher.finalize()) == hex(digest))
    }

    @Test func costParametersArgonDoesNotDefineAreRefused() {
        // Less memory than the lane count needs.
        #expect(Argon2id.hash(
            password: Array("x".utf8),
            salt: [UInt8](repeating: 0, count: 16),
            parameters: Argon2id.Parameters(memoryKiB: 8, iterations: 1, parallelism: 4),
            length: 32
        ) == nil)
        // No passes at all.
        #expect(Argon2id.hash(
            password: Array("x".utf8),
            salt: [UInt8](repeating: 0, count: 16),
            parameters: Argon2id.Parameters(memoryKiB: 64, iterations: 0, parallelism: 1),
            length: 32
        ) == nil)
    }

    /// Every other test here runs at a throwaway cost, so this is the only one
    /// that proves the cost the app actually ships with is accepted and comes
    /// back in a reasonable time. It allocates 256 MiB, which is the point.
    ///
    /// Disabled by default because a debug build spends about twenty seconds
    /// on it — the same function takes well under a second when it is
    /// optimized, which is what ships. Run it against a release build:
    ///
    ///     xcodebuild test -scheme Launchtype -configuration Release \
    ///         -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    ///         -only-testing:LaunchtypeTests/Argon2idTests/theShippedCostWorks
    @Test(.disabled("slow in a debug build; the shipped Argon2 cost is the point"))
    func theShippedCostWorks() throws {
        let started = ContinuousClock.now
        let tag = try #require(Argon2id.hash(
            password: Array("correct horse battery".utf8),
            salt: [UInt8](repeating: 0x07, count: 16),
            parameters: .strong,
            length: 32
        ))
        #expect(tag.count == 32)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
