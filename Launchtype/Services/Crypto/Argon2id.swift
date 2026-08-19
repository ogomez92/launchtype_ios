import Foundation

/// Argon2id (RFC 9106) — the memory-hard function that turns the vault's
/// master password into a key.
///
/// This is the one piece of the vault that has no system implementation to
/// lean on: CryptoKit stops at PBKDF2-era primitives, and the desktop app
/// stretches its password with Argon2id, so opening a vault copied from
/// Windows means computing the same function here. It is a direct port of the
/// reference implementation, sequential across lanes (the sync-point structure
/// makes the result identical however the lanes are scheduled).
///
/// Cost is deliberately high — 256 MiB and four passes for a vault made by
/// either app — because the memory is what makes guessing the master password
/// expensive on the hardware someone would bring to it. That also means one
/// call allocates 256 MiB and runs for on the order of a second, so it belongs
/// off the main actor; every function here is a pure `nonisolated static`.
enum Argon2id {
    /// The cost parameters, which every vault records so that raising them
    /// later never orphans an existing vault.
    struct Parameters: Equatable, Sendable {
        /// Memory cost in KiB.
        var memoryKiB: UInt32
        /// Number of passes over that memory.
        var iterations: UInt32
        /// Number of lanes.
        var parallelism: UInt32

        /// What both apps write: 256 MiB over 4 passes, an order of magnitude
        /// past OWASP's floor for Argon2id.
        static let strong = Parameters(memoryKiB: 256 * 1024, iterations: 4, parallelism: 1)

        /// The cheapest parameters Argon2 accepts. Test use only — a vault
        /// made with these is not protected in any meaningful sense.
        static let weak = Parameters(memoryKiB: 8, iterations: 1, parallelism: 1)
    }

    private static let version: UInt32 = 0x13
    /// Argon2id. Argon2d is 0 and Argon2i is 1; the type is hashed into `H0`,
    /// so this constant is part of the format.
    private static let type: UInt32 = 2
    private static let syncPoints = 4
    private static let wordsPerBlock = 128
    private static let blockBytes = 1024
    private static let addressesPerBlock = 128

    /// Derive `length` bytes from `password` and `salt`.
    ///
    /// `secret` and `associatedData` are the two optional inputs of RFC 9106.
    /// Neither app uses them — a vault passes only a password and a salt — but
    /// they are part of the hashed header either way, and supporting them is
    /// what lets the official test vectors run against this code.
    ///
    /// Returns nil only for parameters Argon2 does not define — too little
    /// memory for the lane count, no passes, a tag shorter than 4 bytes —
    /// which for the vault means a `vault.meta` that has been damaged or
    /// hand-edited.
    nonisolated static func hash(
        password: [UInt8],
        salt: [UInt8],
        parameters: Parameters,
        length: Int,
        secret: [UInt8] = [],
        associatedData: [UInt8] = []
    ) -> [UInt8]? {
        let lanes = Int(parameters.parallelism)
        let passes = Int(parameters.iterations)
        guard lanes >= 1, passes >= 1, length >= 4, salt.count >= 8 else {
            return nil
        }
        guard parameters.memoryKiB >= 8 * parameters.parallelism else {
            return nil
        }

        // Memory is rounded down to a whole number of segments per lane.
        let memoryBlocks = (Int(parameters.memoryKiB) / (syncPoints * lanes)) * (syncPoints * lanes)
        let laneLength = memoryBlocks / lanes
        let segmentLength = laneLength / syncPoints

        var h0 = initialHash(
            password: password,
            salt: salt,
            parameters: parameters,
            length: length,
            secret: secret,
            associatedData: associatedData
        )
        defer { Zeroize.wipe(&h0) }

        let memory = UnsafeMutablePointer<UInt64>.allocate(capacity: memoryBlocks * wordsPerBlock)
        memory.initialize(repeating: 0, count: memoryBlocks * wordsPerBlock)
        defer {
            // The memory block is a function of the password; it is the
            // largest thing in this process that must not outlive the call.
            Zeroize.wipe(memory, count: memoryBlocks * wordsPerBlock)
            memory.deallocate()
        }

        fillFirstBlocks(memory, h0: h0, lanes: lanes, laneLength: laneLength)
        fillMemory(
            memory,
            passes: passes,
            lanes: lanes,
            laneLength: laneLength,
            segmentLength: segmentLength,
            memoryBlocks: memoryBlocks
        )

        // The tag is the hash of the last block of every lane, XORed together.
        var final = [UInt8](repeating: 0, count: blockBytes)
        defer { Zeroize.wipe(&final) }
        var mixed = [UInt64](repeating: 0, count: wordsPerBlock)
        defer { Zeroize.wipe(&mixed) }
        for lane in 0..<lanes {
            let block = memory + (lane * laneLength + laneLength - 1) * wordsPerBlock
            for word in 0..<wordsPerBlock {
                mixed[word] ^= block[word]
            }
        }
        for word in 0..<wordsPerBlock {
            for byte in 0..<8 {
                final[word * 8 + byte] = UInt8(truncatingIfNeeded: mixed[word] >> (8 * UInt64(byte)))
            }
        }
        return variableLengthHash(length: length, input: final)
    }

