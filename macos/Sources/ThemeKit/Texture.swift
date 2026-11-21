import Foundation

/// A simple 24-bit RGB image, row-major, top-left origin.
public struct RGBImage: Equatable, Hashable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]   // r,g,b per pixel

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3, "RGBImage pixel buffer has the wrong size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: RGB = RGB(0, 0, 0)) {
        self.width = width
        self.height = height
        var p = [UInt8](repeating: 0, count: width * height * 3)
        if fill != RGB(0, 0, 0) {
            for i in stride(from: 0, to: p.count, by: 3) { p[i] = fill.r; p[i + 1] = fill.g; p[i + 2] = fill.b }
        }
        self.pixels = p
    }

    public func pixel(_ x: Int, _ y: Int) -> RGB {
        let i = (y * width + x) * 3
        return RGB(pixels[i], pixels[i + 1], pixels[i + 2])
    }

    public mutating func setPixel(_ x: Int, _ y: Int, _ c: RGB) {
        let i = (y * width + x) * 3
        pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b
    }

    /// Copies `self` into a larger canvas at (0,0) and repeats the last column/row
    /// into the unused area ("edge bleeding"), so filtering on the 3DS never shows seams.
    public func bled(toWidth w: Int, height h: Int) -> RGBImage {
        var out = RGBImage(width: w, height: h)
        let cw = min(width, w), ch = min(height, h)
        for y in 0..<h {
            let sy = min(y, ch - 1)
            for x in 0..<w {
                let sx = min(x, cw - 1)
                let si = (sy * width + sx) * 3
                let di = (y * w + x) * 3
                out.pixels[di] = pixels[si]
                out.pixels[di + 1] = pixels[si + 1]
                out.pixels[di + 2] = pixels[si + 2]
            }
        }
        return out
    }

    /// Returns the region (0,0,w,h).
    public func cropped(width w: Int, height h: Int) -> RGBImage {
        var out = RGBImage(width: w, height: h)
        for y in 0..<min(h, height) {
            for x in 0..<min(w, width) {
                let si = (y * width + x) * 3, di = (y * w + x) * 3
                out.pixels[di] = pixels[si]; out.pixels[di + 1] = pixels[si + 1]; out.pixels[di + 2] = pixels[si + 2]
            }
        }
        return out
    }

    public func grayscaleLevels() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Int(pixels[i * 3]), gg = Int(pixels[i * 3 + 1]), b = Int(pixels[i * 3 + 2])
            g[i] = UInt8(min(255, (r * 299 + gg * 587 + b * 114) / 1000))
        }
        return g
    }
}

/// Pixel formats used by 3DS home menu textures.
public enum TextureFormat: String, Codable {
    case rgb565, bgr888, a8

    public var bytesPerPixel: Int {
        switch self {
        case .rgb565: return 2
        case .bgr888: return 3
        case .a8: return 1
        }
    }
}

/// Morton-tiled (8x8) texture encoding/decoding exactly as used by the 3DS GPU.
public enum TextureCodec {
    @inline(__always)
    static func compact(_ v: UInt32) -> UInt32 {
        var x = v & 0x55555555
        x = (x | (x >> 1)) & 0x33333333
        x = (x | (x >> 2)) & 0x0F0F0F0F
        x = (x | (x >> 4)) & 0x00FF00FF
        x = (x | (x >> 8)) & 0x0000FFFF
        return x
    }

    /// Maps the linear index of a texel in the file to its (x, y) image coordinate.
    @inline(__always)
    static func coord(index j: Int, width: Int) -> (Int, Int) {
        let tilesPerRow = max(1, (width + 7) / 8)
        let within = UInt32(j % 64)
        let tile = j / 64
        let x = Int(compact(within)) + (tile % tilesPerRow) * 8
        let y = Int(compact(within >> 1)) + (tile / tilesPerRow) * 8
        return (x, y)
    }

    static let bayer8x8: [Int] = [
        1, 49, 13, 61, 4, 52, 16, 64,
        33, 17, 45, 29, 36, 20, 48, 32,
        9, 57, 5, 53, 12, 60, 8, 56,
        41, 25, 37, 21, 44, 28, 40, 24,
        3, 51, 15, 63, 2, 50, 14, 62,
        35, 19, 47, 31, 34, 18, 46, 30,
        11, 59, 7, 55, 10, 58, 6, 54,
        43, 27, 39, 23, 42, 26, 38, 22,
    ]

