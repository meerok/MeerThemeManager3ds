import Foundation

/// Size limits enforced by the 3DS HOME Menu / theme managers.
public enum ThemeLimits {
    /// Maximum size of the compressed body_LZ.bin (BodyCache.bin is 0x150000 bytes).
    public static let maxCompressedBody = 0x150000
    /// Maximum size of bgm.bcstm (BgmCache.bin is 0x337000 bytes).
    public static let maxBGM = 0x337000
    /// Maximum size of the sound-effect block.
    public static let maxSoundEffects = 0x2DC00
}

/// Texture slots in a theme, with their exact sizes and formats.
public enum TextureSlot: String, CaseIterable, Codable, Identifiable {
    case top, topPattern, topAltPattern, bottom, folderClosed, folderOpen, fileLarge, fileSmall
    public var id: String { rawValue }

    public var format: TextureFormat {
        switch self {
        case .top, .bottom: return .rgb565
        case .topPattern, .topAltPattern: return .a8
        case .folderClosed, .folderOpen, .fileLarge, .fileSmall: return .bgr888
        }
    }
}

/// Decoded images of a theme. Each image is stored at full texture-canvas size.
public struct ThemeTextures: Hashable {
    public var top: RGBImage?          // 512x256 (static) or 1024x256 (scrolling), RGB565
    public var topPattern: RGBImage?   // 64x64 A8, for "Color + Pattern" mode
    public var topAltPattern: RGBImage?// 64x64 A8, second pattern layer
    public var bottom: RGBImage?       // 512x256 or 1024x256, RGB565
    public var folderClosed: RGBImage? // 128x64 BGR888
    public var folderOpen: RGBImage?   // 128x64 BGR888
    public var fileLarge: RGBImage?    // 64x128 BGR888
    public var fileSmall: RGBImage?    // 32x64 BGR888
    public init() {}

    public subscript(slot: TextureSlot) -> RGBImage? {
        get {
            switch slot {
            case .top: return top
            case .topPattern: return topPattern
            case .topAltPattern: return topAltPattern
            case .bottom: return bottom
            case .folderClosed: return folderClosed
            case .folderOpen: return folderOpen
            case .fileLarge: return fileLarge
            case .fileSmall: return fileSmall
            }
        }
        set {
            switch slot {
            case .top: top = newValue
            case .topPattern: topPattern = newValue
            case .topAltPattern: topAltPattern = newValue
            case .bottom: bottom = newValue
            case .folderClosed: folderClosed = newValue
            case .folderOpen: folderOpen = newValue
            case .fileLarge: fileLarge = newValue
            case .fileSmall: fileSmall = newValue
            }
        }
    }
}

/// Geometry helpers describing how big each image must be.
public enum ThemeGeometry {
    public static func canvasSize(_ slot: TextureSlot, flags: ThemeFlags) -> (Int, Int) {
        switch slot {
        case .top: return flags.topFrameType.scrolls ? (1024, 256) : (512, 256)
        case .bottom: return flags.bottomFrameType.isWide ? (1024, 256) : (512, 256)
        case .topPattern, .topAltPattern: return (64, 64)
        case .folderClosed, .folderOpen: return (128, 64)
        case .fileLarge: return (64, 128)
        case .fileSmall: return (32, 64)
        }
    }

    /// The part of the canvas that is actually visible on the console.
    public static func visibleSize(_ slot: TextureSlot, flags: ThemeFlags) -> (Int, Int) {
        switch slot {
        case .top: return flags.topFrameType.scrolls ? (1008, 240) : (412, 240)
        case .bottom:
            switch flags.bottomFrameType {
            case .single: return (320, 240)
            case .pageScroll, .bounceScroll: return (960, 240)
            case .slowScroll, .fastScroll: return (1008, 240)
            }
        default: return canvasSize(slot, flags: flags)
        }
    }
}

/// A complete 3DS HOME Menu theme (the contents of body_LZ.bin).
public struct Theme: Hashable {
    public var flags = ThemeFlags()
    public var colors = ThemeColors()
    public var textures = ThemeTextures()
    /// Raw sound-effect block (see `SoundEffectBlock`).
    public var soundEffectData: [UInt8] = []
    /// Use ordered dithering when converting the backgrounds to 16-bit color.
    public var ditherBackgrounds = true

    public init() {}

    // MARK: Reading