    // MARK: - Initial state

    /// `H0`: everything the caller asked for, hashed into 64 bytes. Empty
    /// secret and associated data still contribute their zero lengths.
    private static func initialHash(
        password: [UInt8],
        salt: [UInt8],
        parameters: Parameters,
        length: Int,
        secret: [UInt8],
        associatedData: [UInt8]
    ) -> [UInt8] {
        var hasher = Blake2b(digestLength: Blake2b.maxDigestLength)
        hasher.update(littleEndian(parameters.parallelism))
        hasher.update(littleEndian(UInt32(length)))
        hasher.update(littleEndian(parameters.memoryKiB))
        hasher.update(littleEndian(parameters.iterations))
        hasher.update(littleEndian(version))
        hasher.update(littleEndian(type))
        hasher.update(littleEndian(UInt32(password.count)))
        hasher.update(password)
        hasher.update(littleEndian(UInt32(salt.count)))
        hasher.update(salt)
        hasher.update(littleEndian(UInt32(secret.count)))
        hasher.update(secret)
        hasher.update(littleEndian(UInt32(associatedData.count)))
        hasher.update(associatedData)
        return hasher.finalize()
    }

    /// The two blocks at the head of every lane, which the rest is built from.
    private static func fillFirstBlocks(
        _ memory: UnsafeMutablePointer<UInt64>,
        h0: [UInt8],
        lanes: Int,
        laneLength: Int
    ) {
        for lane in 0..<lanes {
            for column in 0..<2 {
                var input = h0
                input.append(contentsOf: littleEndian(UInt32(column)))
                input.append(contentsOf: littleEndian(UInt32(lane)))
                var block = variableLengthHash(length: blockBytes, input: input)
                defer { Zeroize.wipe(&block) }
                let destination = memory + (lane * laneLength + column) * wordsPerBlock
                for word in 0..<wordsPerBlock {
                    var value: UInt64 = 0
                    for byte in 0..<8 {
                        value |= UInt64(block[word * 8 + byte]) << (8 * UInt64(byte))
                    }
                    destination[word] = value
                }
            }
        }
    }

    // MARK: - Filling