    /// Ordered (Bayer 8x8) dither towards the 5-6-5 grid to reduce banding.
    public static func ditherTo565(_ img: RGBImage) -> RGBImage {
        var out = img
        for y in 0..<img.height {
            for x in 0..<img.width {
                let t = bayer8x8[((y & 7) << 3) + (x & 7)]
                let i = (y * img.width + x) * 3
                let r = min(255, Int(img.pixels[i]) + t * 8 / 65)
                let g = min(255, Int(img.pixels[i + 1]) + t * 4 / 65)
                let b = min(255, Int(img.pixels[i + 2]) + t * 8 / 65)
                out.pixels[i] = UInt8((r >> 3) << 3)
                out.pixels[i + 1] = UInt8((g >> 2) << 2)
                out.pixels[i + 2] = UInt8((b >> 3) << 3)
            }
        }
        return out
    }

    public static func encode(_ img: RGBImage, format: TextureFormat, dither: Bool = true) -> [UInt8] {
        let w = img.width, h = img.height
        let count = w * h
        switch format {
        case .rgb565:
            let src = dither ? ditherTo565(img) : img
            var out = [UInt8](repeating: 0, count: count * 2)
            for j in 0..<count {
                let (x, y) = coord(index: j, width: w)
                let i = (y * w + x) * 3
                let r = Int(src.pixels[i]) >> 3, g = Int(src.pixels[i + 1]) >> 2, b = Int(src.pixels[i + 2]) >> 3
                let px = (r << 11) | (g << 5) | b
                out[j * 2] = UInt8(px & 0xFF)
                out[j * 2 + 1] = UInt8(px >> 8)
            }
            return out
        case .bgr888:
            var out = [UInt8](repeating: 0, count: count * 3)
            for j in 0..<count {
                let (x, y) = coord(index: j, width: w)
                let i = (y * w + x) * 3
                out[j * 3] = img.pixels[i + 2]
                out[j * 3 + 1] = img.pixels[i + 1]
                out[j * 3 + 2] = img.pixels[i]
            }
            return out
        case .a8:
            precondition(w == h, "A8 textures must be square")
            let gray = img.grayscaleLevels()
            // Rotate counter-clockwise (matches the home menu's sampling of these masks).
            var rot = [UInt8](repeating: 0, count: count)
            for i in 0..<w {
                for j in 0..<h {
                    rot[j * w + i] = gray[(w - 1 - i) * w + j]
                }
            }
            var out = [UInt8](repeating: 0, count: count)
            for k in 0..<count {
                let (x, y) = coord(index: k, width: w)
                out[k] = rot[y * w + x]
            }
            return out
        }
    }

    public static func decode(_ data: [UInt8], width w: Int, height h: Int, format: TextureFormat) throws -> RGBImage {
        let count = w * h
        guard data.count >= count * format.bytesPerPixel else { throw ThemeKitError.unexpectedEnd }
        var img = RGBImage(width: w, height: h)
        switch format {
        case .rgb565:
            for j in 0..<count {
                let px = Int(data[j * 2]) | Int(data[j * 2 + 1]) << 8
                let (x, y) = coord(index: j, width: w)
                let i = (y * w + x) * 3
                let r = (px >> 11) & 0x1F, g = (px >> 5) & 0x3F, b = px & 0x1F
                img.pixels[i] = UInt8((r << 3) | (r >> 2))
                img.pixels[i + 1] = UInt8((g << 2) | (g >> 4))
                img.pixels[i + 2] = UInt8((b << 3) | (b >> 2))
            }
        case .bgr888:
            for j in 0..<count {
                let (x, y) = coord(index: j, width: w)
                let i = (y * w + x) * 3
                img.pixels[i] = data[j * 3 + 2]
                img.pixels[i + 1] = data[j * 3 + 1]
                img.pixels[i + 2] = data[j * 3]
            }
        case .a8:
            var rot = [UInt8](repeating: 0, count: count)
            for k in 0..<count {
                let (x, y) = coord(index: k, width: w)
                rot[y * w + x] = data[k]
            }
            // Rotate clockwise back to upright.
            for i in 0..<w {
                for j in 0..<h {
                    let v = rot[j * w + i]
                    let di = ((w - 1 - i) * w + j) * 3
                    img.pixels[di] = v; img.pixels[di + 1] = v; img.pixels[di + 2] = v
                }
            }
        }
        return img
    }
}