    /// Reads body_LZ.bin (compressed or already decompressed).
    public static func read(body raw: [UInt8]) throws -> Theme {
        let data = LZ11.isCompressed(raw) ? try LZ11.decompress(raw) : raw
        guard data.count >= 0xC4 else { throw ThemeKitError.invalidFormat("This body file is too small to be a theme.") }
        var r = ByteReader(data)
        guard try r.u32() == 1 else {
            throw ThemeKitError.invalidFormat("This is not a 3DS theme body (version field is not 1).")
        }
        func u32(_ o: Int) throws -> UInt32 { try r.u32(at: o) }
        func flag(_ o: Int) throws -> Bool { try u32(o) != 0 }

        var t = Theme()
        var f = ThemeFlags()
        f.backgroundMusic = data[5] != 0
        f.topDrawType = TopDrawType(rawValue: try u32(0x0C)) ?? .none
        f.topFrameType = TopFrameType(rawValue: try u32(0x10)) ?? .single
        f.bottomDrawType = BottomDrawType(rawValue: try u32(0x20)) ?? .none
        f.bottomFrameType = BottomFrameType(rawValue: try u32(0x24)) ?? .single
        f.cursorColor = try flag(0x2C)
        f.folderColor = try flag(0x34)
        f.folderTexture = try flag(0x3C)
        f.fileColor = try flag(0x48)
        f.fileTexture = try flag(0x50)
        f.arrowButtonColor = try flag(0x5C)
        f.arrowColor = try flag(0x64)
        f.openCloseColor = try flag(0x6C)
        f.gameTextDrawType = GameTextDrawType(rawValue: try u32(0x78)) ?? .standard
        f.bottomInnerColor = try flag(0x80)
        f.bottomOuterColor = try flag(0x88)
        f.folderBackgroundColor = try flag(0x90)
        f.folderArrowColor = try flag(0x98)
        f.bottomCornerColor = try flag(0xA0)
        f.topCornerColor = try flag(0xA8)
        f.demoTextColor = try flag(0xB0)
        f.soundEffects = try flag(0xB8)
        t.flags = f

        // Colors: each block is read only if its offset is valid; otherwise defaults stay.
        func at<T>(_ offsetField: Int, _ body: (inout ByteReader) throws -> T) -> T? {
            guard let off = try? Int(u32(offsetField)), off > 0, off < data.count else { return nil }
            var rr = ByteReader(data)
            rr.position = off
            return try? body(&rr)
        }
        var c = ThemeColors()
        if let v = at(0x14, { try TopBackgroundColors.read(&$0, extended: f.topDrawType == .solidColorTexture) }) { c.topBackground = v }
        if let v = at(0x30, { try CursorColors.read(&$0) }) { c.cursor = v }
        if let v = at(0x38, { try FolderColors.read(&$0) }) { c.folder = v }
        if let v = at(0x4C, { try ShadedColors.read(&$0) }) { c.file = v }
        if let v = at(0x60, { try ShadedColors.read(&$0) }) { c.arrowButton = v }
        if let v = at(0x68, { try ArrowColors.read(&$0) }) { c.arrow = v }
        if let v = at(0x70, { try OpenCloseColors.read(&$0) }) { c.open = v }
        if let v = at(0x74, { try OpenCloseColors.read(&$0) }) { c.close = v }
        if let v = at(0x7C, { try GameTextColors.read(&$0) }) { c.gameText = v }
        if let v = at(0x84, { try InnerPanelColors.read(&$0) }) { c.bottomInner = v }
        if let v = at(0x8C, { try OuterPanelColors.read(&$0) }) { c.bottomOuter = v }
        if let v = at(0x94, { try InnerPanelColors.read(&$0) }) { c.folderBackground = v }
        if let v = at(0x9C, { try FolderArrowColors.read(&$0) }) { c.folderArrow = v }
        if let v = at(0xA4, { try BottomCornerColors.read(&$0) }) { c.bottomCorner = v }
        if let v = at(0xAC, { try TopCornerColors.read(&$0) }) { c.topCorner = v }
        if let v = at(0xB4, { try DemoTextColors.read(&$0) }) { c.demoText = v }
        t.colors = c

        // Textures
        func tex(_ off: UInt32, _ w: Int, _ h: Int, _ fmt: TextureFormat) -> RGBImage? {
            let o = Int(off)
            let len = w * h * fmt.bytesPerPixel
            guard o > 0, o + len <= data.count else { return nil }
            return try? TextureCodec.decode(Array(data[o..<(o + len)]), width: w, height: h, format: fmt)
        }
        var tx = ThemeTextures()
        let topOff = try u32(0x18), topExtOff = try u32(0x1C)
        switch f.topDrawType {
        case .texture:
            let (w, h) = ThemeGeometry.canvasSize(.top, flags: f)
            tx.top = tex(topOff, w, h, .rgb565)
        case .solidColorTexture:
            tx.topPattern = tex(topOff, 64, 64, .a8)
            tx.topAltPattern = tex(topExtOff, 64, 64, .a8)
        default: break
        }
        if f.bottomDrawType == .texture {
            let (w, h) = ThemeGeometry.canvasSize(.bottom, flags: f)
            tx.bottom = tex(try u32(0x28), w, h, .rgb565)
        }
        if f.folderTexture {
            tx.folderClosed = tex(try u32(0x40), 128, 64, .bgr888)
            tx.folderOpen = tex(try u32(0x44), 128, 64, .bgr888)
        }
        if f.fileTexture {
            tx.fileLarge = tex(try u32(0x54), 64, 128, .bgr888)
            tx.fileSmall = tex(try u32(0x58), 32, 64, .bgr888)
        }
        t.textures = tx

        // Sound effects
        let sfxLen = Int(try u32(0xBC)), sfxOff = Int(try u32(0xC0))
        if sfxLen > 0, sfxOff > 0, sfxOff + sfxLen <= data.count {
            t.soundEffectData = Array(data[sfxOff..<(sfxOff + sfxLen)])
        }
        return t
    }

