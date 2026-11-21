import Foundation
import Compression

/// Minimal ZIP support: writes stored (uncompressed) archives and reads stored/deflated ones.
public enum Zip {
    public struct Entry {
        public var name: String
        public var data: [UInt8]
        public init(name: String, data: [UInt8]) { self.name = name; self.data = data }
    }

    public static func write(_ entries: [Entry]) -> [UInt8] {
        var w = ByteWriter()
        var central = ByteWriter()
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = (UInt16(2026 - 1980) << 9) | (1 << 5) | 1
        for e in entries {
            let nameBytes = Array(e.name.utf8)
            let crc = CRC32.checksum(e.data)
            let offset = w.count
            w.u32(0x04034B50); w.u16(20); w.u16(0x0800); w.u16(0); w.u16(dosTime); w.u16(dosDate)
            w.u32(crc); w.u32(e.data.count); w.u32(e.data.count)
            w.u16(UInt16(nameBytes.count)); w.u16(0)
            w.append(nameBytes); w.append(e.data)

            central.u32(0x02014B50); central.u16(20); central.u16(20); central.u16(0x0800); central.u16(0)
            central.u16(dosTime); central.u16(dosDate); central.u32(crc)
            central.u32(e.data.count); central.u32(e.data.count)
            central.u16(UInt16(nameBytes.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
            central.u32(0); central.u32(offset)
            central.append(nameBytes)
        }
        let cdOffset = w.count
        w.append(central.bytes)
        w.u32(0x06054B50); w.u16(0); w.u16(0)
        w.u16(UInt16(entries.count)); w.u16(UInt16(entries.count))
        w.u32(central.count); w.u32(cdOffset); w.u16(0)
        return w.bytes
    }

    public static func read(_ bytes: [UInt8]) throws -> [Entry] {
        // Find end of central directory
        guard bytes.count >= 22 else { throw ThemeKitError.invalidFormat("Not a ZIP file.") }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65535)
        while i >= lowest {
            if bytes.readU32LE(i) == 0x06054B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ThemeKitError.invalidFormat("Not a ZIP file (no directory found).") }
        var r = ByteReader(bytes)
        r.position = eocd + 10
        let count = Int(try r.u16())
        _ = try r.u32()
        let cdOffset = try r.int()
        r.position = cdOffset
        var entries: [Entry] = []
        for _ in 0..<count {
            guard try r.u32() == 0x02014B50 else { break }
            try r.skip(6)
            let method = try r.u16()
            try r.skip(8)
            let compSize = try r.int()
            let uncompSize = try r.int()
            let nameLen = Int(try r.u16()), extraLen = Int(try r.u16()), commentLen = Int(try r.u16())
            try r.skip(8)
            let localOffset = try r.int()
            let name = String(decoding: try r.read(nameLen), as: UTF8.self)
            try r.skip(extraLen + commentLen)
            if name.hasSuffix("/") { continue }

            var lr = ByteReader(bytes)
            lr.position = localOffset
            guard try lr.u32() == 0x04034B50 else { continue }
            try lr.skip(22)
            let ln = Int(try lr.u16()), le = Int(try lr.u16())
            try lr.skip(ln + le)
            let comp = try lr.read(compSize)
            switch method {
            case 0: entries.append(Entry(name: name, data: comp))
            case 8: entries.append(Entry(name: name, data: try inflate(comp, expected: uncompSize)))
            default: continue
            }
        }
        return entries
    }

    static func inflate(_ data: [UInt8], expected: Int) throws -> [UInt8] {
        if expected == 0 { return [] }
        var out = [UInt8](repeating: 0, count: expected)
        let n = data.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, expected, src.baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expected else { throw ThemeKitError.invalidFormat("Could not decompress a file inside the ZIP.") }
        return out
    }
}
