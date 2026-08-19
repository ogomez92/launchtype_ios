import Foundation

/// BLAKE2b (RFC 7693), unkeyed, with a variable digest length.
///
/// CryptoKit has no BLAKE2, and Argon2 is defined entirely in terms of it, so
/// the vault has to bring its own. The desktop app derives its master key with
/// the same hash; every byte here exists to make a vault written on Windows
/// open on the phone, so this is a straight implementation of the spec with no
/// room for interpretation.
struct Blake2b {
    /// The largest digest BLAKE2b produces. Argon2's `H'` chains hashes of
    /// this size when it needs more.
    static let maxDigestLength = 64

    private static let blockLength = 128

    /// The SHA-512 initialization vector, which BLAKE2b reuses.
    private static let iv: [UInt64] = [
        0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b,
        0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
        0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f,
        0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179,
    ]

    /// The message-word permutation, one row per round. Rounds 10 and 11 reuse
    /// rows 0 and 1, which is why there are ten here and twelve rounds below.
    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    ]

    private var h: [UInt64]
    private var buffer = [UInt8](repeating: 0, count: Blake2b.blockLength)
    private var bufferCount = 0
    /// Bytes absorbed so far, the `t` counter of the spec. A vault never feeds
    /// it more than a few kilobytes, so the high half stays zero.
    private var counter: UInt64 = 0
    private let digestLength: Int

    /// A hasher producing `digestLength` bytes (1...64).
    init(digestLength: Int) {
        precondition((1...Blake2b.maxDigestLength).contains(digestLength))
        self.digestLength = digestLength
        h = Blake2b.iv
        // Parameter block: digest length, no key, fanout 1, depth 1.
        h[0] ^= 0x0101_0000 ^ UInt64(digestLength)
    }

    mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { update($0) }
    }

    mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) {
        var offset = 0
        while offset < bytes.count {
            if bufferCount == Blake2b.blockLength {
                // Never compress the final block here: finalization has to
                // flag it, so a full buffer waits until more input arrives.
                counter &+= UInt64(Blake2b.blockLength)
                compress(last: false)
                bufferCount = 0
            }
            let take = min(Blake2b.blockLength - bufferCount, bytes.count - offset)
            for index in 0..<take {
                buffer[bufferCount + index] = bytes[offset + index]
            }
            bufferCount += take
            offset += take
        }
    }

    /// The digest. Consumes the hasher: the state is wiped afterwards, since
    /// what passed through it is password material.
    mutating func finalize() -> [UInt8] {
        counter &+= UInt64(bufferCount)
        for index in bufferCount..<Blake2b.blockLength {
            buffer[index] = 0
        }
        compress(last: true)

        var digest = [UInt8](repeating: 0, count: digestLength)
        for index in 0..<digestLength {
            digest[index] = UInt8(truncatingIfNeeded: h[index / 8] >> (8 * UInt64(index % 8)))
        }
        Zeroize.wipe(&h)
        Zeroize.wipe(&buffer)
        return digest
    }

    private mutating func compress(last: Bool) {
        var m = [UInt64](repeating: 0, count: 16)
        for word in 0..<16 {
            var value: UInt64 = 0
            for byte in 0..<8 {
                value |= UInt64(buffer[word * 8 + byte]) << (8 * UInt64(byte))
            }
            m[word] = value
        }

        var v = [UInt64](repeating: 0, count: 16)
        for index in 0..<8 {
            v[index] = h[index]
            v[index + 8] = Blake2b.iv[index]
        }
        v[12] ^= counter
        // v[13] ^= high half of the counter, which is always zero here.
        if last {
            v[14] = ~v[14]
        }

        for round in 0..<12 {
            let s = Blake2b.sigma[round % 10]
            Blake2b.mix(&v, 0, 4, 8, 12, m[s[0]], m[s[1]])
            Blake2b.mix(&v, 1, 5, 9, 13, m[s[2]], m[s[3]])
            Blake2b.mix(&v, 2, 6, 10, 14, m[s[4]], m[s[5]])
            Blake2b.mix(&v, 3, 7, 11, 15, m[s[6]], m[s[7]])
            Blake2b.mix(&v, 0, 5, 10, 15, m[s[8]], m[s[9]])
            Blake2b.mix(&v, 1, 6, 11, 12, m[s[10]], m[s[11]])
            Blake2b.mix(&v, 2, 7, 8, 13, m[s[12]], m[s[13]])
            Blake2b.mix(&v, 3, 4, 9, 14, m[s[14]], m[s[15]])
        }

        for index in 0..<8 {
            h[index] ^= v[index] ^ v[index + 8]
        }
        Zeroize.wipe(&m)
        Zeroize.wipe(&v)
    }

    /// The `G` mixing function of RFC 7693.
    @inline(__always)
    private static func mix(
        _ v: inout [UInt64],
        _ a: Int, _ b: Int, _ c: Int, _ d: Int,
        _ x: UInt64, _ y: UInt64
    ) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = (v[d] ^ v[a]).rotatedRight(32)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(24)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = (v[d] ^ v[a]).rotatedRight(16)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(63)
    }

    /// One-shot hash of the concatenation of `parts` — how Argon2 always uses
    /// it, and shorter than three lines of hasher juggling at each call site.
    static func hash(digestLength: Int, _ parts: [UInt8]...) -> [UInt8] {
        var hasher = Blake2b(digestLength: digestLength)
        for part in parts {
            hasher.update(part)
        }
        return hasher.finalize()
    }
}

extension UInt64 {
    @inline(__always)
    func rotatedRight(_ places: UInt64) -> UInt64 {
        (self >> places) | (self << (64 - places))
    }
}
