import SwiftUI
import ThemeKit

/// Which HOME Menu screen the live preview shows.
enum PreviewMode: String, CaseIterable, Identifiable {
    case home, folder, zoom, paused
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .folder: return "Folder"
        case .zoom: return "Big Icons"
        case .paused: return "Suspended"
        }
    }
    /// The view that shows what an editor page changes, if any.
    static func forSection(_ s: EditorSection?) -> PreviewMode? {
        switch s {
        case .icons?, .buttons?, .top?, .bottom?: return .home
        case .folderView?: return .folder
        case .text?: return .zoom
        default: return nil
        }
    }
}

/// Draws the 3DS HOME Menu with the theme's colors and pictures, laid out like the real console.
/// Coordinates are console pixels: top screen 412×240 (including 3D margins), bottom 320×240.
struct PreviewRenderer {
    let theme: Theme
    let images: [TextureSlot: CGImage]
    let icon: CGImage?
    var mode: PreviewMode = .home
    var title: String = "My Theme"
    let time: Double
    let forExport: Bool
    var clock = Date()

    static let topSize = CGSize(width: 412, height: 240)
    static let bottomSize = CGSize(width: 320, height: 240)

    private var f: ThemeFlags { theme.flags }
    private var c: ThemeColors { theme.colors }
    private var shownTitle: String { title.isEmpty ? "My Theme" : title }

    // MARK: What the console looks like when a color group is switched off

    private enum Real {
        static let cursor: CursorColors = { var c = CursorColors(); c.shading = RGB(51, 225, 154); c.main = RGB(57, 237, 166); c.light = RGB(170, 255, 222); c.glow = RGB(57, 237, 166); return c }()
        static let folder: FolderColors = { var c = FolderColors(); c.shading = RGB(70, 132, 150); c.main = RGB(101, 168, 187); c.light = RGB(146, 225, 238); c.shadow = RGB(0, 0, 0); return c }()
        static let file = ShadedColors(shading: RGB(208, 208, 208), main: RGB(246, 246, 246), light: RGB(252, 252, 252), shadow: RGBA(0, 0, 0, 70))
        static let arrowButton = ShadedColors(shading: RGB(206, 206, 206), main: RGB(240, 240, 240), light: RGB(255, 255, 255), shadow: RGBA(0, 0, 0, 70))
        static let arrow: ArrowColors = { var c = ArrowColors(); c.border = RGB(151, 181, 176); c.unpressed = RGB(161, 192, 186); c.pressed = RGB(177, 255, 240); return c }()
        static let open: OpenCloseColors = {
            var c = OpenCloseColors(); c.textShadowPosition = -1.25; c.pressed = RGB(160, 156, 152); c.unpressed = RGB(189, 185, 181); c.light = RGB(230, 227, 223)
            c.shadow = RGBA(0, 0, 0, 60); c.glow = RGB(240, 238, 234); c.textShadow = RGB(239, 237, 233); c.textUnpressed = RGB(61, 61, 61); c.textPressed = RGB(40, 40, 40); return c
        }()
        static let close: OpenCloseColors = {
            var c = OpenCloseColors(); c.textShadowPosition = 1; c.pressed = RGB(60, 58, 52); c.unpressed = RGB(75, 72, 65); c.light = RGB(88, 85, 78)
            c.shadow = RGBA(0, 0, 0, 60); c.glow = RGB(134, 131, 124); c.textShadow = RGB(90, 90, 90); c.textUnpressed = RGB(239, 237, 233); c.textPressed = RGB(200, 200, 200); return c
        }()
        static let gameText: GameTextColors = { var c = GameTextColors(); c.main = RGB(250, 250, 250); c.light = RGB(255, 255, 255); c.shadow = RGBA(0, 0, 0, 60); c.text = RGB(61, 61, 61); return c }()
        static let inner: InnerPanelColors = { var c = InnerPanelColors(); c.highlight = RGB(127, 127, 127); c.main = RGB(223, 220, 215); c.border = RGB(234, 234, 234); c.glow = RGBA(63, 63, 63, 255); return c }()
        static let outer: OuterPanelColors = { var c = OuterPanelColors(); c.stripes = RGB(208, 208, 216); c.main = RGB(226, 226, 234); c.glow = RGB(227, 228, 233); return c }()
        static let folderArrow: FolderArrowColors = {
            var c = FolderArrowColors(); c.arrowShadowPosition = -1.25; c.shading = RGB(43, 45, 42); c.main = RGB(78, 75, 68); c.highlight = RGB(140, 135, 129); c.shadow = RGBA(0, 0, 0, 90)
            c.glow = RGB(120, 116, 110); c.arrowGlow = RGB(0, 0, 0); c.arrowUnpressed = RGB(255, 255, 255); c.arrowPressed = RGB(187, 187, 187); return c
        }()
        static let bottomCorner: BottomCornerColors = {
            var c = BottomCornerColors(); c.border = RGB(220, 220, 220); c.main = RGB(233, 233, 234); c.highlight = RGB(250, 250, 250); c.baseShadow = RGB(0, 0, 0)
            c.iconBottom = RGB(130, 156, 196); c.iconTop = RGB(149, 176, 211); c.iconText = RGB(149, 176, 211); return c
        }()
        static let topCorner: TopCornerColors = { var c = TopCornerColors(); c.main = RGB(255, 255, 255); c.light = RGB(255, 255, 255); c.shadow = RGB(0, 0, 0); c.text = RGB(61, 61, 61); return c }()
    }

    private var cursorC: CursorColors { f.cursorColor ? c.cursor : Real.cursor }
    private var folderC: FolderColors { f.folderColor ? c.folder : Real.folder }
    private var fileC: ShadedColors { f.fileColor ? c.file : Real.file }
    private var arrowButtonC: ShadedColors { f.arrowButtonColor ? c.arrowButton : Real.arrowButton }
    private var arrowC: ArrowColors { f.arrowColor ? c.arrow : Real.arrow }
    private var openC: OpenCloseColors { f.openCloseColor ? c.open : Real.open }
    private var closeC: OpenCloseColors { f.openCloseColor ? c.close : Real.close }
    private var gameTextC: GameTextColors { f.gameTextDrawType == .colored ? c.gameText : Real.gameText }
    private var innerC: InnerPanelColors { f.bottomDrawType == .solidColor && f.bottomInnerColor ? c.bottomInner : Real.inner }
    private var outerC: OuterPanelColors { f.bottomDrawType == .solidColor && f.bottomOuterColor ? c.bottomOuter : Real.outer }
    private var folderBgC: InnerPanelColors { f.folderBackgroundColor ? c.folderBackground : Real.inner }
    private var folderArrowC: FolderArrowColors { f.folderArrowColor ? c.folderArrow : Real.folderArrow }
    private var bottomCornerC: BottomCornerColors { f.bottomCornerColor ? c.bottomCorner : Real.bottomCorner }
    private var topCornerC: TopCornerColors { f.topCornerColor ? c.topCorner : Real.topCorner }

    // MARK: Helpers

