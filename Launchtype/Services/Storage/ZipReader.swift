import Compression
import Foundation

/// A minimal zip reader for backup import: parses the central directory and
/// extracts stored or deflated entries — which covers zips made by this app,
/// Finder, and desktop archivers. Encrypted and zip64 archives are rejected;
/// a Launchtype backup is never either.
struct ZipReader {
    struct Entry {
        let path: String
        let isDirectory: Bool
        let uncompressedSize: Int
        fileprivate let method: UInt16
        fileprivate let compressedSize: Int
        fileprivate let localHeaderOffset: Int
    }

    enum ZipError: Error, LocalizedError {
        case notAZip
        case unsupported
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notAZip: "The file is not a zip archive."
            case .unsupported: "The archive uses an unsupported zip feature."
            case .corrupt: "The archive is damaged."
            }
        }
    }

    let entries: [Entry]
    private let data: Data

    private static let endOfDirectorySignature: UInt32 = 0x0605_4B50
    private static let directoryEntrySignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    /// A backup is a handful of small files; anything past these caps is not
    /// one of ours.
    private static let maxEntries = 10_000
    private static let maxTotalUncompressed = 256 * 1024 * 1024

    init(data: Data) throws {
        self.data = data
        // The end-of-central-directory record sits at the very end, before an
        // optional comment of up to 64 KB — scan backwards for its signature.
        guard data.count >= 22 else {
            throw ZipError.notAZip
        }
        let scanFloor = max(0, data.count - 22 - 65_535)
        var recordOffset: Int?
        var offset = data.count - 22
        while offset >= scanFloor {
            if Self.readUInt32(data, at: offset) == Self.endOfDirectorySignature {
                recordOffset = offset
                break
            }
            offset -= 1
        }
        guard let recordOffset else {
            throw ZipError.notAZip
        }
        let entryCount = Int(Self.readUInt16(data, at: recordOffset + 10))
        let directoryOffset = Int(Self.readUInt32(data, at: recordOffset + 16))
        guard entryCount != 0xFFFF, directoryOffset != 0xFFFF_FFFF else {
            throw ZipError.unsupported // zip64
        }
        guard entryCount <= Self.maxEntries, directoryOffset < data.count else {
            throw ZipError.corrupt
        }

        var parsed: [Entry] = []
        var cursor = directoryOffset
        var totalUncompressed = 0
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  Self.readUInt32(data, at: cursor) == Self.directoryEntrySignature else {
                throw ZipError.corrupt
            }
            let flags = Self.readUInt16(data, at: cursor + 8)
            guard flags & 0x1 == 0 else {
                throw ZipError.unsupported // encrypted
            }
            let method = Self.readUInt16(data, at: cursor + 10)
            guard method == 0 || method == 8 else {
                throw ZipError.unsupported
            }
            let compressedSize = Int(Self.readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(Self.readUInt32(data, at: cursor + 24))
            let nameLength = Int(Self.readUInt16(data, at: cursor + 28))
            let extraLength = Int(Self.readUInt16(data, at: cursor + 30))
            let commentLength = Int(Self.readUInt16(data, at: cursor + 32))
            let localHeaderOffset = Int(Self.readUInt32(data, at: cursor + 42))
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF,
                  localHeaderOffset != 0xFFFF_FFFF else {
                throw ZipError.unsupported // zip64
            }
            guard cursor + 46 + nameLength <= data.count else {
                throw ZipError.corrupt
            }
            totalUncompressed += uncompressedSize
            guard totalUncompressed <= Self.maxTotalUncompressed else {
                throw ZipError.unsupported
            }
            let nameData = Self.subdata(data, from: cursor + 46, count: nameLength)
            let path = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            parsed.append(Entry(
                path: path,
                isDirectory: path.hasSuffix("/"),
                uncompressedSize: uncompressedSize,
                method: method,
                compressedSize: compressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        entries = parsed
    }

    func contents(of entry: Entry) throws -> Data {
        let headerOffset = entry.localHeaderOffset
        guard headerOffset + 30 <= data.count,
              Self.readUInt32(data, at: headerOffset) == Self.localHeaderSignature else {
            throw ZipError.corrupt
        }
        // Sizes come from the central directory — the local header's copies
        // may be zeroed when the writer streamed with data descriptors.
        let nameLength = Int(Self.readUInt16(data, at: headerOffset + 26))
        let extraLength = Int(Self.readUInt16(data, at: headerOffset + 28))
        let start = headerOffset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else {
            throw ZipError.corrupt
        }
        let compressed = Self.subdata(data, from: start, count: entry.compressedSize)
        if entry.method == 0 {
            guard compressed.count == entry.uncompressedSize else {
                throw ZipError.corrupt
            }
            return compressed
        }
        return try Self.inflate(compressed, uncompressedSize: entry.uncompressedSize)
    }

    /// Raw-deflate decompression — Compression's `COMPRESSION_ZLIB` is the
    /// headerless deflate stream zip entries contain.
    private static func inflate(_ input: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else {
            return Data()
        }
        guard !input.isEmpty else {
            throw ZipError.corrupt
        }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { rawOutput in
            input.withUnsafeBytes { rawInput in
                guard let outputBase = rawOutput.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = rawInput.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    outputBase, uncompressedSize,
                    inputBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else {
            throw ZipError.corrupt
        }
        return output
    }

    // Offsets are logical (0-based); index math goes through startIndex so a
    // Data slice would still read correctly.

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let index = data.startIndex + offset
        return UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(readUInt16(data, at: offset)) | (UInt32(readUInt16(data, at: offset + 2)) << 16)
    }

    private static func subdata(_ data: Data, from offset: Int, count: Int) -> Data {
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }
}
