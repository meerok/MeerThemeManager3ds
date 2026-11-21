import Foundation

// MARK: - Colors

public struct RGB: Codable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    static func read(_ r: inout ByteReader) throws -> RGB { RGB(try r.u8(), try r.u8(), try r.u8()) }
    func write(_ w: inout ByteWriter) { w.u8(r); w.u8(g); w.u8(b) }
}

public struct RGBA: Codable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) { self.r = r; self.g = g; self.b = b; self.a = a }

    public var rgb: RGB {
        get { RGB(r, g, b) }
        set { r = newValue.r; g = newValue.g; b = newValue.b }
    }

    static func read(_ r: inout ByteReader) throws -> RGBA { RGBA(try r.u8(), try r.u8(), try r.u8(), try r.u8()) }
    func write(_ w: inout ByteWriter) { w.u8(r); w.u8(g); w.u8(b); w.u8(a) }
}

// MARK: - Enumerations (values match the file format)

public enum TopDrawType: UInt32, Codable, CaseIterable, Identifiable {
    case none = 0, solidColor = 1, solidColorTexture = 2, texture = 3
    public var id: UInt32 { rawValue }
}

public enum TopFrameType: UInt32, Codable, CaseIterable, Identifiable {
    case fastScroll = 0, single = 1, slowScroll = 3
    public var id: UInt32 { rawValue }
    public var scrolls: Bool { self != .single }
}

public enum BottomDrawType: UInt32, Codable, CaseIterable, Identifiable {
    case none = 0, solidColor = 1, texture = 3
    public var id: UInt32 { rawValue }
}

public enum BottomFrameType: UInt32, Codable, CaseIterable, Identifiable {
    case fastScroll = 0, single = 1, pageScroll = 2, slowScroll = 3, bounceScroll = 4
    public var id: UInt32 { rawValue }
    public var isWide: Bool { self != .single }
}

public enum GameTextDrawType: UInt32, Codable, CaseIterable, Identifiable {
    case standard = 0, colored = 1, hidden = 2
    public var id: UInt32 { rawValue }
}

// MARK: - Color sets (field order in `read`/`write` matches the binary layout)

public struct TopBackgroundColors: Codable, Hashable {
    /// Stored at full 0–255 precision; written to the file as 0–100 percentages.
    public var main = RGB(204, 204, 217)
    public var gradient: UInt8 = 64
    public var textureOpacity: UInt8 = 128
    public var alternateOpacity: UInt8 = 128
    public var gradientColor: UInt8 = 255

    public init() {}

    private static func inflate(_ v: UInt8) -> UInt8 { UInt8(min(255, Int(v) * 255 / 100)) }
    private static func deflate(_ v: UInt8) -> UInt8 { UInt8(min(100, Int(v) * 100 / 255)) }

    static func read(_ r: inout ByteReader, extended: Bool) throws -> TopBackgroundColors {
        var c = TopBackgroundColors()
        let m = try RGB.read(&r)
        c.main = RGB(inflate(m.r), inflate(m.g), inflate(m.b))
        c.gradient = inflate(try r.u8())
        c.textureOpacity = inflate(try r.u8())
        if extended {
            c.alternateOpacity = inflate(try r.u8())
            c.gradientColor = inflate(try r.u8())
        }
        return c
    }

    func write(_ w: inout ByteWriter, extended: Bool) {
        RGB(Self.deflate(main.r), Self.deflate(main.g), Self.deflate(main.b)).write(&w)
        w.u8(Self.deflate(gradient))
        w.u8(Self.deflate(textureOpacity))
        if extended {
            w.u8(Self.deflate(alternateOpacity))
            w.u8(Self.deflate(gradientColor))
        }
    }
}

public struct CursorColors: Codable, Hashable {
    public var shading = RGB(8, 110, 180)
    public var main = RGB(28, 176, 255)
    public var light = RGB(150, 222, 255)
    public var glow = RGB(70, 200, 255)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.shading = try .read(&r); c.main = try .read(&r); c.light = try .read(&r); c.glow = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { shading.write(&w); main.write(&w); light.write(&w); glow.write(&w) }
}

public struct FolderColors: Codable, Hashable {
    public var shading = RGB(196, 142, 26)
    public var main = RGB(250, 206, 82)
    public var light = RGB(255, 236, 160)
    public var shadow = RGB(110, 80, 20)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.shading = try .read(&r); c.main = try .read(&r); c.light = try .read(&r); c.shadow = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { shading.write(&w); main.write(&w); light.write(&w); shadow.write(&w) }
}

