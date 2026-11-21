import Foundation
import CoreGraphics
import CoreImage

/// Every adjustment the image editor can make to a picture before it becomes a 3DS texture.
public struct ImageEdit: Codable, Hashable {
    // Geometry
    public var fit: FitMode = .fill
    public var zoom: Double = 1            // 1 = fitted size
    public var offsetX: Double = 0         // target pixels, + = right
    public var offsetY: Double = 0         // target pixels, + = down
    public var quarterTurns: Int = 0       // clockwise 90° steps
    public var angle: Double = 0           // fine rotation in degrees, clockwise
    public var flipHorizontal = false
    public var flipVertical = false
    public var background = RGB(0, 0, 0)   // fill for empty areas (Fit mode / rotation)

    // Color
    public var brightness: Double = 0      // -1 … 1
    public var contrast: Double = 1        // 0.25 … 2
    public var saturation: Double = 1      // 0 … 2
    public var hue: Double = 0             // degrees -180 … 180
    public var warmth: Double = 0          // -1 … 1
    public var sharpen: Double = 0         // 0 … 2
    public var blur: Double = 0            // 0 … 20 px
    public var vignette: Double = 0        // 0 … 2

    public init() {}
    public init(fit: FitMode) { self.fit = fit }

    public var hasColorAdjustments: Bool {
        brightness != 0 || contrast != 1 || saturation != 1 || hue != 0 || warmth != 0 || sharpen != 0 || blur != 0 || vignette != 0
    }

    /// Only the color part, used to decide when the adjusted image must be rebuilt.
    public var colorKey: [Double] { [brightness, contrast, saturation, hue, warmth, sharpen, blur, vignette] }

    public mutating func resetGeometry() {
        zoom = 1; offsetX = 0; offsetY = 0; quarterTurns = 0; angle = 0; flipHorizontal = false; flipVertical = false
    }

    public mutating func resetColor() {
        brightness = 0; contrast = 1; saturation = 1; hue = 0; warmth = 0; sharpen = 0; blur = 0; vignette = 0
    }
}

extension ImageOps {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Applies the color adjustments with Core Image. Returns the input when nothing changes.
    public static func adjusted(_ image: CGImage, _ e: ImageEdit) -> CGImage {
        guard e.hasColorAdjustments else { return image }
        var ci = CIImage(cgImage: image)
        let extent = ci.extent

        if e.brightness != 0 || e.contrast != 1 || e.saturation != 1, let f = CIFilter(name: "CIColorControls") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(e.brightness * 0.5, forKey: kCIInputBrightnessKey)
            f.setValue(e.contrast, forKey: kCIInputContrastKey)
            f.setValue(e.saturation, forKey: kCIInputSaturationKey)
            if let o = f.outputImage { ci = o }
        }
        if e.hue != 0, let f = CIFilter(name: "CIHueAdjust") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(e.hue * .pi / 180, forKey: kCIInputAngleKey)
            if let o = f.outputImage { ci = o }
        }
        if e.warmth != 0, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 + CGFloat(e.warmth) * 3000, y: 0), forKey: "inputTargetNeutral")
            if let o = f.outputImage { ci = o }
        }
        if e.blur > 0, let f = CIFilter(name: "CIGaussianBlur") {
            f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            f.setValue(e.blur, forKey: kCIInputRadiusKey)
            if let o = f.outputImage { ci = o.cropped(to: extent) }
        }
        if e.sharpen > 0, let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(e.sharpen, forKey: kCIInputSharpnessKey)
            if let o = f.outputImage { ci = o }
        }
        if e.vignette > 0, let f = CIFilter(name: "CIVignette") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(e.vignette, forKey: kCIInputIntensityKey)
            f.setValue(max(extent.width, extent.height) / 2, forKey: kCIInputRadiusKey)
            if let o = f.outputImage { ci = o }
        }
        return ciContext.createCGImage(ci.cropped(to: extent), from: extent, format: .RGBA8,
                                       colorSpace: rgbSpace) ?? image
    }

    /// Shrinks very large pictures so editing stays fast (longest side at most `maxSide`).
    public static func limitSize(_ image: CGImage, maxSide: Int = 2400) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let s = Double(maxSide) / Double(longest)
        let w = max(1, Int(Double(image.width) * s)), h = max(1, Int(Double(image.height) * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: rgbSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Renders an (already color-adjusted) picture into a width×height area using the edit's geometry.
    public static func render(_ image: CGImage, width: Int, height: Int, edit e: ImageEdit) -> RGBImage {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let bg = e.background
        rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: rgbSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(srgbRed: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let turns = ((e.quarterTurns % 4) + 4) % 4
            let odd = turns % 2 == 1
            let iw = CGFloat(image.width), ih = CGFloat(image.height)
            // Size of the picture as displayed (after quarter turns).
            let dw = odd ? ih : iw, dh = odd ? iw : ih
            let tw = CGFloat(width), th = CGFloat(height)
            var sx: CGFloat, sy: CGFloat
            switch e.fit {
            case .fill: sx = max(tw / dw, th / dh); sy = sx
            case .fit: sx = min(tw / dw, th / dh); sy = sx
            case .stretch: sx = tw / dw; sy = th / dh
            }
            sx *= CGFloat(e.zoom); sy *= CGFloat(e.zoom)
            // In image space, the image's width maps to the displayed height when rotated by 90°/270°.
            let drawW = iw * (odd ? sy : sx), drawH = ih * (odd ? sx : sy)

            ctx.translateBy(x: tw / 2 + CGFloat(e.offsetX), y: th / 2 - CGFloat(e.offsetY))
            // Flip in screen space (applied after rotation), then rotate clockwise.
            ctx.scaleBy(x: e.flipHorizontal ? -1 : 1, y: e.flipVertical ? -1 : 1)
            ctx.rotate(by: -(CGFloat(turns) * .pi / 2 + CGFloat(e.angle) * .pi / 180))
            ctx.draw(image, in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
        }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let inv = 255 - Int(rgba[i * 4 + 3])
            rgb[i * 3] = UInt8(min(255, Int(rgba[i * 4]) + Int(bg.r) * inv / 255))
            rgb[i * 3 + 1] = UInt8(min(255, Int(rgba[i * 4 + 1]) + Int(bg.g) * inv / 255))
            rgb[i * 3 + 2] = UInt8(min(255, Int(rgba[i * 4 + 2]) + Int(bg.b) * inv / 255))
        }
        return RGBImage(width: width, height: height, pixels: rgb)
    }

    /// Simulates how a picture will look on the console after 16-bit conversion.
    public static func consolePreview(_ img: RGBImage, format: TextureFormat, dither: Bool) -> RGBImage {
        switch format {
        case .rgb565:
            if dither { return TextureCodec.ditherTo565(img) }
            var o = img
            for i in stride(from: 0, to: o.pixels.count, by: 3) {
                o.pixels[i] = (o.pixels[i] >> 3) << 3; o.pixels[i + 1] = (o.pixels[i + 1] >> 2) << 2; o.pixels[i + 2] = (o.pixels[i + 2] >> 3) << 3
            }
            return o
        case .a8:
            let g = img.grayscaleLevels()
            var o = img
            for i in 0..<g.count { o.pixels[i * 3] = g[i]; o.pixels[i * 3 + 1] = g[i]; o.pixels[i * 3 + 2] = g[i] }
            return o
        case .bgr888:
            return img
        }
    }
}