    private func cl(_ v: RGB, _ a: Double = 1) -> Color { Color(.sRGB, red: Double(v.r) / 255, green: Double(v.g) / 255, blue: Double(v.b) / 255, opacity: a) }
    private func ca(_ v: RGBA, _ k: Double = 1) -> Color { Color(.sRGB, red: Double(v.r) / 255, green: Double(v.g) / 255, blue: Double(v.b) / 255, opacity: Double(v.a) / 255 * k) }
    private func hex(_ v: UInt32, _ a: Double = 1) -> Color { Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a) }
    private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(x) * (1 - t) + Double(y) * t).rounded()))) }
        return RGB(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b))
    }
    private var white: RGB { RGB(255, 255, 255) }
    private var black: RGB { RGB(0, 0, 0) }

    private func grad(_ stops: [(Double, Color)], _ p0: CGPoint, _ p1: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) }), startPoint: p0, endPoint: p1)
    }
    private func vgrad(_ stops: [(Double, Color)], _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading { grad(stops, CGPoint(x: 0, y: y0), CGPoint(x: 0, y: y1)) }
    private func hgrad(_ stops: [(Double, Color)], _ x0: CGFloat, _ x1: CGFloat) -> GraphicsContext.Shading { grad(stops, CGPoint(x: x0, y: 0), CGPoint(x: x1, y: 0)) }
    private func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path { Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r) }
    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)).applying(CGAffineTransform(rotationAngle: rotation).concatenating(CGAffineTransform(translationX: x, y: y)))
    }
    private func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }; p.closeSubpath(); return p
    }
    private func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path { var p = Path(); p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1)); return p }
    private func shadowed(_ ctx: GraphicsContext, _ color: Color, _ blur: CGFloat, _ dx: CGFloat, _ dy: CGFloat) -> GraphicsContext {
        var s = ctx; s.addFilter(.shadow(color: color, radius: blur / 2, x: dx, y: dy)); return s
    }
    private func label(_ s: String, _ size: CGFloat, _ color: Color, _ weight: Font.Weight = .heavy) -> Text {
        Text(s).font(.system(size: size, weight: weight, design: .rounded)).foregroundColor(color)
    }
    private func outlined(_ ctx: inout GraphicsContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ fill: Color, _ anchor: UnitPoint = .center) {
        let halo = label(s, size, .white)
        for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-0.8, -0.8), (0.8, 0.8), (-0.8, 0.8), (0.8, -0.8)] {
            ctx.draw(halo, at: CGPoint(x: x + dx, y: y + dy), anchor: anchor)
        }
        ctx.draw(label(s, size, fill), at: CGPoint(x: x, y: y), anchor: anchor)
    }
    private func fitted(_ ctx: GraphicsContext, _ s: String, _ maxW: CGFloat, _ size: CGFloat) -> String {
        func width(_ t: String) -> CGFloat { ctx.resolve(label(t, size, .black)).measure(in: CGSize(width: 2000, height: 100)).width }
        if width(s) <= maxW { return s }
        var t = s
        while t.count > 1 && width(t + "…") > maxW { t.removeLast() }
        return t + "…"
    }
    private func drawImage(_ ctx: inout GraphicsContext, _ img: CGImage, in r: CGRect) { ctx.draw(Image(decorative: img, scale: 1), in: r) }

    // MARK: App artwork (original designs, drawn in a 38×38 box centered on 0,0)

    private func appBackground(_ ctx: inout GraphicsContext, _ top: RGB, _ bottom: RGB) {
        ctx.fill(Path(CGRect(x: -19, y: -19, width: 38, height: 38)), with: vgrad([(0, cl(top)), (1, cl(bottom))], -19, 19))
        ctx.fill(ellipse(0, -19, 30, 17), with: .color(.white.opacity(0.22)))
    }

    private func drawArt(_ ctx: inout GraphicsContext, _ kind: String) {
        var a = ctx
        a.clip(to: rr(-19, -19, 38, 38, 3))
        let w = Color.white
        switch kind {
        case "theme":
            a.fill(Path(CGRect(x: -19, y: -19, width: 38, height: 38)), with: .color(hex(0x4B6BF5)))
            if let icon { drawImage(&a, icon, in: CGRect(x: -19, y: -19, width: 38, height: 38)) }
        case "settings":
            appBackground(&a, RGB(176, 182, 192), RGB(104, 110, 122))
            a.fill(poly((0..<16).map { i in let ang = Double(i) / 16 * .pi * 2, r: Double = i % 2 == 1 ? 9 : 12; return (CGFloat(cos(ang) * r), CGFloat(sin(ang) * r)) }), with: .color(w))
            a.fill(circle(0, 0, 4.5), with: .color(cl(RGB(128, 134, 146))))
        case "camera":
            appBackground(&a, RGB(70, 74, 84), RGB(30, 32, 38))
            a.fill(rr(-13, -7, 26, 18, 4), with: .color(hex(0xE8E8EC))); a.fill(rr(-5, -11, 10, 5, 2), with: .color(hex(0xE8E8EC)))
            a.fill(circle(0, 2, 6.5), with: .color(hex(0x2C2F36))); a.fill(circle(0, 2, 3.6), with: .color(hex(0x5AB0FF))); a.fill(circle(-1.2, 0.8, 1.1), with: .color(w))
        case "music":
            appBackground(&a, RGB(255, 172, 64), RGB(232, 104, 24))
            a.fill(ellipse(-6, 8, 4.6, 3.6, rotation: -0.4), with: .color(w)); a.fill(ellipse(7, 5, 4.6, 3.6, rotation: -0.4), with: .color(w))
            a.fill(Path(CGRect(x: -2.3, y: -11, width: 2.6, height: 19)), with: .color(w)); a.fill(Path(CGRect(x: 10.7, y: -14, width: 2.6, height: 19)), with: .color(w))
            a.fill(poly([(-2.3, -11), (13.3, -14), (13.3, -9), (-2.3, -6)]), with: .color(w))
        case "browser":
            appBackground(&a, RGB(86, 170, 255), RGB(28, 98, 214))
            a.stroke(circle(0, 0, 11), with: .color(w), lineWidth: 2)
            var p = ellipse(0, 0, 5, 11); p.addPath(line(-11, 0, 11, 0)); p.addPath(line(-9, -6, 9, -6)); p.addPath(line(-9, 6, 9, 6))
            a.stroke(p, with: .color(w), lineWidth: 1.4)
        case "shop":
            appBackground(&a, RGB(120, 214, 110), RGB(40, 150, 64))
            a.fill(rr(-11, -5, 22, 17, 3), with: .color(w))
            var h = Path(); h.addArc(center: CGPoint(x: 0, y: -5), radius: 6, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            a.stroke(h, with: .color(w), lineWidth: 2.2)
            a.fill(circle(0, 3.5, 3), with: .color(cl(RGB(40, 150, 64))))
        case "mail":
            appBackground(&a, RGB(90, 222, 214), RGB(18, 150, 160))
            a.fill(rr(-12, -8, 24, 17, 2.5), with: .color(w))
            var v = Path(); v.move(to: CGPoint(x: -11, y: -7)); v.addLine(to: CGPoint(x: 0, y: 2)); v.addLine(to: CGPoint(x: 11, y: -7))
            a.stroke(v, with: .color(cl(RGB(18, 150, 160))), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        case "heart":
            appBackground(&a, RGB(255, 140, 170), RGB(222, 60, 110))
            var h = Path(); h.move(to: CGPoint(x: 0, y: 11))
            h.addCurve(to: CGPoint(x: 0, y: -5), control1: CGPoint(x: -16, y: 0), control2: CGPoint(x: -9, y: -14))
            h.addCurve(to: CGPoint(x: 0, y: 11), control1: CGPoint(x: 9, y: -14), control2: CGPoint(x: 16, y: 0))
            a.fill(h, with: .color(w))
        case "download":
            appBackground(&a, RGB(255, 214, 70), RGB(236, 160, 20))
            a.fill(Path(CGRect(x: -3, y: -12, width: 6, height: 12)), with: .color(w)); a.fill(poly([(-9, -1), (9, -1), (0, 9)]), with: .color(w)); a.fill(rr(-12, 10, 24, 3, 1.5), with: .color(w))
        default: // "game"
            appBackground(&a, RGB(196, 120, 255), RGB(112, 48, 196))
            a.fill(poly((0..<10).map { i in let ang = -Double.pi / 2 + Double(i) * .pi / 5, r: Double = i % 2 == 1 ? 5.2 : 12; return (CGFloat(cos(ang) * r), CGFloat(sin(ang) * r + 1)) }), with: .color(w))
        }
        ctx.stroke(rr(-18.6, -18.6, 37.2, 37.2, 3), with: .color(.black.opacity(0.14)), lineWidth: 0.75)
    }

    // MARK: Grid pieces (drawn centered on 0,0 at icon scale)

    /// The frame every app icon sits in (the "file" colors / picture).
    private func drawFileFrame(_ ctx: inout GraphicsContext) {
        let fc = fileC, frame = rr(-24, -24, 48, 48, 8)
        shadowed(ctx, ca(fc.shadow), 4, 0, 2).fill(frame, with: .color(cl(fc.main)))
        if f.fileTexture, let tex = images[.fileLarge], let half = tex.cropping(to: CGRect(x: 1, y: 1, width: 34, height: 69)) {
            // The picture holds the left half of the frame; the console mirrors it for the right half.
            var t = ctx; t.clip(to: frame)
            drawImage(&t, half, in: CGRect(x: -24, y: -24, width: 24, height: 48))
            t.scaleBy(x: -1, y: 1); drawImage(&t, half, in: CGRect(x: -24, y: -24, width: 24, height: 48))
            return
        }
        var b = ctx; b.clip(to: frame)
        b.stroke(frame, with: vgrad([(0, cl(fc.light)), (1, cl(fc.shading))], -24, 24), lineWidth: 3.2)
        ctx.stroke(rr(-23.6, -23.6, 47.2, 47.2, 7.8), with: .color(cl(fc.shading, 0.9)), lineWidth: 0.8)
    }

    /// The game card slot with no card inserted (not affected by themes).
    private func drawCardSlot(_ ctx: inout GraphicsContext) {
        shadowed(ctx, .black.opacity(0.18), 3, 0, 1.5).fill(rr(-24, -24, 48, 48, 8), with: .color(hex(0xE0E0DE)))
        var card = Path()
        card.move(to: CGPoint(x: -12, y: -16)); card.addLine(to: CGPoint(x: 9, y: -16)); card.addLine(to: CGPoint(x: 14, y: -11)); card.addLine(to: CGPoint(x: 14, y: 16)); card.addLine(to: CGPoint(x: -12, y: 16))
        card.addQuadCurve(to: CGPoint(x: -14, y: 14), control: CGPoint(x: -14, y: 16)); card.addLine(to: CGPoint(x: -14, y: -14)); card.addQuadCurve(to: CGPoint(x: -12, y: -16), control: CGPoint(x: -14, y: -16)); card.closeSubpath()
        ctx.fill(card, with: .color(hex(0xD3D3D1))); ctx.stroke(card, with: .color(hex(0xB9B9B7)), lineWidth: 1)
        ctx.fill(rr(-9, -11, 18, 15, 2), with: .color(hex(0xE0E0DE)))
        for i in 0..<5 { ctx.fill(Path(CGRect(x: -8 + CGFloat(i) * 4, y: 9, width: 2.4, height: 5)), with: .color(hex(0xC4C4C2))) }
    }

    private static let folderBack: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -24, y: 0)); p.addLine(to: CGPoint(x: -24, y: -17))
        p.addArc(tangent1End: CGPoint(x: -24, y: -20), tangent2End: CGPoint(x: -21, y: -20), radius: 3)
        p.addLine(to: CGPoint(x: -5, y: -20)); p.addLine(to: CGPoint(x: -3, y: -17)); p.addLine(to: CGPoint(x: 21, y: -17))
        p.addArc(tangent1End: CGPoint(x: 24, y: -17), tangent2End: CGPoint(x: 24, y: -14), radius: 3)
        p.addLine(to: CGPoint(x: 24, y: 0)); p.closeSubpath(); return p
    }()
    private static let folderFrontClosed = Path(roundedRect: CGRect(x: -24, y: -14, width: 48, height: 36), cornerRadius: 3)
    private static let folderFrontOpen: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -21, y: -6)); p.addLine(to: CGPoint(x: 21, y: -6)); p.addQuadCurve(to: CGPoint(x: 24, y: -3), control: CGPoint(x: 24, y: -6))
        p.addLine(to: CGPoint(x: 21, y: 19)); p.addQuadCurve(to: CGPoint(x: 18, y: 22), control: CGPoint(x: 21, y: 22)); p.addLine(to: CGPoint(x: -18, y: 22))
        p.addQuadCurve(to: CGPoint(x: -21, y: 19), control: CGPoint(x: -21, y: 22)); p.addLine(to: CGPoint(x: -24, y: -3)); p.addQuadCurve(to: CGPoint(x: -21, y: -6), control: CGPoint(x: -24, y: -6))
        p.closeSubpath(); return p
    }()
    private static let folderWhole: Path = { var p = folderBack; p.addPath(folderFrontClosed); return p }()

    /// A HOME Menu folder icon; open shows the front flap tipped forward.
    private func drawFolderIcon(_ ctx: inout GraphicsContext, open: Bool) {
        let fc = folderC, front = open ? Self.folderFrontOpen : Self.folderFrontClosed
        if f.folderTexture, let tex = images[open ? .folderOpen : .folderClosed],
           let part = tex.cropping(to: CGRect(x: 0, y: 0, width: open ? 82 : 74, height: 64)) {
            shadowed(ctx, cl(fc.shadow, 0.45), 4, 0, 2).fill(Self.folderWhole, with: .color(cl(fc.main)))
            var t = ctx; t.clip(to: Self.folderWhole)
            drawImage(&t, part, in: CGRect(x: -24, y: -20, width: 48, height: 42))
            return
        }
        shadowed(ctx, cl(fc.shadow, 0.45), 4, 0, 2).fill(Self.folderBack, with: vgrad([(0, cl(mix(fc.main, white, 0.25))), (1, cl(fc.shading))], -20, 0))
        var peek = ctx; peek.clip(to: Path(CGRect(x: -20, y: -23, width: 40, height: open ? 18 : 9)))
        let fl = fileC
        peek.fill(rr(-15, -17, 30, 36, 4), with: .color(cl(fl.main))); peek.stroke(rr(-15, -17, 30, 36, 4), with: .color(cl(fl.shading)), lineWidth: 1)
        shadowed(ctx, cl(fc.shadow, 0.3), 2, 0, open ? 2 : 1).fill(front, with: vgrad([(0, cl(fc.light)), (1, cl(fc.main))], open ? -6 : -14, 22))
        ctx.stroke(front, with: .color(cl(fc.shading)), lineWidth: 0.9)
        let y: CGFloat = open ? -4.5 : -12.5
        ctx.stroke(line(-20, y, 20, y), with: .color(cl(mix(fc.light, white, 0.5), 0.8)), lineWidth: 0.8)
    }

    /// The four-corner selection cursor, pulsing like the console's.
    private func drawCursor(_ ctx: inout GraphicsContext) {
        let cc = cursorC, t = forExport ? 0.5 : (sin(time * .pi * 2) + 1) / 2, k = 1 + 0.05 * t
        var g = ctx; g.scaleBy(x: k, y: k)
        var keep = Path(); keep.addRect(CGRect(x: -40, y: -40, width: 80, height: 80)); keep.addPath(poly([(0, -38.2), (-38.2, 0), (0, 38.2), (38.2, 0)]))
        g.clip(to: keep, style: FillStyle(eoFill: true))
        var ring = rr(-27, -27, 54, 54, 6); ring.addPath(rr(-23, -23, 46, 46, 4))
        let eo = FillStyle(eoFill: true)
        shadowed(g, cl(cc.glow, 0.95), 5 + 5 * t, 0, 0).fill(ring, with: .color(cl(cc.glow, 0.35 + 0.6 * t)), style: eo)
        g.fill(ring, with: vgrad([(0, cl(mix(cc.main, cc.light, 0.45))), (0.5, cl(cc.main)), (1, cl(cc.main))], -27, 27), style: eo)
        g.stroke(ring, with: .color(cl(cc.shading)), lineWidth: 1)
        g.stroke(rr(-25.6, -25.6, 51.2, 51.2, 5), with: .color(cl(cc.light, 0.9)), lineWidth: 0.8)
    }

    private func drawAppTile(_ ctx: inout GraphicsContext, _ kind: String) { drawFileFrame(&ctx); drawArt(&ctx, kind) }
    private func drawItem(_ ctx: inout GraphicsContext, _ kind: String) {
        switch kind {
        case "card": drawCardSlot(&ctx)
        case "folder": drawFolderIcon(&ctx, open: false)
        default: drawAppTile(&ctx, kind)
        }
    }
    private func place(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ k: CGFloat, _ draw: (inout GraphicsContext) -> Void) {
        var p = ctx; p.translateBy(x: x, y: y); p.scaleBy(x: k, y: k); draw(&p)
    }

    // MARK: Bottom screen

    private static let cols: [CGFloat] = [54, 107, 160, 213, 266, 320]
    private static let rows: [CGFloat] = [70, 123, 176]
    private static let folderRows: [CGFloat] = [112, 166]
    private static let homeGrid: [(Int, Int, String)] = [
        (0, 0, "card"), (1, 0, "theme"), (2, 0, "folder"), (3, 0, "camera"), (4, 0, "music"),
        (0, 1, "settings"), (1, 1, "browser"), (2, 1, "shop"), (3, 1, "mail"),
        (0, 2, "game"), (1, 2, "download"),
    ]
    private static let folderGrid: [(Int, Int, String)] = [(0, 0, "theme"), (1, 0, "heart"), (2, 0, "game"), (0, 1, "music")]

    private func drawPanel(_ ctx: inout GraphicsContext, _ p: InnerPanelColors, _ r: CGRect) {
        let a = Double(p.glow.a) / 255 / 25
        for dx in -2...2 { for dy in -2...2 { ctx.fill(Path(roundedRect: r.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy) + 2), cornerRadius: 10), with: .color(cl(p.glow.rgb, a))) } }
        ctx.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(cl(p.main)))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(cl(p.border)), lineWidth: 1)
        ctx.stroke(line(r.minX + 10, r.maxY + 1, r.maxX - 20, r.maxY + 1), with: .color(cl(p.highlight)), lineWidth: 0.5)
    }

    private func drawSlotMarks(_ ctx: inout GraphicsContext, _ p: InnerPanelColors, rows: [CGFloat], solid: Bool, taken: Set<String>) {
        for x in Self.cols { for y in rows where !taken.contains("\(Int(x)),\(Int(y))") {
            if solid {
                ctx.stroke(rr(x - 8.5, y - 8.5, 16, 16, 2), with: .color(cl(p.border)), lineWidth: 1)
                ctx.stroke(line(x - 6.5, y - 8.5, x + 5.5, y - 8.5), with: .color(cl(p.highlight)), lineWidth: 0.5)
            } else {
                ctx.fill(rr(x - 8, y - 8, 16, 16, 2), with: .color(.white.opacity(0.2)))
            }
        } }
    }

    private func drawBottomBackground(_ ctx: inout GraphicsContext, taken: Set<String>) {
        let folder = mode == .folder
        let area = folder ? CGRect(x: 12, y: 69, width: 320, height: 140) : CGRect(x: 12, y: 39, width: 320, height: 170)
        let rows = folder ? Self.folderRows : Self.rows
        let panel = folder ? folderBgC : innerC
        if f.bottomDrawType == .texture, let img = images[.bottom] {
            var x: CGFloat = 0
            if !forExport {
                switch f.bottomFrameType {
                case .single: x = 0
                case .fastScroll, .slowScroll: x = CGFloat((sin(time / (f.bottomFrameType == .fastScroll ? 2 : 3)) + 1) / 2) * (1008 - 320)
                case .pageScroll: x = CGFloat(Int(time / 2.5) % 3) * 320
                case .bounceScroll: x = CGFloat([0, 1, 2, 1][Int(time / 2.5) % 4]) * 320
                }
            }
            drawImage(&ctx, img, in: CGRect(x: -x, y: 0, width: CGFloat(img.width), height: CGFloat(img.height)))
            if folder && f.folderBackgroundColor {
                drawPanel(&ctx, c.folderBackground, area); drawSlotMarks(&ctx, c.folderBackground, rows: rows, solid: true, taken: taken)
            } else if mode != .zoom {
                drawSlotMarks(&ctx, panel, rows: rows, solid: false, taken: taken)
            }
            return
        }
        let o = outerC
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 240)), with: .color(cl(o.main)))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 24, height: 240)), with: hgrad([(0, cl(o.glow)), (0.3, cl(o.glow)), (1, cl(o.main))], 0, 24))
        ctx.fill(Path(CGRect(x: 296, y: 0, width: 24, height: 240)), with: hgrad([(0, cl(o.main)), (0.7, cl(o.glow)), (1, cl(o.glow))], 296, 320))
        for i in 0..<7 {
            let y = 240 - CGFloat(4 * i) - 2.5
            ctx.stroke(line(0, y, 320, y), with: .color(cl(o.stripes, (1 - Double(i) / 7) / 2 + 0.15)), lineWidth: 0.6)
        }
        drawPanel(&ctx, panel, area)
        if mode != .zoom { drawSlotMarks(&ctx, panel, rows: rows, solid: true, taken: taken) }
    }

    /// HOME Menu settings (left) and icon-size buttons (right) along the top of the bottom screen.
    private func drawCornerButtons(_ ctx: inout GraphicsContext) {
        let bc = bottomCornerC
        for x: CGFloat in [-8, 268] {
            shadowed(ctx, cl(bc.baseShadow, 0.35), 4, 0, 1.5).fill(rr(x, -8, 59, 38, 8), with: .color(cl(bc.main)))
            ctx.fill(rr(x, -8, 59, 38, 8), with: vgrad([(0, cl(bc.highlight)), (0.55, cl(bc.main)), (1, cl(mix(bc.main, black, 0.06)))], -8, 30))
            ctx.stroke(rr(x + 0.5, -7.5, 58, 37, 8), with: .color(cl(bc.border)), lineWidth: 1)
        }
        let glyph = vgrad([(0, cl(bc.iconTop)), (1, cl(bc.iconBottom))], 4, 27)
        func well(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            ctx.fill(rr(x, y, w, h, 3), with: .color(.white.opacity(0.08)))
            ctx.stroke(rr(x, y, w, h, 3), with: .color(cl(bc.iconText, 0.55)), lineWidth: 0.75)
        }
        well(3, 3, 45, 25)
        var h = ctx; h.translateBy(x: 13, y: 5)
        var house = Path()
        house.move(to: CGPoint(x: 1, y: 9)); house.addLine(to: CGPoint(x: 10, y: 0)); house.addLine(to: CGPoint(x: 18, y: 8)); house.addLine(to: CGPoint(x: 15, y: 11))
        house.addLine(to: CGPoint(x: 15, y: 18)); house.addLine(to: CGPoint(x: 5, y: 18)); house.addQuadCurve(to: CGPoint(x: 3, y: 16), control: CGPoint(x: 3, y: 18)); house.addLine(to: CGPoint(x: 3, y: 9)); house.closeSubpath()
        h.fill(house, with: vgrad([(0, cl(bc.iconTop)), (1, cl(bc.iconBottom))], -1, 22))
        h.fill(Path(CGRect(x: 7.5, y: 11, width: 5, height: 7)), with: .color(cl(bc.main)))
        var brush = Path()
        brush.move(to: CGPoint(x: 16, y: 19)); brush.addLine(to: CGPoint(x: 22, y: 10)); brush.addQuadCurve(to: CGPoint(x: 25, y: 12), control: CGPoint(x: 25, y: 9))
        brush.addLine(to: CGPoint(x: 19, y: 21)); brush.addQuadCurve(to: CGPoint(x: 16, y: 19), control: CGPoint(x: 16, y: 23)); brush.closeSubpath()
        h.fill(brush, with: vgrad([(0, cl(bc.iconTop)), (1, cl(bc.iconBottom))], -1, 22))
        well(271, 4, 20, 23); well(297, 4, 20, 23)
        ctx.fill(rr(275, 10, 12, 12, 3), with: glyph)
        for (dx, dy) in [(0.0, 0.0), (7, 0), (0, 7), (7, 7)] { ctx.fill(rr(301 + dx, 10 + dy, 5, 5, 1), with: glyph) }
        ctx.stroke(line(293.5, 4, 293.5, 27), with: .color(cl(bc.border)), lineWidth: 1)
        ctx.stroke(line(294.5, 4, 294.5, 27), with: .color(cl(bc.highlight)), lineWidth: 1)
    }

    /// The row of built-in program shortcuts between the corner buttons (not affected by themes).
    private func drawShortcuts(_ ctx: inout GraphicsContext) {
        let tints: [RGB] = [RGB(255, 205, 60), RGB(255, 150, 70), RGB(110, 205, 90), RGB(80, 160, 250), RGB(160, 120, 240)]
        let w = Color.white
        for (i, tint) in tints.enumerated() {
            let x = 82 + CGFloat(i) * 39
            var s = ctx; s.translateBy(x: 0, y: 14)
            shadowed(s, .black.opacity(0.25), 2, 0, 1).fill(rr(x - 12, -10, 24, 20, 5), with: vgrad([(0, cl(mix(tint, white, 0.25))), (1, cl(tint))], -10, 10))
            s.stroke(rr(x - 11.6, -9.6, 23.2, 19.2, 4.6), with: .color(.white.opacity(0.7)), lineWidth: 0.8)
            switch i {
            case 0:
                s.fill(rr(x - 6, -6, 11, 13, 1.5), with: .color(w))
                for k in 0..<3 { let y = -3 + CGFloat(k) * 3.5; s.stroke(line(x - 4, y, x + 3, y), with: .color(hex(0xD29A10)), lineWidth: 1) }
            case 1:
                s.fill(circle(x, 0, 7), with: .color(w))
                var eyes = circle(x - 2.5, -1.5, 1.2); eyes.addPath(circle(x + 2.5, -1.5, 1.2)); s.fill(eyes, with: .color(hex(0xFF8A3C)))
                var smile = Path(); smile.addArc(center: CGPoint(x: x, y: 0.5), radius: 3.6, startAngle: .radians(0.2), endAngle: .radians(.pi - 0.2), clockwise: false)
                s.stroke(smile, with: .color(hex(0xFF8A3C)), lineWidth: 1.2)
            case 2:
                s.fill(rr(x - 7, -6, 14, 10, 3), with: .color(w)); s.fill(poly([(x - 3, 3), (x - 5, 7.5), (x + 1, 3)]), with: .color(w))
                s.fill(Path(CGRect(x: x - 0.8, y: -4.5, width: 1.6, height: 4)), with: .color(hex(0x4FB53A))); s.fill(Path(CGRect(x: x - 0.8, y: 0.5, width: 1.6, height: 1.6)), with: .color(hex(0x4FB53A)))
            case 3:
                var g = circle(x, 0, 6.5); g.addPath(line(x - 6.5, 0, x + 6.5, 0)); g.addPath(ellipse(x, 0, 3, 6.5))
                s.stroke(g, with: .color(w), lineWidth: 1.4)
            default:
                s.fill(rr(x - 7, -6, 10, 8, 2.5), with: .color(w)); s.fill(rr(x - 2, -2, 10, 8, 2.5), with: .color(w))
                s.fill(Path(CGRect(x: x, y: 1, width: 6, height: 1.2)), with: .color(hex(0xA078F0)))
            }
        }
    }

    /// The half-round scroll button on the right edge.
    private func drawArrowButton(_ ctx: inout GraphicsContext, pressed: Bool) {
        let ab = arrowButtonC, ar = arrowC
        var g = ctx; g.translateBy(x: pressed ? 2 : 0, y: 0)
        let shape = ellipse(338, 123, 38, 39)
        shadowed(g, ca(ab.shadow), 4, -1, 1).fill(shape, with: .color(cl(ab.main)))
        var sheen = g; sheen.clip(to: shape)
        sheen.fill(Path(CGRect(x: 296, y: 80, width: 30, height: 86)), with: vgrad([(0, cl(ab.main, 0)), (0.5, cl(ab.main, 0)), (1, cl(ab.shading, 0.95))], 84, 162))
        sheen.fill(Path(CGRect(x: 296, y: 80, width: 30, height: 86)), with: hgrad([(0, cl(ab.light, 0.95)), (1, cl(ab.light, 0))], 300, 312))
        var rim = Path(); rim.addArc(center: CGPoint(x: 338, y: 123), radius: 38, startAngle: .radians(.pi * 0.62), endAngle: .radians(.pi * 1.38), clockwise: false)
        g.stroke(rim, with: .color(.white.opacity(0.9)), lineWidth: 1)
        g.translateBy(x: 303, y: 123)
        var arrow = Path()
        arrow.move(to: CGPoint(x: 1, y: 2)); arrow.addLine(to: CGPoint(x: 7, y: 2)); arrow.addLine(to: CGPoint(x: 7, y: 7)); arrow.addLine(to: CGPoint(x: 14, y: 0))
        arrow.addLine(to: CGPoint(x: 7, y: -7)); arrow.addLine(to: CGPoint(x: 7, y: -2)); arrow.addLine(to: CGPoint(x: 1, y: -2))
        arrow.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 0, y: -2)); arrow.addQuadCurve(to: CGPoint(x: 1, y: 2), control: CGPoint(x: 0, y: 2)); arrow.closeSubpath()
        g.fill(arrow, with: .color(cl(pressed ? ar.pressed : ar.unpressed)))
        g.stroke(arrow, with: .color(cl(ar.border)), lineWidth: 1)
    }

    /// The Open bar across the bottom (or Close + the suspended software when something is suspended).
    private func drawButtonBar(_ ctx: inout GraphicsContext, pressed: Bool) {
        func one(_ o: OpenCloseColors, _ x: CGFloat, _ w: CGFloat, _ text: String, left: Bool, right: Bool, isPressed: Bool) {
            let shape = UnevenRoundedRectangle(topLeadingRadius: left ? 10 : 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: right ? 10 : 0)
                .path(in: CGRect(x: x, y: 215, width: w, height: 50))
            shadowed(ctx, ca(o.shadow), 5, 0, -1).fill(shape, with: .color(cl(o.unpressed)))
            ctx.fill(shape, with: vgrad([(0, cl(o.light)), (1, cl(isPressed ? o.pressed : o.unpressed))], 215, 240))
            var edge = ctx; edge.clip(to: shape)
            edge.stroke(line(x + (left ? 8 : 0), 216, x + w - (right ? 8 : 0), 216), with: .color(cl(o.glow)), lineWidth: 1.2)
            ctx.stroke(shape, with: .color(cl(mix(o.unpressed, black, 0.12))), lineWidth: 0.8)
            let t = fitted(ctx, text, w - 16, 13), dy = CGFloat(max(-3, min(3, o.textShadowPosition))) * 1.2, ty: CGFloat = 227.5 + (isPressed ? 1 : 0)
            ctx.draw(label(t, 13, cl(o.textShadow)), at: CGPoint(x: x + w / 2, y: ty - dy))
            ctx.draw(label(t, 13, cl(isPressed ? o.textPressed : o.textUnpressed)), at: CGPoint(x: x + w / 2, y: ty))
        }
        if mode == .paused {
            one(closeC, 0, 106, "Close", left: true, right: false, isPressed: pressed)
            one(openC, 106, 214, shownTitle, left: false, right: true, isPressed: false)
            ctx.stroke(line(106, 217, 106, 240), with: .color(.black.opacity(0.25)), lineWidth: 1)
        } else {
            one(openC, 0, 320, shownTitle, left: true, right: true, isPressed: pressed)
        }
    }

    /// The button that leaves a folder, and the folder's name.
    private func drawFolderHeader(_ ctx: inout GraphicsContext, pressed: Bool) {
        let fa = folderArrowC, box = rr(27, 47, 66, 30, 8)
        shadowed(ctx, ca(fa.shadow), 4, 0, 2).fill(box, with: .color(cl(fa.main)))
        ctx.fill(box, with: vgrad([(0, cl(fa.highlight)), (0.3, cl(fa.main)), (1, cl(pressed ? mix(fa.main, black, 0.2) : fa.main))], 47, 77))
        ctx.stroke(rr(27.5, 47.5, 65, 29, 8), with: .color(cl(fa.shading)), lineWidth: 1)
        ctx.stroke(line(35, 49, 85, 49), with: .color(cl(fa.glow)), lineWidth: 0.9)
        var arrow = Path()
        arrow.move(to: CGPoint(x: 7, y: 4)); arrow.addLine(to: CGPoint(x: 10, y: 4))
        arrow.addArc(center: CGPoint(x: 10, y: 10), radius: 6, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        arrow.addLine(to: CGPoint(x: 7, y: 16)); arrow.addLine(to: CGPoint(x: 7, y: 13)); arrow.addLine(to: CGPoint(x: 10, y: 13))
        arrow.addArc(center: CGPoint(x: 10, y: 10), radius: 3, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        arrow.addLine(to: CGPoint(x: 7, y: 7)); arrow.addLine(to: CGPoint(x: 7, y: 10)); arrow.addLine(to: CGPoint(x: 0, y: 5.5)); arrow.addLine(to: CGPoint(x: 7, y: 0)); arrow.closeSubpath()
        let dy = CGFloat(max(-3, min(3, fa.arrowShadowPosition))) * 1.2
        var a = ctx; a.translateBy(x: 51, y: 52 + (pressed ? 1 : 0))
        var glow = a; glow.translateBy(x: 0, y: -dy); glow.fill(arrow, with: .color(cl(fa.arrowGlow, 0.8)))
        a.fill(arrow, with: .color(cl(pressed ? fa.arrowPressed : fa.arrowUnpressed)))
        outlined(&ctx, "My Folder", 104, 62, 13, hex(0x3D3D3D), .leading)
    }

    func drawBottom(_ ctx: inout GraphicsContext) {
        var ctx = ctx
        ctx.clip(to: Path(CGRect(origin: .zero, size: Self.bottomSize)))
        let grid = mode == .folder ? Self.folderGrid : Self.homeGrid, rows = mode == .folder ? Self.folderRows : Self.rows
        let taken = Set(grid.map { "\(Int(Self.cols[$0.0])),\(Int(rows[$0.1]))" })
        drawBottomBackground(&ctx, taken: taken)

        if mode == .zoom {
            // Largest icon size: one big row, with the selected title shown above the cursor.
            let k: CGFloat = 1.72, y: CGFloat = 132
            for (x, kind) in [(CGFloat(-12), "card"), (160, "theme"), (332, "folder")] { place(ctx, x, y, k) { drawItem(&$0, kind) } }
            place(ctx, 160, y, k) { drawCursor(&$0) }
            if f.gameTextDrawType != .hidden {
                let g = gameTextC, text = fitted(ctx, shownTitle, 200, 12)
                let tw = ctx.resolve(label(text, 12, .black)).measure(in: CGSize(width: 2000, height: 100)).width
                let w = max(90, tw + 28), box = rr(160 - w / 2, 50, w, 24, 7)
                shadowed(ctx, ca(g.shadow), 4, 0, 2).fill(box, with: .color(cl(g.main)))
                ctx.fill(poly([(154, 74), (160, 80), (166, 74)]), with: .color(cl(g.main)))
                ctx.fill(box, with: vgrad([(0, cl(g.light)), (0.6, cl(g.main, 0))], 50, 74))
                ctx.draw(label(text, 12, cl(g.text)), at: CGPoint(x: 160, y: 62.5))
            }
        } else {
            for (cx, ry, kind) in grid { place(ctx, Self.cols[cx], rows[ry], 1) { drawItem(&$0, kind) } }
            place(ctx, Self.cols[1], rows[0], 1) { drawCursor(&$0) }
        }
        if mode == .folder { drawFolderHeader(&ctx, pressed: !forExport && Int(time / 1.7) % 4 == 3) }
        drawCornerButtons(&ctx)
        drawShortcuts(&ctx)
        if mode != .folder { drawArrowButton(&ctx, pressed: !forExport && Int(time / 1.5) % 4 == 3) }
        drawButtonBar(&ctx, pressed: !forExport && Int(time / 2) % 5 == 4)
    }

    // MARK: Top screen

    private func drawStatusBar(_ ctx: inout GraphicsContext) {
        let blue = hex(0x27B7EB), dark = hex(0x3D3D3D)
        var sig = ctx; sig.translateBy(x: 8, y: 3)
        let bars: [CGRect] = [CGRect(x: 3, y: 7, width: 3, height: 10), CGRect(x: 7, y: 12, width: 5, height: 5), CGRect(x: 12, y: 7, width: 5, height: 10), CGRect(x: 17, y: 2, width: 5, height: 15)]
        sig.fill(circle(4, 4, 2.5), with: .color(blue)); sig.stroke(circle(4, 4, 2.5), with: .color(.white), lineWidth: 1)
        for b in bars { sig.fill(Path(b), with: .color(blue)); sig.stroke(Path(b), with: .color(.white), lineWidth: 1) }
        let pill = rr(33, 3, 104, 16, 2.5)
        ctx.fill(pill, with: vgrad([(0, hex(0x31AADF)), (0.5, hex(0x59C3F3)), (0.5, hex(0x31AADF)), (1, hex(0x59C3F3))], 3, 19))
        ctx.stroke(pill, with: .color(.white), lineWidth: 0.8)
        ctx.draw(label("Internet", 11, .white, .bold), at: CGPoint(x: 85, y: 11.5))
        ctx.fill(circle(155, 11, 7), with: .color(hex(0xD5C500))); ctx.stroke(circle(155, 11, 7), with: .color(.white), lineWidth: 0.8)
        var coin = Path(CGRect(x: 153, y: 8, width: 4, height: 6)); coin.addPath(line(153, 11, 157, 11)); ctx.stroke(coin, with: .color(.white), lineWidth: 1)
        outlined(&ctx, "300", 166, 11.5, 12, dark, .leading)
        let cal = Calendar.current, now = clock
        let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][cal.component(.weekday, from: now) - 1]
        outlined(&ctx, "\(cal.component(.month, from: now))/\(cal.component(.day, from: now)) (\(day))", 300, 11.5, 12, dark, .trailing)
        outlined(&ctx, "\(cal.component(.hour, from: now))", 340, 11.5, 12, dark, .trailing)
        if forExport || Int(time * 2) % 2 == 0 { outlined(&ctx, ":", 343, 10.5, 12, dark) }
        outlined(&ctx, String(format: "%02d", cal.component(.minute, from: now)), 346, 11.5, 12, dark, .leading)
        let body = rr(376, 3, 27, 16, 2), nub = Path(CGRect(x: 373.5, y: 8, width: 2.5, height: 6))
        ctx.fill(body, with: .color(.black)); ctx.stroke(body, with: .color(.white), lineWidth: 1)
        ctx.fill(nub, with: .color(.black)); ctx.stroke(nub, with: .color(.white), lineWidth: 1)
        ctx.fill(Path(CGRect(x: 380, y: 6, width: 20, height: 10)), with: vgrad([(0, hex(0x7FE08A)), (0.3, .white), (0.45, hex(0x3FB54D)), (1, hex(0x2A9A3A))], 6, 16))
    }

    /// The camera shortcut tabs in the lower corners of the top screen.
    private func drawCameraTabs(_ ctx: inout GraphicsContext) {
        let tc = topCornerC, fg = cl(tc.text)
        var g = ctx; g.translateBy(x: 0, y: 217)
        var shape = Path()
        shape.move(to: CGPoint(x: 0, y: 23)); shape.addLine(to: CGPoint(x: 0, y: 0)); shape.addLine(to: CGPoint(x: 76, y: 0)); shape.addQuadCurve(to: CGPoint(x: 90, y: 10), control: CGPoint(x: 88, y: 0)); shape.addLine(to: CGPoint(x: 92, y: 23)); shape.closeSubpath()
        shape.move(to: CGPoint(x: 320, y: 23)); shape.addLine(to: CGPoint(x: 323, y: 10)); shape.addQuadCurve(to: CGPoint(x: 334, y: 0), control: CGPoint(x: 326, y: 0)); shape.addLine(to: CGPoint(x: 412, y: 0)); shape.addLine(to: CGPoint(x: 412, y: 23)); shape.closeSubpath()
        shadowed(g, cl(tc.shadow, 0.5), 3, 0, 0).fill(shape, with: .color(cl(tc.main, 0.78)))
        g.fill(shape, with: vgrad([(0, cl(tc.light, 0.55)), (1, cl(tc.light, 0))], 0, 12))
        var cam = g; cam.translateBy(x: 20, y: 5)
        var frame = Path()
        frame.move(to: CGPoint(x: 9, y: 12)); frame.addLine(to: CGPoint(x: 2, y: 12)); frame.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 0, y: 12)); frame.addLine(to: CGPoint(x: 0, y: 2))
        frame.addQuadCurve(to: CGPoint(x: 2, y: 0), control: CGPoint(x: 0, y: 0)); frame.addLine(to: CGPoint(x: 15, y: 0)); frame.addQuadCurve(to: CGPoint(x: 17, y: 2), control: CGPoint(x: 17, y: 0))
        cam.stroke(frame, with: .color(fg), lineWidth: 1.8)
        cam.fill(rr(11, 6, 12, 8, 1.5), with: .color(fg)); cam.fill(rr(14, 4, 6, 4, 2), with: .color(fg)); cam.fill(circle(17, 10, 2.3), with: .color(cl(tc.main)))
        g.stroke(circle(60, 11, 7.5), with: .color(fg), lineWidth: 1.6)
        g.draw(label("Y", 10, fg), at: CGPoint(x: 60, y: 11.5))
        var cam2 = g; cam2.translateBy(x: 318, y: 5)
        cam2.fill(rr(0, 2, 16, 12, 1.5), with: .color(fg)); cam2.fill(rr(4, 0, 8, 4, 2), with: .color(fg)); cam2.fill(circle(8, 8, 3), with: .color(cl(tc.main)))
        func shoulder(_ x: CGFloat, flip: Bool, _ ch: String) {
            var s = g; s.translateBy(x: x, y: 5)
            var p = Path()
            if !flip {
                p.move(to: CGPoint(x: 0, y: 13)); p.addQuadCurve(to: CGPoint(x: 3, y: 0), control: CGPoint(x: 2, y: 0)); p.addLine(to: CGPoint(x: 16, y: 0)); p.addQuadCurve(to: CGPoint(x: 13, y: 13), control: CGPoint(x: 15, y: 2))
            } else {
                p.move(to: CGPoint(x: 16, y: 13)); p.addQuadCurve(to: CGPoint(x: 13, y: 0), control: CGPoint(x: 14, y: 0)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addQuadCurve(to: CGPoint(x: 3, y: 13), control: CGPoint(x: 1, y: 2))
            }
            p.closeSubpath()
            s.stroke(p, with: .color(fg), lineWidth: 1.4)
            s.draw(label(ch, 9.5, fg), at: CGPoint(x: 8, y: 7))
        }
        shoulder(338, flip: false, "L")
        g.draw(label("+", 11, fg), at: CGPoint(x: 367, y: 11.5))
        shoulder(372, flip: true, "R")
    }

    func drawTop(_ ctx: inout GraphicsContext) {
        var ctx = ctx
        let rect = CGRect(origin: .zero, size: Self.topSize)
        ctx.clip(to: Path(rect))
        switch f.topDrawType {
        case .solidColor, .solidColorTexture:
            let tb = c.topBackground
            ctx.fill(Path(rect), with: .color(cl(tb.main)))
            let glow = RGB(tb.gradientColor, tb.gradientColor, tb.gradientColor), k = Double(tb.gradient) / 255
            ctx.fill(Path(rect), with: vgrad([(0, cl(glow, k * 0.85)), (1, cl(glow, 0))], 0, 240))
            if f.topDrawType == .solidColorTexture {
                let off = forExport ? 0 : CGFloat(time * 8).truncatingRemainder(dividingBy: 64)
                if let p = images[.topPattern] { var pc = ctx; pc.opacity = Double(tb.textureOpacity) / 255; tile(&pc, p, rect, dx: off, dy: off) }
                if let alt = images[.topAltPattern] { var ac = ctx; ac.opacity = Double(tb.alternateOpacity) / 255; tile(&ac, alt, rect, dx: -off, dy: off * 0.5) }
            }
        case .texture where images[.top] != nil:
            let img = images[.top]!
            var x: CGFloat = 0
            if f.topFrameType.scrolls && !forExport { x = CGFloat((sin(time / (f.topFrameType == .fastScroll ? 2 : 3)) + 1) / 2) * (1008 - 412) }
            drawImage(&ctx, img, in: CGRect(x: -x, y: 0, width: CGFloat(img.width), height: CGFloat(img.height)))
        default:
            ctx.fill(Path(rect), with: vgrad([(0, hex(0xF4F4F6)), (1, hex(0xD9D9E0))], 0, 240))
            let off = forExport ? 0 : CGFloat(time * 6).truncatingRemainder(dividingBy: 24)
            var lines = Path()
            var x = -240 + off
            while x < 412 { lines.addPath(line(x, 240, x + 240, 0)); x += 24 }
            ctx.stroke(lines, with: .color(.white.opacity(0.55)), lineWidth: 1)
        }

        if mode == .folder {
            // The selected folder floats in the middle of the top screen.
            let bob = forExport ? 0 : sin(time * 1.6) * 4, tilt = forExport ? 0 : sin(time * 0.8) * 0.06
            var fc = ctx; fc.translateBy(x: 206, y: 118 + bob); fc.rotate(by: .radians(tilt)); fc.scaleBy(x: 2.7, y: 2.7)
            drawFolderIcon(&fc, open: true)
        }
        if f.demoTextColor && mode != .folder {
            let d = c.demoText
            shadowed(ctx, .black.opacity(0.3), 4, 0, 1).fill(rr(116, 176, 180, 24, 6), with: .color(cl(d.main, 0.95)))
            ctx.draw(label("Remaining uses: 10", 11.5, cl(d.text), .bold), at: CGPoint(x: 206, y: 188.5))
        }
        drawStatusBar(&ctx)
        drawCameraTabs(&ctx)
        if !forExport {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 6, height: 240)), with: .color(.black.opacity(0.22)))
            ctx.fill(Path(CGRect(x: 406, y: 0, width: 6, height: 240)), with: .color(.black.opacity(0.22)))
        }
    }

    private func tile(_ ctx: inout GraphicsContext, _ img: CGImage, _ rect: CGRect, dx: CGFloat, dy: CGFloat) {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        var y = -h + dy.truncatingRemainder(dividingBy: h)
        while y < rect.maxY {
            var x = -w + dx.truncatingRemainder(dividingBy: w)
            while x < rect.maxX { ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: w, height: h)); x += w }
            y += h
        }
    }
}