    private static func fillMemory(
        _ memory: UnsafeMutablePointer<UInt64>,
        passes: Int,
        lanes: Int,
        laneLength: Int,
        segmentLength: Int,
        memoryBlocks: Int
    ) {
        // Scratch for the compression function, allocated once: the inner loop
        // runs millions of times and must not touch the allocator.
        let blockR = UnsafeMutablePointer<UInt64>.allocate(capacity: wordsPerBlock)
        let blockTmp = UnsafeMutablePointer<UInt64>.allocate(capacity: wordsPerBlock)
        let addresses = UnsafeMutablePointer<UInt64>.allocate(capacity: wordsPerBlock)
        let addressInput = UnsafeMutablePointer<UInt64>.allocate(capacity: wordsPerBlock)
        let zeroBlock = UnsafeMutablePointer<UInt64>.allocate(capacity: wordsPerBlock)
        for scratch in [blockR, blockTmp, addresses, addressInput, zeroBlock] {
            scratch.initialize(repeating: 0, count: wordsPerBlock)
        }
        defer {
            for scratch in [blockR, blockTmp, addresses, addressInput, zeroBlock] {
                Zeroize.wipe(scratch, count: wordsPerBlock)
                scratch.deallocate()
            }
        }

        for pass in 0..<passes {
            for slice in 0..<syncPoints {
                // Argon2id addresses its first half data-independently (the
                // Argon2i half) and everything after it data-dependently.
                let dataIndependent = pass == 0 && slice < syncPoints / 2
                for lane in 0..<lanes {
                    var startIndex = 0
                    if pass == 0 && slice == 0 {
                        // The first two blocks of a lane are already there.
                        startIndex = 2
                        if dataIndependent {
                            addressInput.update(repeating: 0, count: wordsPerBlock)
                            addressInput[0] = UInt64(pass)
                            addressInput[1] = UInt64(lane)
                            addressInput[2] = UInt64(slice)
                            addressInput[3] = UInt64(memoryBlocks)
                            addressInput[4] = UInt64(passes)
                            addressInput[5] = UInt64(type)
                            nextAddresses(
                                addresses: addresses,
                                input: addressInput,
                                zero: zeroBlock,
                                blockR: blockR,
                                blockTmp: blockTmp
                            )
                        }
                    } else if dataIndependent {
                        addressInput.update(repeating: 0, count: wordsPerBlock)
                        addressInput[0] = UInt64(pass)
                        addressInput[1] = UInt64(lane)
                        addressInput[2] = UInt64(slice)
                        addressInput[3] = UInt64(memoryBlocks)
                        addressInput[4] = UInt64(passes)
                        addressInput[5] = UInt64(type)
                    }

                    var currentOffset = lane * laneLength + slice * segmentLength + startIndex
                    var previousOffset = currentOffset % laneLength == 0
                        ? currentOffset + laneLength - 1
                        : currentOffset - 1

                    for index in startIndex..<segmentLength {
                        if currentOffset % laneLength == 1 {
                            previousOffset = currentOffset - 1
                        }

                        let pseudoRandom: UInt64
                        if dataIndependent {
                            if index % addressesPerBlock == 0 {
                                nextAddresses(
                                    addresses: addresses,
                                    input: addressInput,
                                    zero: zeroBlock,
                                    blockR: blockR,
                                    blockTmp: blockTmp
                                )
                            }
                            pseudoRandom = addresses[index % addressesPerBlock]
                        } else {
                            pseudoRandom = memory[previousOffset * wordsPerBlock]
                        }

                        // The first slice of the first pass has nothing in the
                        // other lanes to point at yet.
                        var referenceLane = Int(pseudoRandom >> 32) % lanes
                        if pass == 0 && slice == 0 {
                            referenceLane = lane
                        }
                        let referenceIndex = referencePosition(
                            pass: pass,
                            slice: slice,
                            index: index,
                            sameLane: referenceLane == lane,
                            random: UInt32(truncatingIfNeeded: pseudoRandom),
                            laneLength: laneLength,
                            segmentLength: segmentLength
                        )

                        let reference = memory + (referenceLane * laneLength + referenceIndex) * wordsPerBlock
                        let previous = memory + previousOffset * wordsPerBlock
                        let current = memory + currentOffset * wordsPerBlock
                        compress(
                            previous: previous,
                            reference: reference,
                            into: current,
                            // Later passes XOR over what is already there
                            // rather than overwriting it (version 0x13).
                            xoringExisting: pass != 0,
                            blockR: blockR,
                            blockTmp: blockTmp
                        )

                        currentOffset += 1
                        previousOffset += 1
                    }
                }
            }
        }
    }