    // MARK: Writing

    /// Produces the decompressed theme body.
    public func writeBody() -> [UInt8] {
        var w = ByteWriter(capacity: 1_200_000)
        w.zeros(0xD0)
        let f = flags

        // Colors (all blocks are always written; flags decide whether they are used)
        let oTop = w.count; colors.topBackground.write(&w, extended: f.topDrawType == .solidColorTexture)
        let oCursor = w.count; colors.cursor.write(&w)
        let oFolder = w.count; colors.folder.write(&w)
        let oFile = w.count; colors.file.write(&w)
        let oArrowButton = w.count; colors.arrowButton.write(&w)
        let oArrow = w.count; colors.arrow.write(&w)
        let oOpen = w.count; colors.open.write(&w)
        let oClose = w.count; colors.close.write(&w)
        let oGameText = w.count; colors.gameText.write(&w)
        let oInner = w.count; colors.bottomInner.write(&w)
        let oOuter = w.count; colors.bottomOuter.write(&w)
        let oFolderBG = w.count; colors.folderBackground.write(&w)
        let oFolderArrow = w.count; colors.folderArrow.write(&w)
        let oBottomCorner = w.count; colors.bottomCorner.write(&w)
        let oTopCorner = w.count; colors.topCorner.write(&w)
        let oDemo = w.count; colors.demoText.write(&w)

        // Textures
        func fit(_ img: RGBImage, _ slot: TextureSlot) -> RGBImage {
            let (cw, ch) = ThemeGeometry.canvasSize(slot, flags: f)
            if img.width == cw && img.height == ch { return img }
            return img.cropped(width: min(img.width, cw), height: min(img.height, ch)).bled(toWidth: cw, height: ch)
        }
        var oTex = 0, oTexExt = 0, oBottom = 0, oFolderClosed = 0, oFolderOpen = 0, oFileLarge = 0, oFileSmall = 0
        var topDraw = f.topDrawType
        var bottomDraw = f.bottomDrawType
        var folderTex = f.folderTexture
        var fileTex = f.fileTexture

        switch f.topDrawType {
        case .texture:
            if let img = textures.top {
                oTex = w.count
                w.append(TextureCodec.encode(fit(img, .top), format: .rgb565, dither: ditherBackgrounds))
            } else { topDraw = .none }
        case .solidColorTexture:
            let pattern = textures.topPattern ?? ThemeDefaults.defaultPattern
            oTex = w.count
            w.append(TextureCodec.encode(fit(pattern, .topPattern), format: .a8))
            if let alt = textures.topAltPattern {
                oTexExt = w.count
                w.append(TextureCodec.encode(fit(alt, .topAltPattern), format: .a8))
            }
        default: break
        }
        if f.bottomDrawType == .texture {
            if let img = textures.bottom {
                oBottom = w.count
                w.append(TextureCodec.encode(fit(img, .bottom), format: .rgb565, dither: ditherBackgrounds))
            } else { bottomDraw = .none }
        }
        if f.folderTexture {
            if let c = textures.folderClosed, let o = textures.folderOpen {
                oFolderClosed = w.count
                w.append(TextureCodec.encode(fit(c, .folderClosed), format: .bgr888))
                oFolderOpen = w.count
                w.append(TextureCodec.encode(fit(o, .folderOpen), format: .bgr888))
            } else { folderTex = false }
        }
        if f.fileTexture {
            if let l = textures.fileLarge, let s = textures.fileSmall {
                oFileLarge = w.count
                w.append(TextureCodec.encode(fit(l, .fileLarge), format: .bgr888))
                oFileSmall = w.count
                w.append(TextureCodec.encode(fit(s, .fileSmall), format: .bgr888))
            } else { fileTex = false }
        }

        // Sound effects
        let sfx = f.soundEffects ? soundEffectData : []
        let oSfx = w.count
        w.append(sfx)
        w.pad(to: 0x10)

        // Header
        func b(_ v: Bool) -> UInt32 { v ? 1 : 0 }
        var h = ByteWriter(capacity: 0xD0)
        h.u32(1)                                  // 0x00 version
        h.u8(0)                                   // 0x04
        h.u8(f.backgroundMusic ? 1 : 0)           // 0x05 BGM flag
        h.u8(0); h.u8(0)                          // 0x06
        h.u32(0)                                  // 0x08
        h.u32(topDraw.rawValue)                   // 0x0C
        h.u32(f.topFrameType.rawValue)            // 0x10
        h.u32(oTop)                               // 0x14
        h.u32(oTex)                               // 0x18
        h.u32(oTexExt)                            // 0x1C
        h.u32(bottomDraw.rawValue)                // 0x20
        h.u32(f.bottomFrameType.rawValue)         // 0x24
        h.u32(oBottom)                            // 0x28
        h.u32(b(f.cursorColor)); h.u32(oCursor)   // 0x2C
        h.u32(b(f.folderColor)); h.u32(oFolder)   // 0x34
        h.u32(b(folderTex)); h.u32(oFolderClosed); h.u32(oFolderOpen) // 0x3C
        h.u32(b(f.fileColor)); h.u32(oFile)       // 0x48
        h.u32(b(fileTex)); h.u32(oFileLarge); h.u32(oFileSmall)       // 0x50
        h.u32(b(f.arrowButtonColor)); h.u32(oArrowButton)              // 0x5C
        h.u32(b(f.arrowColor)); h.u32(oArrow)     // 0x64
        h.u32(b(f.openCloseColor)); h.u32(oOpen); h.u32(oClose)        // 0x6C
        h.u32(f.gameTextDrawType.rawValue); h.u32(oGameText)           // 0x78
        h.u32(b(f.bottomInnerColor)); h.u32(oInner)                    // 0x80
        h.u32(b(f.bottomOuterColor)); h.u32(oOuter)                    // 0x88
        h.u32(b(f.folderBackgroundColor)); h.u32(oFolderBG)            // 0x90
        h.u32(b(f.folderArrowColor)); h.u32(oFolderArrow)              // 0x98
        h.u32(b(f.bottomCornerColor)); h.u32(oBottomCorner)            // 0xA0
        h.u32(b(f.topCornerColor)); h.u32(oTopCorner)                  // 0xA8
        h.u32(b(f.demoTextColor)); h.u32(oDemo)                        // 0xB0
        h.u32(b(f.soundEffects && !sfx.isEmpty)); h.u32(sfx.count); h.u32(oSfx) // 0xB8
        precondition(h.count == 0xC4)

        var out = w.bytes
        out.replaceSubrange(0..<h.count, with: h.bytes)
        return out
    }

    /// Produces the compressed body_LZ.bin.
    public func writeCompressedBody() -> [UInt8] {
        LZ11.compress(writeBody())
    }
}

public enum ThemeDefaults {
    /// A soft diagonal-stripe pattern used when "Color + Pattern" has no pattern image yet.
    public static let defaultPattern: RGBImage = {
        var img = RGBImage(width: 64, height: 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let v: UInt8 = ((x + y) / 8) % 2 == 0 ? 255 : 90
                img.setPixel(x, y, RGB(v, v, v))
            }
        }
        return img
    }()
}
