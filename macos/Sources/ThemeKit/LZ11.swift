import Foundation

/// Nintendo LZ11 compression, used for body_LZ.bin.
public enum LZ11 {
    public static func isCompressed(_ data: [UInt8]) -> Bool {
        data.count >= 4 && data[0] == 0x11
    }

    public static func decompress(_ data: [UInt8]) throws -> [UInt8] {
        guard data.count >= 4, data[0] == 0x11 else {
            throw ThemeKitError.invalidFormat("This file is not LZ11-compressed.")
        }
        var p = 4
        var size = Int(data[1]) | Int(data[2]) << 8 | Int(data[3]) << 16
        if size == 0 {
            guard data.count >= 8 else { throw ThemeKitError.unexpectedEnd }
            size = Int(data.readU32LE(4))
            p = 8
        }
        guard size < 64 * 1024 * 1024 else { throw ThemeKitError.tooLarge("Decompressed size is unreasonably large.") }
        var out = [UInt8]()
        out.reserveCapacity(size)
        while out.count < size {
            guard p < data.count else { throw ThemeKitError.unexpectedEnd }
            let flags = data[p]; p += 1
            for bit in 0..<8 {
                if out.count >= size { break }
                if flags & (0x80 >> UInt8(bit)) != 0 {
                    guard p + 1 < data.count else { throw ThemeKitError.unexpectedEnd }
                    let b1 = Int(data[p])
                    var length: Int
                    var disp: Int
                    switch b1 >> 4 {
                    case 0:
                        guard p + 2 < data.count else { throw ThemeKitError.unexpectedEnd }
                        length = (((b1 & 0xF) << 4) | (Int(data[p + 1]) >> 4)) + 0x11
                        disp = (((Int(data[p + 1]) & 0xF) << 8) | Int(data[p + 2])) + 1
                        p += 3
                    case 1:
                        guard p + 3 < data.count else { throw ThemeKitError.unexpectedEnd }
                        length = (((b1 & 0xF) << 12) | (Int(data[p + 1]) << 4) | (Int(data[p + 2]) >> 4)) + 0x111
                        disp = (((Int(data[p + 2]) & 0xF) << 8) | Int(data[p + 3])) + 1
                        p += 4
                    default:
                        length = (b1 >> 4) + 1
                        disp = (((b1 & 0xF) << 8) | Int(data[p + 1])) + 1
                        p += 2
                    }
                    guard disp <= out.count else {
                        throw ThemeKitError.invalidFormat("Compressed data refers outside the buffer.")
                    }
                    let start = out.count - disp
                    for i in 0..<length {
                        if out.count >= size { break }
                        out.append(out[start + i])
                    }
                } else {
                    guard p < data.count else { throw ThemeKitError.unexpectedEnd }
                    out.append(data[p]); p += 1
                }
            }
        }
        return out
    }

    /// Greedy LZ11 compressor with hash chains. Output is padded to a multiple of 4 bytes.
    public static func compress(_ input: [UInt8]) -> [UInt8] {
        let n = input.count
        var out = [UInt8]()
        out.reserveCapacity(n / 2 + 16)
        if n <= 0xFFFFFF {
            out += [0x11, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF)]
        } else {
            out += [0x11, 0, 0, 0, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)]
        }
        if n == 0 { return out }

        let hashBits = 16
        let hashSize = 1 << hashBits
        var head = [Int32](repeating: -1, count: hashSize)
        var prev = [Int32](repeating: -1, count: n)
        let maxChain = 192
        let window = 0x1000
        let maxMatch = 0x10110

        return input.withUnsafeBufferPointer { src -> [UInt8] in
            @inline(__always) func hash(_ i: Int) -> Int {
                let v = (UInt32(src[i]) << 16) | (UInt32(src[i + 1]) << 8) | UInt32(src[i + 2])
                return Int((v &* 2654435761) >> UInt32(32 - hashBits))
            }
            @inline(__always) func insert(_ i: Int) {
                if i + 2 < n {
                    let h = hash(i)
                    prev[i] = head[h]
                    head[h] = Int32(i)
                }
            }

            var pos = 0
            while pos < n {
                let flagIndex = out.count
                out.append(0)
                var flags: UInt8 = 0
                for bit in 0..<8 {
                    if pos >= n { break }
                    var bestLen = 0
                    var bestDisp = 0
                    if pos + 2 < n {
                        let limit = min(maxMatch, n - pos)
                        var cand = Int(head[hash(pos)])
                        var chain = 0
                        while cand >= 0 && pos - cand <= window && chain < maxChain {
                            if src[cand + bestLen] == src[pos + bestLen] || bestLen == 0 {
                                var l = 0
                                while l < limit && src[cand + l] == src[pos + l] { l += 1 }
                                if l > bestLen {
                                    bestLen = l
                                    bestDisp = pos - cand
                                    if l == limit { break }
                                }
                            }
                            cand = Int(prev[cand])
                            chain += 1
                        }
                    }
                    if bestLen >= 3 {
                        flags |= 0x80 >> UInt8(bit)
                        let d = bestDisp - 1
                        if bestLen <= 0x10 {
                            out.append(UInt8(((bestLen - 1) << 4) | (d >> 8)))
                            out.append(UInt8(d & 0xFF))
                        } else if bestLen <= 0x110 {
                            let l = bestLen - 0x11
                            out.append(UInt8(l >> 4))
                            out.append(UInt8(((l & 0xF) << 4) | (d >> 8)))
                            out.append(UInt8(d & 0xFF))
                        } else {
                            let l = bestLen - 0x111
                            out.append(UInt8(0x10 | (l >> 12)))
                            out.append(UInt8((l >> 4) & 0xFF))
                            out.append(UInt8(((l & 0xF) << 4) | (d >> 8)))
                            out.append(UInt8(d & 0xFF))
                        }
                        for k in 0..<bestLen { insert(pos + k) }
                        pos += bestLen
                    } else {
                        out.append(src[pos])
                        insert(pos)
                        pos += 1
                    }
                }
                out[flagIndex] = flags
            }
            while out.count % 4 != 0 { out.append(0) }
            return out
        }
    }
}