    /// Generate the next block of data-independent reference positions.
    private static func nextAddresses(
        addresses: UnsafeMutablePointer<UInt64>,
        input: UnsafeMutablePointer<UInt64>,
        zero: UnsafePointer<UInt64>,
        blockR: UnsafeMutablePointer<UInt64>,
        blockTmp: UnsafeMutablePointer<UInt64>
    ) {
        input[6] &+= 1
        compress(
            previous: zero, reference: input, into: addresses,
            xoringExisting: false, blockR: blockR, blockTmp: blockTmp
        )
        compress(
            previous: zero, reference: addresses, into: addresses,
            xoringExisting: false, blockR: blockR, blockTmp: blockTmp
        )
    }

    /// Map a random 32-bit value onto a block this one is allowed to refer to.
    ///
    /// The rules are what stop a block referring to itself, to a block that
    /// does not exist yet, or to one another lane is writing this very moment.
    private static func referencePosition(
        pass: Int,
        slice: Int,
        index: Int,
        sameLane: Bool,
        random: UInt32,
        laneLength: Int,
        segmentLength: Int
    ) -> Int {
        let referenceAreaSize: Int
        if pass == 0 {
            if slice == 0 {
                referenceAreaSize = index - 1
            } else if sameLane {
                referenceAreaSize = slice * segmentLength + index - 1
            } else {
                referenceAreaSize = slice * segmentLength - (index == 0 ? 1 : 0)
            }
        } else if sameLane {
            referenceAreaSize = laneLength - segmentLength + index - 1
        } else {
            referenceAreaSize = laneLength - segmentLength - (index == 0 ? 1 : 0)
        }

        // Square the random value and take the high half, twice: the result is
        // biased towards recent blocks, which is what the spec calls for.
        var relative = UInt64(random)
        relative = (relative &* relative) >> 32
        relative = UInt64(referenceAreaSize) - 1 - ((UInt64(referenceAreaSize) &* relative) >> 32)

        var start = 0
        if pass != 0 {
            start = slice == syncPoints - 1 ? 0 : (slice + 1) * segmentLength
        }
        return (start + Int(relative)) % laneLength
    }

    // MARK: - The compression function

    /// `G`: mix `previous` and `reference` into `into`, either overwriting it
    /// or XORing over what is there.
    private static func compress(
        previous: UnsafePointer<UInt64>,
        reference: UnsafePointer<UInt64>,
        into destination: UnsafeMutablePointer<UInt64>,
        xoringExisting: Bool,
        blockR: UnsafeMutablePointer<UInt64>,
        blockTmp: UnsafeMutablePointer<UInt64>
    ) {
        for word in 0..<wordsPerBlock {
            let value = reference[word] ^ previous[word]
            blockR[word] = value
            blockTmp[word] = xoringExisting ? value ^ destination[word] : value
        }

        // BLAKE2's round function over the columns of the block, then over its
        // rows: the two together diffuse every word into every other.
        for i in 0..<8 {
            mixRound(blockR, base: 16 * i, stride: 2)
        }
        for i in 0..<8 {
            mixRound(blockR, base: 2 * i, stride: 16)
        }

        for word in 0..<wordsPerBlock {
            destination[word] = blockTmp[word] ^ blockR[word]
        }
    }