// MARK: - Console shell

/// Draws a 3DS around the two screens. Sizes are console pixels; the whole drawing is 480×622.
struct ConsoleShell {
    static let size = CGSize(width: 480, height: 622)
    static let topScreen = CGPoint(x: 34, y: 28)
    static let bottomScreen = CGPoint(x: 80, y: 334)

    static func draw(_ ctx: inout GraphicsContext) {
        func hex(_ v: UInt32, _ a: Double = 1) -> Color { Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a) }
        func vg(_ stops: [(Double, Color)], _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
            .linearGradient(Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) }), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        func radial(_ inner: Color, _ outer: Color, _ c: CGPoint, _ r: CGFloat) -> GraphicsContext.Shading { .radialGradient(Gradient(colors: [inner, outer]), center: c, startRadius: 0, endRadius: r) }
        func caption(_ s: String, _ size: CGFloat, _ color: Color) -> Text { Text(s).font(.system(size: size, weight: .heavy)).foregroundColor(color) }

        // top half
        let top = UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 26).path(in: CGRect(x: 0, y: 0, width: 480, height: 296))
        var shadow = ctx; shadow.addFilter(.shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 10))
        shadow.fill(top, with: .color(hex(0x1C1F2A)))
        ctx.fill(top, with: vg([(0, hex(0x2B2F3D)), (0.55, hex(0x1C1F2A)), (1, hex(0x161923))], 0, 296))
        ctx.stroke(UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 26).path(in: CGRect(x: 0.5, y: 0.5, width: 479, height: 295)), with: .color(.white.opacity(0.08)), lineWidth: 1)
        ctx.fill(Path(roundedRect: CGRect(x: 28, y: 22, width: 424, height: 252), cornerRadius: 7), with: .color(hex(0x07080B)))
        ctx.fill(circle(240, 11, 4), with: radial(hex(0x50607C), hex(0x0A0C12), CGPoint(x: 239, y: 10), 4))
        for side: CGFloat in [7, 480 - 7 - 17.6] {
            for r in 0..<7 { for cc in 0..<3 { ctx.fill(circle(side + 1.6 + CGFloat(cc) * 7.2, 74 + 1.6 + CGFloat(r) * 7.4, 1.6), with: .color(hex(0x090A0F))) } }
        }
        ctx.fill(Path(roundedRect: CGRect(x: 466, y: 18, width: 5, height: 44), cornerRadius: 3), with: .color(hex(0x0B0C12)))
        ctx.fill(Path(roundedRect: CGRect(x: 464.5, y: 40, width: 8, height: 10), cornerRadius: 2), with: .color(hex(0xB0B6C6)))
        ctx.draw(caption("3D", 6, .white.opacity(0.35)), at: CGPoint(x: 468, y: 70))
        // hinge
        let hinge = Path(roundedRect: CGRect(x: 14, y: 296, width: 452, height: 16), cornerRadius: 8)
        ctx.fill(hinge, with: vg([(0, hex(0x11131A)), (0.35, hex(0x3A3F50)), (0.6, hex(0x232634)), (1, hex(0x0D0F15))], 296, 312))
        var led = ctx; led.addFilter(.shadow(color: hex(0x50C8FF, 0.8), radius: 3))
        led.fill(circle(437, 304, 3), with: radial(hex(0xB9F3FF), hex(0x10668E), CGPoint(x: 436, y: 303), 3.5))
        // bottom half
        let bottom = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 10).path(in: CGRect(x: 0, y: 312, width: 480, height: 310))
        shadow.fill(bottom, with: .color(hex(0x1D202B)))
        ctx.fill(bottom, with: vg([(0, hex(0x232733)), (0.4, hex(0x1D202B)), (1, hex(0x171A24))], 312, 622))
        ctx.fill(Path(roundedRect: CGRect(x: 74, y: 328, width: 332, height: 252), cornerRadius: 7), with: .color(hex(0x07080B)))
        // circle pad
        ctx.fill(circle(38, 363, 25), with: .color(hex(0x0C0E14)))
        var pad = ctx; pad.addFilter(.shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 2))
        pad.fill(circle(38, 363, 19), with: radial(hex(0x5C6274), hex(0x1B1E27), CGPoint(x: 35, y: 358), 22))
        // d-pad
        let dpadColor = vg([(0, hex(0x3D4252)), (1, hex(0x22252F))], 424, 468)
        ctx.fill(Path(roundedRect: CGRect(x: 16, y: 439, width: 44, height: 14), cornerRadius: 2.5), with: dpadColor)
        ctx.fill(Path(roundedRect: CGRect(x: 31, y: 424, width: 14, height: 44), cornerRadius: 2.5), with: dpadColor)
        ctx.fill(circle(38, 446, 4), with: .color(hex(0x1A1D25)))
        // A B X Y
        for (letter, x, y) in [("X", 422.5 + 8.5, 342 + 8.5), ("Y", 414 + 8.5, 361.5 + 8.5), ("A", 453 + 8.5, 361.5 + 8.5), ("B", 433.5 + 8.5, 381 + 8.5)] as [(String, CGFloat, CGFloat)] {
            ctx.fill(circle(x, y + 1.6, 8.5), with: .color(hex(0x0B0D12)))
            ctx.fill(circle(x, y, 8.5), with: radial(hex(0x4A4F60), hex(0x262A35), CGPoint(x: x - 1.5, y: y - 2.5), 10))
            ctx.draw(caption(letter, 8, hex(0xC9CEDE)), at: CGPoint(x: x, y: y))
        }
        // power
        ctx.fill(circle(446, 528, 6), with: radial(hex(0x3C4152), hex(0x1C1F29), CGPoint(x: 444, y: 526), 7))
        var power = Path(); power.addArc(center: CGPoint(x: 446, y: 528), radius: 2.7, startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
        ctx.stroke(power, with: .color(.white.opacity(0.45)), lineWidth: 1)
        // SELECT / HOME / START
        for (x, text) in [(CGFloat(185), "SELECT"), (295, "START")] {
            ctx.fill(Path(roundedRect: CGRect(x: x - 22, y: 597, width: 44, height: 13), cornerRadius: 6), with: .color(hex(0x11131A)))
            ctx.draw(caption(text, 6, .white.opacity(0.42)), at: CGPoint(x: x, y: 603.5))
        }
        ctx.fill(Path(roundedRect: CGRect(x: 225, y: 597, width: 30, height: 12), cornerRadius: 6), with: vg([(0, hex(0x3A3F50)), (1, hex(0x20232D))], 597, 609))
        var house = Path()
        house.move(to: CGPoint(x: 240, y: 600)); house.addLine(to: CGPoint(x: 243.5, y: 602.5)); house.addLine(to: CGPoint(x: 242.5, y: 602.5)); house.addLine(to: CGPoint(x: 242.5, y: 605))
        house.addLine(to: CGPoint(x: 237.5, y: 605)); house.addLine(to: CGPoint(x: 237.5, y: 602.5)); house.addLine(to: CGPoint(x: 236.5, y: 602.5)); house.closeSubpath()
        ctx.fill(house, with: .color(hex(0x8FD7FF, 0.85)))
        ctx.fill(circle(374.5, 604.5, 1.5), with: .color(hex(0x07080B)))
    }
}