/// Used for 3D file icons ("File") and the left/right arrow buttons.
public struct ShadedColors: Codable, Hashable {
    public var shading = RGB(176, 176, 186)
    public var main = RGB(238, 238, 242)
    public var light = RGB(255, 255, 255)
    public var shadow = RGBA(0, 0, 0, 64)
    public init() {}
    public init(shading: RGB, main: RGB, light: RGB, shadow: RGBA) {
        self.shading = shading; self.main = main; self.light = light; self.shadow = shadow
    }
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.shading = try .read(&r); c.main = try .read(&r); c.light = try .read(&r); c.shadow = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { shading.write(&w); main.write(&w); light.write(&w); shadow.write(&w) }
}

public struct ArrowColors: Codable, Hashable {
    public var border = RGB(90, 90, 104)
    public var unpressed = RGB(140, 140, 152)
    public var pressed = RGB(28, 176, 255)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.border = try .read(&r); c.unpressed = try .read(&r); c.pressed = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { border.write(&w); unpressed.write(&w); pressed.write(&w) }
}

/// The "Open" / "Close" buttons shown on the bottom screen.
public struct OpenCloseColors: Codable, Hashable {
    public var textShadowPosition: Float = -1.25
    public var pressed = RGB(200, 200, 208)
    public var unpressed = RGB(245, 245, 248)
    public var light = RGB(255, 255, 255)
    public var shadow = RGBA(0, 0, 0, 80)
    public var glow = RGB(255, 255, 255)
    public var textShadow = RGB(255, 255, 255)
    public var textUnpressed = RGB(60, 60, 70)
    public var textPressed = RGB(28, 140, 230)
    var padding = RGB(0, 0, 0)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self()
        c.textShadowPosition = try r.f32()
        c.pressed = try .read(&r); c.unpressed = try .read(&r); c.light = try .read(&r)
        c.shadow = try .read(&r); c.glow = try .read(&r); c.textShadow = try .read(&r)
        c.textUnpressed = try .read(&r); c.textPressed = try .read(&r); c.padding = try .read(&r)
        return c
    }
    func write(_ w: inout ByteWriter) {
        w.f32(textShadowPosition)
        pressed.write(&w); unpressed.write(&w); light.write(&w); shadow.write(&w); glow.write(&w)
        textShadow.write(&w); textUnpressed.write(&w); textPressed.write(&w); padding.write(&w)
    }
}

/// Software title banner shown on the top screen.
public struct GameTextColors: Codable, Hashable {
    public var main = RGB(250, 250, 252)
    public var light = RGB(255, 255, 255)
    public var shadow = RGBA(0, 0, 0, 60)
    public var text = RGB(50, 50, 60)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.main = try .read(&r); c.light = try .read(&r); c.shadow = try .read(&r); c.text = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { main.write(&w); light.write(&w); shadow.write(&w); text.write(&w) }
}

/// Bottom screen inner panel (also used for the folder background).
public struct InnerPanelColors: Codable, Hashable {
    public var highlight = RGB(127, 127, 127)
    public var main = RGB(223, 220, 215)
    public var border = RGB(234, 234, 234)
    public var glow = RGBA(63, 63, 63, 255)
    public init() {}
    public init(highlight: RGB, main: RGB, border: RGB, glow: RGBA) {
        self.highlight = highlight; self.main = main; self.border = border; self.glow = glow
    }
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.highlight = try .read(&r); c.main = try .read(&r); c.border = try .read(&r); c.glow = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { highlight.write(&w); main.write(&w); border.write(&w); glow.write(&w) }
}

/// Bottom screen outer area (the frame around the inner panel).
public struct OuterPanelColors: Codable, Hashable {
    public var stripes = RGB(208, 208, 216)
    public var main = RGB(226, 226, 234)
    public var glow = RGB(227, 228, 233)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.stripes = try .read(&r); c.main = try .read(&r); c.glow = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { stripes.write(&w); main.write(&w); glow.write(&w) }
}