    /// One BLAKE2 round over sixteen words of a block. The two orders the
    /// block is walked in — columns and rows — differ only in `stride`: word
    /// `j` of the round is at `base + (j / 2) * stride + (j % 2)`.
    @inline(__always)
    private static func mixRound(_ block: UnsafeMutablePointer<UInt64>, base: Int, stride: Int) {
        let i0 = base, i1 = base + 1
        let i2 = base + stride, i3 = base + stride + 1
        let i4 = base + 2 * stride, i5 = base + 2 * stride + 1
        let i6 = base + 3 * stride, i7 = base + 3 * stride + 1
        let i8 = base + 4 * stride, i9 = base + 4 * stride + 1
        let i10 = base + 5 * stride, i11 = base + 5 * stride + 1
        let i12 = base + 6 * stride, i13 = base + 6 * stride + 1
        let i14 = base + 7 * stride, i15 = base + 7 * stride + 1

        var v0 = block[i0], v1 = block[i1], v2 = block[i2], v3 = block[i3]
        var v4 = block[i4], v5 = block[i5], v6 = block[i6], v7 = block[i7]
        var v8 = block[i8], v9 = block[i9], v10 = block[i10], v11 = block[i11]
        var v12 = block[i12], v13 = block[i13], v14 = block[i14], v15 = block[i15]

        quarterRound(&v0, &v4, &v8, &v12)
        quarterRound(&v1, &v5, &v9, &v13)
        quarterRound(&v2, &v6, &v10, &v14)
        quarterRound(&v3, &v7, &v11, &v15)
        quarterRound(&v0, &v5, &v10, &v15)
        quarterRound(&v1, &v6, &v11, &v12)
        quarterRound(&v2, &v7, &v8, &v13)
        quarterRound(&v3, &v4, &v9, &v14)

        block[i0] = v0; block[i1] = v1; block[i2] = v2; block[i3] = v3
        block[i4] = v4; block[i5] = v5; block[i6] = v6; block[i7] = v7
        block[i8] = v8; block[i9] = v9; block[i10] = v10; block[i11] = v11
        block[i12] = v12; block[i13] = v13; block[i14] = v14; block[i15] = v15
    }

    @inline(__always)
    private static func quarterRound(
        _ a: inout UInt64, _ b: inout UInt64, _ c: inout UInt64, _ d: inout UInt64
    ) {
        a = blaMka(a, b)
        d = (d ^ a).rotatedRight(32)
        c = blaMka(c, d)
        b = (b ^ c).rotatedRight(24)
        a = blaMka(a, b)
        d = (d ^ a).rotatedRight(16)
        c = blaMka(c, d)
        b = (b ^ c).rotatedRight(63)
    }

    /// Argon2's addition: BLAKE2's `a + b` with a multiplication of the low
    /// halves folded in, so that the round cannot be shortcut with cheap
    /// bitwise hardware.
    @inline(__always)
    private static func blaMka(_ x: UInt64, _ y: UInt64) -> UInt64 {
        let product = (x & 0xFFFF_FFFF) &* (y & 0xFFFF_FFFF)
        return x &+ y &+ (product &<< 1)
    }

    // MARK: - Variable-length hashing

    /// `H'`: BLAKE2b when 64 bytes are enough, and a chain of 64-byte hashes
    /// contributing 32 bytes each when they are not (which is how the 1024-byte
    /// blocks are produced).
    private static func variableLengthHash(length: Int, input: [UInt8]) -> [UInt8] {
        let prefix = littleEndian(UInt32(length))
        if length <= Blake2b.maxDigestLength {
            return Blake2b.hash(digestLength: length, prefix, input)
        }

        var output = [UInt8]()
        output.reserveCapacity(length)
        var block = Blake2b.hash(digestLength: Blake2b.maxDigestLength, prefix, input)
        defer { Zeroize.wipe(&block) }
        output.append(contentsOf: block[0..<32])
        var remaining = length - 32
        while remaining > Blake2b.maxDigestLength {
            block = Blake2b.hash(digestLength: Blake2b.maxDigestLength, block)
            output.append(contentsOf: block[0..<32])
            remaining -= 32
        }
        block = Blake2b.hash(digestLength: remaining, block)
        output.append(contentsOf: block)
        return output
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ]
    }
}
