import Foundation

/// Errors thrown while reading or writing 3DS formats.
public enum ThemeKitError: LocalizedError {
    case unexpectedEnd
    case invalidFormat(String)
    case tooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedEnd: return "The file ended unexpectedly. It may be truncated or damaged."
        case .invalidFormat(let s): return s
        case .tooLarge(let s): return s
        }
    }
}

/// Little-endian byte writer backed by a [UInt8] buffer.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init(capacity: Int = 0) { bytes.reserveCapacity(capacity) }

    public var count: Int { bytes.count }

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
    }
    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    public mutating func u32(_ v: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: v))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
    }
    public mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    public mutating func u32(_ v: Int) { u32(UInt32(truncatingIfNeeded: v)) }
    public mutating func i64(_ v: Int64) {
        u32(UInt32(truncatingIfNeeded: v))
        u32(UInt32(truncatingIfNeeded: v >> 32))
    }
    public mutating func f32(_ v: Float) { u32(v.bitPattern) }
    public mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
    public mutating func append(_ d: Data) { bytes.append(contentsOf: d) }
    public mutating func ascii(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }
    public mutating func zeros(_ n: Int) {
        if n > 0 { bytes.append(contentsOf: [UInt8](repeating: 0, count: n)) }
    }
    public mutating func pad(to multiple: Int) {
        let r = bytes.count % multiple
        if r != 0 { zeros(multiple - r) }
    }
    public mutating func padTo(length: Int) {
        if bytes.count < length { zeros(length - bytes.count) }
    }
    public mutating func patchU32(_ v: UInt32, at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: v)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: v >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: v >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: v >> 24)
    }
    public mutating func patchU32(_ v: Int, at offset: Int) { patchU32(UInt32(truncatingIfNeeded: v), at: offset) }
}

/// Little-endian byte reader over a [UInt8] buffer.
public struct ByteReader {
    public let bytes: [UInt8]
    public var position: Int = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = [UInt8](data) }

    public var remaining: Int { bytes.count - position }

    private func check(_ n: Int) throws {
        if position < 0 || position + n > bytes.count { throw ThemeKitError.unexpectedEnd }
    }

    public mutating func u8() throws -> UInt8 {
        try check(1); defer { position += 1 }
        return bytes[position]
    }
    public mutating func u16() throws -> UInt16 {
        try check(2); defer { position += 2 }
        return UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
    }
    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    public mutating func u32() throws -> UInt32 {
        try check(4); defer { position += 4 }
        return UInt32(bytes[position]) | UInt32(bytes[position + 1]) << 8
            | UInt32(bytes[position + 2]) << 16 | UInt32(bytes[position + 3]) << 24
    }
    public mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    public mutating func int() throws -> Int { Int(try u32()) }
    public mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
    public mutating func read(_ n: Int) throws -> [UInt8] {
        try check(n); defer { position += n }
        return Array(bytes[position..<(position + n)])
    }
    public mutating func ascii(_ n: Int) throws -> String {
        String(decoding: try read(n), as: UTF8.self)
    }
    public mutating func skip(_ n: Int) throws { try check(n); position += n }

    public func u32(at offset: Int) throws -> UInt32 {
        var r = self
        r.position = offset
        return try r.u32()
    }
}

extension Array where Element == UInt8 {
    func readU32LE(_ o: Int) -> UInt32 {
        UInt32(self[o]) | UInt32(self[o + 1]) << 8 | UInt32(self[o + 2]) << 16 | UInt32(self[o + 3]) << 24
    }
}

/// CRC-32 (IEEE) used by ZIP files.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
