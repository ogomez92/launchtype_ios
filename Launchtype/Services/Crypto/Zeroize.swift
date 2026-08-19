import Foundation

/// Overwriting buffers that held key material.
///
/// Swift gives no guarantee that a `String` or a copy-on-write `Array` leaves
/// only one copy behind, so this is a best effort rather than the desktop
/// app's `Zeroizing`: it covers the long-lived buffers — the Argon2 memory
/// block, hash state, derived keys — where a stray copy would otherwise sit in
/// the heap for the life of the process. `memset_s` is used rather than a
/// plain loop because the optimizer is entitled to delete a write nobody
/// reads back, which is exactly what this is.
enum Zeroize {
    static func wipe<T: FixedWidthInteger>(_ buffer: inout [T]) {
        let byteCount = buffer.count * MemoryLayout<T>.stride
        guard byteCount > 0 else {
            return
        }
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            memset_s(base, byteCount, 0, byteCount)
        }
    }

    static func wipe(_ data: inout Data) {
        guard !data.isEmpty else {
            return
        }
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            memset_s(base, raw.count, 0, raw.count)
        }
    }

    static func wipe<T: FixedWidthInteger>(_ pointer: UnsafeMutablePointer<T>, count: Int) {
        let byteCount = count * MemoryLayout<T>.stride
        guard byteCount > 0 else {
            return
        }
        memset_s(UnsafeMutableRawPointer(pointer), byteCount, 0, byteCount)
    }
}
