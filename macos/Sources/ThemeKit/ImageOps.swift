import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// How an imported picture is fitted into a target area.
public enum FitMode: String, CaseIterable, Codable, Identifiable {
    case fill, fit, stretch
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fill: return "Fill (crop edges)"
        case .fit: return "Fit (letterbox)"
        case .stretch: return "Stretch"
        }
    }
}

public enum ImageOps {
    public static func loadCGImage(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    public static func loadCGImage(data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static let rgbSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws `image` into a width×height RGB buffer using the given fit mode.
    public static func render(_ image: CGImage, width: Int, height: Int, mode: FitMode = .fill,
                              background: RGB = RGB(0, 0, 0), offset: CGPoint = .zero, zoom: CGFloat = 1) -> RGBImage {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: rgbSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(srgbRed: CGFloat(background.r) / 255, green: CGFloat(background.g) / 255,
                                     blue: CGFloat(background.b) / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let iw = CGFloat(image.width), ih = CGFloat(image.height)
            let tw = CGFloat(width), th = CGFloat(height)
            var rect: CGRect
            switch mode {
            case .stretch:
                rect = CGRect(x: 0, y: 0, width: tw, height: th)
            case .fill:
                let s = max(tw / iw, th / ih) * zoom
                rect = CGRect(x: (tw - iw * s) / 2, y: (th - ih * s) / 2, width: iw * s, height: ih * s)
            case .fit:
                let s = min(tw / iw, th / ih) * zoom
                rect = CGRect(x: (tw - iw * s) / 2, y: (th - ih * s) / 2, width: iw * s, height: ih * s)
            }
            // offset is in target pixels, positive = move right / down
            rect.origin.x += offset.x
            rect.origin.y -= offset.y
            ctx.draw(image, in: rect)
        }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let a = Int(rgba[i * 4 + 3])
            // Composite over the background (buffer is premultiplied).
            let inv = 255 - a
            rgb[i * 3] = UInt8(min(255, Int(rgba[i * 4]) + Int(background.r) * inv / 255))
            rgb[i * 3 + 1] = UInt8(min(255, Int(rgba[i * 4 + 1]) + Int(background.g) * inv / 255))
            rgb[i * 3 + 2] = UInt8(min(255, Int(rgba[i * 4 + 2]) + Int(background.b) * inv / 255))
        }
        return RGBImage(width: width, height: height, pixels: rgb)
    }

    /// Creates a CGImage from an RGB buffer.
    public static func cgImage(_ img: RGBImage) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: img.width * img.height * 4)
        for i in 0..<(img.width * img.height) {
            rgba[i * 4] = img.pixels[i * 3]
            rgba[i * 4 + 1] = img.pixels[i * 3 + 1]
            rgba[i * 4 + 2] = img.pixels[i * 3 + 2]
        }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: img.width * 4, space: rgbSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Alpha-mask image (white with alpha = gray level) for previewing A8 patterns.
    public static func maskImage(_ img: RGBImage, tint: RGB = RGB(255, 255, 255)) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: img.width * img.height * 4)
        for i in 0..<(img.width * img.height) {
            let a = Int(img.pixels[i * 3])
            rgba[i * 4] = UInt8(Int(tint.r) * a / 255)
            rgba[i * 4 + 1] = UInt8(Int(tint.g) * a / 255)
            rgba[i * 4 + 2] = UInt8(Int(tint.b) * a / 255)
            rgba[i * 4 + 3] = UInt8(a)
        }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: img.width * 4, space: rgbSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Reads back an RGB buffer from any CGImage at its native size.
    public static func rgb(from image: CGImage) -> RGBImage {
        render(image, width: image.width, height: image.height, mode: .stretch)
    }

    /// Most-used colors of an image, grouped and de-duplicated (port of the Usagi palette tool).
    public static func palette(_ img: RGBImage, maxColors: Int = 20, tolerance: Double = 0.025) -> [RGB] {
        var buckets: [UInt32: (count: Int, r: Int, g: Int, b: Int)] = [:]
        let step = max(1, (img.width * img.height) / 120_000)
        var i = 0
        while i < img.width * img.height {
            let r = Int(img.pixels[i * 3]), g = Int(img.pixels[i * 3 + 1]), b = Int(img.pixels[i * 3 + 2])
            let key = UInt32((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3))
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.count += 1; e.r += r; e.g += g; e.b += b
            buckets[key] = e
            i += step
        }
        let sorted = buckets.values.sorted { $0.count > $1.count }
            .map { RGB(UInt8($0.r / $0.count), UInt8($0.g / $0.count), UInt8($0.b / $0.count)) }
        let minDist = tolerance * 255 * 255 * 3
        var out: [RGB] = []
        for c in sorted {
            if out.count >= maxColors { break }
            let far = out.allSatisfy { o in
                let dr = Double(Int(c.r) - Int(o.r)), dg = Double(Int(c.g) - Int(o.g)), db = Double(Int(c.b) - Int(o.b))
                return dr * dr + dg * dg + db * db > minDist
            }
            if far { out.append(c) }
        }
        return out.sorted { hue($0) < hue($1) }
    }

    static func hue(_ c: RGB) -> Double {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        if d < 0.08 { return -1 + (r + g + b) / 3 }   // grays first, dark → light
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }
}