/// The back arrow / arrow buttons shown while inside a folder.
public struct FolderArrowColors: Codable, Hashable {
    public var arrowShadowPosition: Float = -1.25
    public var shading = RGB(200, 200, 208)
    public var main = RGB(245, 245, 248)
    public var highlight = RGB(255, 255, 255)
    public var shadow = RGBA(0, 0, 0, 100)
    public var glow = RGB(255, 255, 255)
    public var arrowGlow = RGB(255, 255, 255)
    public var arrowUnpressed = RGB(90, 90, 104)
    public var arrowPressed = RGB(28, 140, 230)
    var padding = RGB(0, 0, 0)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self()
        c.arrowShadowPosition = try r.f32()
        c.shading = try .read(&r); c.main = try .read(&r); c.highlight = try .read(&r)
        c.shadow = try .read(&r); c.glow = try .read(&r); c.arrowGlow = try .read(&r)
        c.arrowUnpressed = try .read(&r); c.arrowPressed = try .read(&r); c.padding = try .read(&r)
        return c
    }
    func write(_ w: inout ByteWriter) {
        w.f32(arrowShadowPosition)
        shading.write(&w); main.write(&w); highlight.write(&w); shadow.write(&w); glow.write(&w)
        arrowGlow.write(&w); arrowUnpressed.write(&w); arrowPressed.write(&w); padding.write(&w)
    }
}

/// Bottom-left / bottom-right corner buttons on the bottom screen.
public struct BottomCornerColors: Codable, Hashable {
    public var border = RGB(170, 170, 180)
    public var main = RGB(240, 240, 244)
    public var highlight = RGB(255, 255, 255)
    public var baseShadow = RGB(39, 35, 49)
    public var iconBottom = RGB(110, 110, 124)
    public var iconTop = RGB(150, 150, 164)
    public var iconText = RGB(39, 35, 49)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self()
        c.border = try .read(&r); c.main = try .read(&r); c.highlight = try .read(&r); c.baseShadow = try .read(&r)
        c.iconBottom = try .read(&r); c.iconTop = try .read(&r); c.iconText = try .read(&r)
        return c
    }
    func write(_ w: inout ByteWriter) {
        border.write(&w); main.write(&w); highlight.write(&w); baseShadow.write(&w)
        iconBottom.write(&w); iconTop.write(&w); iconText.write(&w)
    }
}

/// Top-left / top-right corner buttons on the bottom screen.
public struct TopCornerColors: Codable, Hashable {
    public var main = RGB(240, 240, 244)
    public var light = RGB(244, 226, 245)
    public var shadow = RGB(39, 35, 49)
    public var text = RGB(60, 60, 70)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.main = try .read(&r); c.light = try .read(&r); c.shadow = try .read(&r); c.text = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { main.write(&w); light.write(&w); shadow.write(&w); text.write(&w) }
}

/// Text box shown on the top screen when demo/“tips” text is displayed.
public struct DemoTextColors: Codable, Hashable {
    public var main = RGB(250, 250, 252)
    public var text = RGB(50, 50, 60)
    public init() {}
    static func read(_ r: inout ByteReader) throws -> Self {
        var c = Self(); c.main = try .read(&r); c.text = try .read(&r); return c
    }
    func write(_ w: inout ByteWriter) { main.write(&w); text.write(&w) }
}

/// All theme colors.
public struct ThemeColors: Codable, Hashable {
    public var topBackground = TopBackgroundColors()
    public var cursor = CursorColors()
    public var folder = FolderColors()
    public var file = ShadedColors()
    public var arrowButton = ShadedColors(shading: RGB(190, 190, 200), main: RGB(242, 242, 246), light: RGB(255, 255, 255), shadow: RGBA(0, 0, 0, 64))
    public var arrow = ArrowColors()
    public var open = OpenCloseColors()
    public var close: OpenCloseColors = { var c = OpenCloseColors(); c.textShadowPosition = 1.0; return c }()
    public var gameText = GameTextColors()
    public var bottomInner = InnerPanelColors()
    public var bottomOuter = OuterPanelColors()
    public var folderBackground = InnerPanelColors()
    public var folderArrow = FolderArrowColors()
    public var bottomCorner = BottomCornerColors()
    public var topCorner = TopCornerColors()
    public var demoText = DemoTextColors()
    public init() {}
}

/// Header flags. Each `...Color` flag tells the home menu to use the matching custom color set.
public struct ThemeFlags: Codable, Hashable {
    public var backgroundMusic = false
    public var topDrawType: TopDrawType = .none
    public var topFrameType: TopFrameType = .single
    public var bottomDrawType: BottomDrawType = .none
    public var bottomFrameType: BottomFrameType = .single
    public var cursorColor = false
    public var folderColor = false
    public var folderTexture = false
    public var fileColor = false
    public var fileTexture = false
    public var arrowButtonColor = false
    public var arrowColor = false
    public var openCloseColor = false
    public var gameTextDrawType: GameTextDrawType = .standard
    public var bottomInnerColor = false
    public var bottomOuterColor = false
    public var folderBackgroundColor = false
    public var folderArrowColor = false
    public var bottomCornerColor = false
    public var topCornerColor = false
    public var demoTextColor = false
    public var soundEffects = false
    public init() {}
}
