import Foundation

/// info.smdh — title, description, author and icons shown by theme managers (Anemone3DS, CHMM2, ThemePlaza).
public struct SMDH: Hashable {
    public struct Title: Hashable {
        public var shortDescription: String = ""   // up to 64 UTF-16 chars
        public var longDescription: String = ""    // up to 128 UTF-16 chars
        public var publisher: String = ""          // up to 64 UTF-16 chars
        public init() {}
    }

    public static let titleCount = 16
    public static let languageNames = ["Japanese", "English", "French", "German", "Italian", "Spanish",
                                       "Chinese (Simplified)", "Korean", "Dutch", "Portuguese", "Russian",
                                       "Chinese (Traditional)"]

    public var version: UInt16 = 0
    public var titles: [Title] = Array(repeating: Title(), count: 16)
    /// Raw application-settings block (0x30 bytes); kept as-is when editing an existing file.
    public var settings: [UInt8] = SMDH.defaultSettings
    public var largeIcon: RGBImage = SMDH.defaultIcon(size: 48)  // 48x48 RGB565
    public var smallIcon: RGBImage = SMDH.defaultIcon(size: 24)  // 24x24 RGB565

    public init() {}

    /// Convenience: sets the same title on every language slot.
    public mutating func setAllTitles(name: String, description: String, author: String) {
        var t = Title()
        t.shortDescription = String(name.prefix(64))
        t.longDescription = String(description.prefix(128))
        t.publisher = String(author.prefix(64))
        titles = Array(repeating: t, count: 16)
    }

    /// The English title if present, otherwise the first non-empty one.
    public var primaryTitle: Title {
        if !titles[1].shortDescription.isEmpty { return titles[1] }
        return titles.first(where: { !$0.shortDescription.isEmpty }) ?? Title()
    }

    static let defaultSettings: [UInt8] = {
        var w = ByteWriter()
        w.zeros(16)                 // age ratings
        w.u32(0x7FFFFFFF)           // region lock: region free
        w.zeros(12)                 // match maker IDs
        w.u32(0x0001)               // flags: visible
        w.zeros(2)                  // EULA version
        w.zeros(2)                  // reserved
        w.f32(0)                    // optimal banner frame
        w.u32(0)                    // streetpass id
        return w.bytes
    }()

    public static func defaultIcon(size: Int) -> RGBImage {
        var img = RGBImage(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let t = Double(y) / Double(size)
                let r = UInt8(40 + 60 * t), g = UInt8(140 + 50 * t), b = UInt8(230 - 30 * t)
                img.setPixel(x, y, RGB(r, g, b))
            }
        }
        return img
    }

    // MARK: IO

    public static func read(_ bytes: [UInt8]) throws -> SMDH {
        guard bytes.count >= 0x36C0 else { throw ThemeKitError.invalidFormat("info.smdh is too small.") }
        var r = ByteReader(bytes)
        guard try r.ascii(4) == "SMDH" else { throw ThemeKitError.invalidFormat("This is not an SMDH file.") }
        var s = SMDH()
        s.version = try r.u16()
        try r.skip(2)
        var titles: [Title] = []
        for _ in 0..<16 {
            var t = Title()
            t.shortDescription = try readUTF16(&r, bytes: 0x80)
            t.longDescription = try readUTF16(&r, bytes: 0x100)
            t.publisher = try readUTF16(&r, bytes: 0x80)
            titles.append(t)
        }
        s.titles = titles
        s.settings = try r.read(0x30)
        try r.skip(8)
        s.smallIcon = try TextureCodec.decode(try r.read(24 * 24 * 2), width: 24, height: 24, format: .rgb565)
        s.largeIcon = try TextureCodec.decode(try r.read(48 * 48 * 2), width: 48, height: 48, format: .rgb565)
        return s
    }

    public func write() -> [UInt8] {
        var w = ByteWriter(capacity: 0x36C0)
        w.ascii("SMDH")
        w.u16(version)
        w.u16(0)
        for i in 0..<16 {
            let t = i < titles.count ? titles[i] : Title()
            Self.writeUTF16(&w, t.shortDescription, bytes: 0x80)
            Self.writeUTF16(&w, t.longDescription, bytes: 0x100)
            Self.writeUTF16(&w, t.publisher, bytes: 0x80)
        }
        var settingsBytes = settings
        if settingsBytes.count != 0x30 { settingsBytes = Self.defaultSettings }
        w.append(settingsBytes)
        w.zeros(8)
        w.append(TextureCodec.encode(smallIcon.width == 24 ? smallIcon : Self.downscale(largeIcon, to: 24), format: .rgb565, dither: false))
        w.append(TextureCodec.encode(largeIcon, format: .rgb565, dither: false))
        return w.bytes
    }

    private static func readUTF16(_ r: inout ByteReader, bytes n: Int) throws -> String {
        let raw = try r.read(n)
        var units: [UInt16] = []
        var i = 0
        while i + 1 < raw.count {
            let u = UInt16(raw[i]) | UInt16(raw[i + 1]) << 8
            if u == 0 { break }
            units.append(u)
            i += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func writeUTF16(_ w: inout ByteWriter, _ s: String, bytes n: Int) {
        var units = Array(s.utf16)
        if units.count * 2 > n - 2 { units = Array(units.prefix((n - 2) / 2)) }
        for u in units { w.u16(u) }
        w.zeros(n - units.count * 2)
    }

    /// Box-filter downscale (used to make the small icon from the large one).
    public static func downscale(_ img: RGBImage, to size: Int) -> RGBImage {
        var out = RGBImage(width: size, height: size)
        let sx = Double(img.width) / Double(size), sy = Double(img.height) / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let x0 = Int(Double(x) * sx), x1 = max(x0 + 1, Int(Double(x + 1) * sx))
                let y0 = Int(Double(y) * sy), y1 = max(y0 + 1, Int(Double(y + 1) * sy))
                var r = 0, g = 0, b = 0, n = 0
                for yy in y0..<min(y1, img.height) {
                    for xx in x0..<min(x1, img.width) {
                        let p = img.pixel(xx, yy); r += Int(p.r); g += Int(p.g); b += Int(p.b); n += 1
                    }
                }
                n = max(n, 1)
                out.setPixel(x, y, RGB(UInt8(r / n), UInt8(g / n), UInt8(b / n)))
            }
        }
        return out
    }
}