/// Animated (or static) 3DS showing both screens.
struct ConsoleScreensView: View {
    @Environment(ThemeDocument.self) private var doc
    var scale: CGFloat
    var animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animate)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let renderer = PreviewRenderer(theme: doc.theme, images: doc.previewImages, icon: doc.iconImage,
                                           mode: doc.previewMode, title: doc.name, time: animate ? t : 0, forExport: false)
            Canvas { ctx, _ in
                ctx.scaleBy(x: scale, y: scale)
                ConsoleShell.draw(&ctx)
                var top = ctx
                top.translateBy(x: ConsoleShell.topScreen.x, y: ConsoleShell.topScreen.y)
                top.clip(to: Path(roundedRect: CGRect(origin: .zero, size: PreviewRenderer.topSize), cornerRadius: 1.5))
                renderer.drawTop(&top)
                var bottom = ctx
                bottom.translateBy(x: ConsoleShell.bottomScreen.x, y: ConsoleShell.bottomScreen.y)
                bottom.clip(to: Path(roundedRect: CGRect(origin: .zero, size: PreviewRenderer.bottomSize), cornerRadius: 1.5))
                renderer.drawBottom(&bottom)
            }
            .frame(width: ConsoleShell.size.width * scale, height: ConsoleShell.size.height * scale)
        }
    }
}

/// Static 412×480 image used as preview.png (the layout Anemone3DS and ThemePlaza expect).
struct ExportPreviewView: View {
    let renderer: PreviewRenderer
    var body: some View {
        Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 412, height: 480)), with: .color(Color(white: 0.08)))
            var top = ctx
            top.clip(to: Path(CGRect(x: 0, y: 0, width: 412, height: 240)))
            renderer.drawTop(&top)
            var bottom = ctx
            bottom.translateBy(x: 46, y: 240)
            bottom.clip(to: Path(CGRect(x: 0, y: 0, width: 320, height: 240)))
            renderer.drawBottom(&bottom)
        }
        .frame(width: 412, height: 480)
    }
}
