import SwiftUI
import ThemeKit

/// Draws an approximation of the 3DS HOME Menu using the theme's colors and images.
/// Coordinates are in console pixels: top screen 412×240 (including 3D margins), bottom 320×240.
struct PreviewRenderer {
    let theme: Theme
    let images: [TextureSlot: CGImage]
    let icon: CGImage?
    let folderMode: Bool
    let time: Double
    let forExport: Bool

    static let topSize = CGSize(width: 412, height: 240)
    static let bottomSize = CGSize(width: 320, height: 240)

    private var f: ThemeFlags { theme.flags }
    private var c: ThemeColors { theme.colors }
    private var defaults: ThemeColors { ThemeColors() }

    // MARK: Helpers

    private func color(_ rgb: RGB, _ opacity: Double = 1) -> GraphicsContext.Shading { .color(rgb.color.opacity(opacity)) }

    private func vGradient(_ top: RGB, _ bottom: RGB, _ rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [top.color, bottom.color]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY))
    }

    private func text(_ s: String, size: CGFloat, weight: Font.Weight = .semibold, color: RGB) -> Text {
        Text(s).font(.system(size: size, weight: weight, design: .rounded)).foregroundColor(color.color)
    }

    private func drawImage(_ ctx: inout GraphicsContext, _ img: CGImage, at origin: CGPoint) {
        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: origin.x, y: origin.y, width: CGFloat(img.width), height: CGFloat(img.height)))
    }

    // MARK: Top screen

    func drawTop(_ ctx: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: Self.topSize)
        switch f.topDrawType {
        case .none:
            drawDefaultTop(&ctx, rect)
        case .solidColor:
            drawSolidTop(&ctx, rect, patterns: false)
        case .solidColorTexture:
            drawSolidTop(&ctx, rect, patterns: true)
        case .texture:
            if let img = images[.top] {
                var x: CGFloat = 0
                if f.topFrameType.scrolls {
                    let travel: CGFloat = 1008 - 412
                    let speed = f.topFrameType == .fastScroll ? 2.0 : 3.5
                    x = forExport ? 0 : CGFloat((sin(time / speed) + 1) / 2) * travel
                }
                drawImage(&ctx, img, at: CGPoint(x: -x, y: 0))
            } else {
                drawDefaultTop(&ctx, rect)
            }
        }

        // Status bar
        let shadow = RGB(0, 0, 0)
        var t = ctx
        t.addFilter(.shadow(color: shadow.color.opacity(0.45), radius: 1.5, x: 0, y: 1))
        t.draw(text("12:30", size: 11, weight: .bold, color: RGB(255, 255, 255)), at: CGPoint(x: 18, y: 10), anchor: .leading)
        t.draw(text("Sat 11/21", size: 10, weight: .semibold, color: RGB(255, 255, 255)), at: CGPoint(x: 58, y: 10), anchor: .leading)
        let battery = CGRect(x: 376, y: 5, width: 20, height: 10)
        t.stroke(Path(roundedRect: battery, cornerRadius: 2), with: .color(.white), lineWidth: 1.2)
        t.fill(Path(roundedRect: battery.insetBy(dx: 2, dy: 2), cornerRadius: 1), with: .color(.white))
        t.fill(Path(CGRect(x: 396.5, y: 8, width: 2, height: 4)), with: .color(.white))
        t.draw(Text(Image(systemName: "wifi")).font(.system(size: 10, weight: .bold)).foregroundColor(.white), at: CGPoint(x: 362, y: 10))

        if folderMode {
            // Big folder in the middle, like the HOME Menu's rotating folder.
            let bob = forExport ? 0 : sin(time * 1.6) * 4
            let fr = CGRect(x: 206 - 70, y: 70 + bob, width: 140, height: 104)
            drawFolderIcon(&ctx, fr, open: true)
        } else {
            drawGameText(&ctx)
        }
        if f.demoTextColor && !folderMode { drawDemoText(&ctx) }

        if !forExport {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 6, height: 240)), with: .color(.black.opacity(0.18)))
            ctx.fill(Path(CGRect(x: 406, y: 0, width: 6, height: 240)), with: .color(.black.opacity(0.18)))
        }
    }

    private func drawDefaultTop(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        ctx.fill(Path(rect), with: vGradient(RGB(232, 232, 238), RGB(196, 196, 210), rect))
        // Soft floating squares like the stock HOME Menu.
        for i in 0..<9 {
            let size = CGFloat(18 + (i * 7) % 26)
            let speed = 6.0 + Double(i)
            let x = CGFloat((Double(i) * 53 + (forExport ? 0 : time * speed)).truncatingRemainder(dividingBy: 460)) - 30
            let y = CGFloat(30 + (i * 37) % 180)
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: size, height: size), cornerRadius: 3), with: .color(.white.opacity(0.35)))
        }
    }

    private func drawSolidTop(_ ctx: inout GraphicsContext, _ rect: CGRect, patterns: Bool) {
        let tb = c.topBackground
        ctx.fill(Path(rect), with: color(tb.main))
        let glow = RGB(tb.gradientColor, tb.gradientColor, tb.gradientColor)
        let strength = Double(tb.gradient) / 255
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [glow.color.opacity(strength * 0.85), glow.color.opacity(0)]),
                                                     startPoint: CGPoint(x: rect.midX, y: 0), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        guard patterns else { return }
        let offset = forExport ? 0 : CGFloat(time * 8).truncatingRemainder(dividingBy: 64)
        if let p = images[.topPattern] {
            var pc = ctx
            pc.opacity = Double(tb.textureOpacity) / 255
            tile(&pc, p, rect, dx: offset, dy: offset)
        }
        if let alt = images[.topAltPattern] {
            var ac = ctx
            ac.opacity = Double(tb.alternateOpacity) / 255
            tile(&ac, alt, rect, dx: -offset, dy: offset * 0.5)
        }
    }

    private func tile(_ ctx: inout GraphicsContext, _ img: CGImage, _ rect: CGRect, dx: CGFloat, dy: CGFloat) {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        var y = -h + dy.truncatingRemainder(dividingBy: h)
        while y < rect.maxY {
            var x = -w + dx.truncatingRemainder(dividingBy: w)
            while x < rect.maxX {
                ctx.draw(Image(decorative: img, scale: 1), in: CGRect(x: x, y: y, width: w, height: h))
                x += w
            }
            y += h
        }
    }

    private func drawGameText(_ ctx: inout GraphicsContext) {
        guard f.gameTextDrawType != .hidden else { return }
        let g = f.gameTextDrawType == .colored ? c.gameText : defaults.gameText
        let box = CGRect(x: 86, y: 196, width: 240, height: 32)
        var s = ctx
        s.addFilter(.shadow(color: g.shadow.color, radius: 3, x: 0, y: 2))
        s.fill(Path(roundedRect: box, cornerRadius: 9), with: vGradient(g.light, g.main, box))
        ctx.stroke(Path(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9), with: color(g.light), lineWidth: 1)
        ctx.draw(text("Meer Theme Manager", size: 13, weight: .bold, color: g.text), at: CGPoint(x: box.midX, y: box.midY))
    }

    private func drawDemoText(_ ctx: inout GraphicsContext) {
        let d = c.demoText
        let box = CGRect(x: 120, y: 26, width: 172, height: 22)
        ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: color(d.main, 0.95))
        ctx.draw(text("Demo text", size: 11, color: d.text), at: CGPoint(x: box.midX, y: box.midY))
    }

    // MARK: Bottom screen

    func drawBottom(_ ctx: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: Self.bottomSize)
        let inner = CGRect(x: 12, y: 39, width: 296, height: 170)

        if f.bottomDrawType == .texture, let img = images[.bottom] {
            var x: CGFloat = 0
            if !forExport {
                switch f.bottomFrameType {
                case .single: x = 0
                case .slowScroll, .fastScroll:
                    let speed = f.bottomFrameType == .fastScroll ? 2.0 : 3.5
                    x = CGFloat((sin(time / speed) + 1) / 2) * (1008 - 320)
                case .pageScroll:
                    x = CGFloat(Int(time / 2.5) % 3) * 320
                case .bounceScroll:
                    x = CGFloat([0, 1, 2, 1][Int(time / 2.5) % 4]) * 320
                }
            }
            drawImage(&ctx, img, at: CGPoint(x: -x, y: 0))
        } else {
            let custom = f.bottomDrawType == .solidColor
            let outer = custom && f.bottomOuterColor ? c.bottomOuter : defaults.bottomOuter
            var innerColors = custom && f.bottomInnerColor ? c.bottomInner : defaults.bottomInner
            if folderMode { innerColors = f.folderBackgroundColor ? c.folderBackground : (custom && f.bottomInnerColor ? c.bottomInner : defaults.folderBackground) }
            drawOuter(&ctx, rect, outer)
            drawInner(&ctx, inner, innerColors)
        }
        if f.bottomDrawType == .texture && folderMode && f.folderBackgroundColor {
            drawInner(&ctx, inner, c.folderBackground)
        }

        drawIconGrid(&ctx, inner)
        drawArrowButtons(&ctx)
        drawTopCorners(&ctx)
        drawBottomCorners(&ctx)
        drawOpenClose(&ctx)
        if folderMode { drawFolderArrow(&ctx) }
    }

    private func drawOuter(_ ctx: inout GraphicsContext, _ rect: CGRect, _ o: OuterPanelColors) {
        ctx.fill(Path(rect), with: color(o.main))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 24, height: rect.height)),
                 with: .linearGradient(Gradient(colors: [o.glow.color, o.main.color]), startPoint: .zero, endPoint: CGPoint(x: 24, y: 0)))
        ctx.fill(Path(CGRect(x: rect.width - 24, y: 0, width: 24, height: rect.height)),
                 with: .linearGradient(Gradient(colors: [o.main.color, o.glow.color]), startPoint: CGPoint(x: rect.width - 24, y: 0), endPoint: CGPoint(x: rect.width, y: 0)))
        for i in 0..<7 {
            let y = rect.height - CGFloat(4 * i) - 2.5
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
            ctx.stroke(p, with: color(o.stripes, (1 - Double(i) / 7) / 2), lineWidth: 1)
        }
    }

    private func drawInner(_ ctx: inout GraphicsContext, _ r: CGRect, _ i: InnerPanelColors) {
        var s = ctx
        s.addFilter(.shadow(color: i.glow.color.opacity(0.35), radius: 4, x: 0, y: 2))
        s.fill(Path(roundedRect: r, cornerRadius: 10), with: color(i.main))
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10), with: color(i.border), lineWidth: 1)
        var line = Path()
        line.move(to: CGPoint(x: r.minX + 10, y: r.maxY + 1)); line.addLine(to: CGPoint(x: r.maxX - 10, y: r.maxY + 1))
        ctx.stroke(line, with: color(i.highlight, 0.6), lineWidth: 0.8)
    }

    private struct GridIcon { let kind: Int; let symbol: String; let tint: RGB }

    private func drawIconGrid(_ ctx: inout GraphicsContext, _ inner: CGRect) {
        let homeIcons: [GridIcon] = [
            GridIcon(kind: 1, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 3, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 2, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 0, symbol: "gamecontroller.fill", tint: RGB(230, 70, 60)),
            GridIcon(kind: 0, symbol: "camera.fill", tint: RGB(70, 150, 230)),
            GridIcon(kind: 0, symbol: "music.note", tint: RGB(240, 150, 40)),
            GridIcon(kind: 0, symbol: "globe", tint: RGB(60, 180, 120)),
            GridIcon(kind: 0, symbol: "gearshape.fill", tint: RGB(140, 140, 150)),
            GridIcon(kind: 2, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 0, symbol: "star.fill", tint: RGB(200, 90, 200)),
        ]
        let folderIcons: [GridIcon] = [
            GridIcon(kind: 3, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 2, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 0, symbol: "gamecontroller.fill", tint: RGB(230, 70, 60)),
            GridIcon(kind: 2, symbol: "", tint: RGB(0, 0, 0)),
            GridIcon(kind: 0, symbol: "puzzlepiece.fill", tint: RGB(90, 120, 220)),
        ]
        let icons = folderMode ? folderIcons : homeIcons
        let cols = 5
        let size: CGFloat = 42
        let gapX = (inner.width - CGFloat(cols) * size) / CGFloat(cols + 1)
        let startY = inner.minY + (folderMode ? 40 : 22)
        let selected = 1
        for (i, icon) in icons.enumerated() {
            let col = i % cols, row = i / cols
            let r = CGRect(x: inner.minX + gapX + CGFloat(col) * (size + gapX), y: startY + CGFloat(row) * (size + 20), width: size, height: size)
            switch icon.kind {
            case 1: drawFolderIcon(&ctx, r.insetBy(dx: 1, dy: 5), open: false)
            case 2: drawFileIcon(&ctx, r)
            case 3: drawAppIcon(&ctx, r)
            default: drawGenericIcon(&ctx, r, icon.symbol, icon.tint)
            }
            if i == selected { drawCursor(&ctx, r.insetBy(dx: -5, dy: -5)) }
        }
    }

    private func drawGenericIcon(_ ctx: inout GraphicsContext, _ r: CGRect, _ symbol: String, _ tint: RGB) {
        var s = ctx
        s.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1))
        s.fill(Path(roundedRect: r, cornerRadius: 7), with: vGradient(tint.mixed(with: RGB(255, 255, 255), 0.35), tint, r))
        ctx.draw(Text(Image(systemName: symbol)).font(.system(size: 18, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: r.midX, y: r.midY))
    }

    private func drawAppIcon(_ ctx: inout GraphicsContext, _ r: CGRect) {
        var s = ctx
        s.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1))
        if let icon {
            s.clip(to: Path(roundedRect: r, cornerRadius: 7))
            s.draw(Image(decorative: icon, scale: 1), in: r)
        } else {
            s.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(.blue))
        }
    }

    func folderPath(_ r: CGRect) -> Path {
        var p = Path()
        let tabW = r.width * 0.42, tabH = r.height * 0.16
        p.move(to: CGPoint(x: r.minX + 4, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.minX + 4, y: r.minY + 3))
        p.addQuadCurve(to: CGPoint(x: r.minX + 8, y: r.minY), control: CGPoint(x: r.minX + 4, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW - 4, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW + 4, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tabH + 4), control: CGPoint(x: r.maxX, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 4))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 4, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 4), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tabH + 4))
        p.addQuadCurve(to: CGPoint(x: r.minX + 4, y: r.minY + tabH), control: CGPoint(x: r.minX, y: r.minY + tabH))
        p.closeSubpath()
        return p
    }

    func drawFolderIcon(_ ctx: inout GraphicsContext, _ r: CGRect, open: Bool) {
        let fc = f.folderColor ? c.folder : defaults.folder
        let path = folderPath(r)
        var s = ctx
        s.addFilter(.shadow(color: fc.shadow.color.opacity(0.5), radius: r.width > 80 ? 6 : 1.5, x: 0, y: r.width > 80 ? 4 : 1))
        if f.folderTexture, let img = images[open ? .folderOpen : .folderClosed] {
            s.fill(path, with: color(fc.main))
            var clip = ctx
            clip.clip(to: path)
            clip.draw(Image(decorative: img, scale: 1), in: r)
        } else {
            s.fill(path, with: vGradient(fc.light, fc.main, r))
            var front = Path()
            let fy = r.minY + r.height * (open ? 0.45 : 0.32)
            front.addRoundedRect(in: CGRect(x: r.minX, y: fy, width: r.width, height: r.maxY - fy), cornerSize: CGSize(width: 4, height: 4))
            ctx.fill(front, with: vGradient(fc.main, fc.shading, r))
            ctx.stroke(path, with: color(fc.shading, 0.6), lineWidth: 0.8)
        }
    }

    private func drawFileIcon(_ ctx: inout GraphicsContext, _ r: CGRect) {
        let fc = f.fileColor ? c.file : defaults.file
        let card = CGRect(x: r.minX + 6, y: r.minY, width: r.width - 12, height: r.height)
        var s = ctx
        s.addFilter(.shadow(color: fc.shadow.color, radius: 2, x: 0, y: 1.5))
        if f.fileTexture, let img = images[.fileSmall] ?? images[.fileLarge] {
            s.fill(Path(roundedRect: card, cornerRadius: 3), with: color(fc.main))
            var clip = ctx
            clip.clip(to: Path(roundedRect: card, cornerRadius: 3))
            clip.draw(Image(decorative: img, scale: 1), in: card)
        } else {
            s.fill(Path(roundedRect: card, cornerRadius: 3), with: vGradient(fc.light, fc.main, card))
            ctx.stroke(Path(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: color(fc.shading), lineWidth: 1)
            let label = CGRect(x: card.minX + 4, y: card.minY + 6, width: card.width - 8, height: card.height * 0.45)
            ctx.fill(Path(roundedRect: label, cornerRadius: 2), with: color(fc.shading, 0.55))
        }
    }

    private func drawCursor(_ ctx: inout GraphicsContext, _ r: CGRect) {
        let cc = f.cursorColor ? c.cursor : defaults.cursor
        let pulse = forExport ? 0.6 : (sin(time * 4) + 1) / 2
        var g = ctx
        g.addFilter(.blur(radius: 3 + 2 * pulse))
        g.stroke(Path(roundedRect: r, cornerRadius: 9), with: color(cc.glow, 0.5 + 0.4 * pulse), lineWidth: 4)
        ctx.stroke(Path(roundedRect: r, cornerRadius: 9),
                   with: .linearGradient(Gradient(colors: [cc.light.color, cc.main.color, cc.shading.color]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)),
                   lineWidth: 3)
    }

    private func drawArrowButtons(_ ctx: inout GraphicsContext) {
        let ab = f.arrowButtonColor ? c.arrowButton : defaults.arrowButton
        let ar = f.arrowColor ? c.arrow : defaults.arrow
        let pressedRight = !forExport && Int(time / 1.5) % 4 == 3
        for (i, r) in [CGRect(x: -10, y: 102, width: 26, height: 44), CGRect(x: 304, y: 102, width: 26, height: 44)].enumerated() {
            var s = ctx
            s.addFilter(.shadow(color: ab.shadow.color, radius: 2, x: 0, y: 1))
            s.fill(Path(roundedRect: r, cornerRadius: 9), with: vGradient(ab.light, ab.main, r))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9), with: color(ab.shading), lineWidth: 1)
            let cx = i == 0 ? r.maxX - 9 : r.minX + 9
            let dir: CGFloat = i == 0 ? -1 : 1
            var tri = Path()
            tri.move(to: CGPoint(x: cx + 4 * dir, y: r.midY))
            tri.addLine(to: CGPoint(x: cx - 3 * dir, y: r.midY - 6))
            tri.addLine(to: CGPoint(x: cx - 3 * dir, y: r.midY + 6))
            tri.closeSubpath()
            let pressed = i == 1 && pressedRight
            ctx.fill(tri, with: color(pressed ? ar.pressed : ar.unpressed))
            ctx.stroke(tri, with: color(ar.border), lineWidth: 0.8)
        }
    }

    private func drawTopCorners(_ ctx: inout GraphicsContext) {
        let tc = f.topCornerColor ? c.topCorner : defaults.topCorner
        let items = [(CGRect(x: -8, y: -8, width: 62, height: 32), "sun.max.fill"),
                     (CGRect(x: 266, y: -8, width: 62, height: 32), "pencil.and.outline")]
        for (r, sym) in items {
            var s = ctx
            s.addFilter(.shadow(color: tc.shadow.color.opacity(0.45), radius: 2, x: 0, y: 1.5))
            s.fill(Path(roundedRect: r, cornerRadius: 10), with: vGradient(tc.light, tc.main, r))
            let center = CGPoint(x: r.midX + (r.minX < 0 ? 4 : -4), y: r.midY + 4)
            ctx.draw(Text(Image(systemName: sym)).font(.system(size: 12, weight: .bold)).foregroundColor(tc.text.color), at: center)
        }
    }

    private func drawBottomCorners(_ ctx: inout GraphicsContext) {
        let bc = f.bottomCornerColor ? c.bottomCorner : defaults.bottomCorner
        let items = [(CGRect(x: -8, y: 214, width: 62, height: 34), "square.grid.3x3.fill"),
                     (CGRect(x: 266, y: 214, width: 62, height: 34), "paintbrush.fill")]
        for (r, sym) in items {
            var s = ctx
            s.addFilter(.shadow(color: bc.baseShadow.color.opacity(0.45), radius: 2, x: 0, y: -1))
            s.fill(Path(roundedRect: r, cornerRadius: 10), with: vGradient(bc.highlight, bc.main, r))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10), with: color(bc.border), lineWidth: 1)
            let center = CGPoint(x: r.midX + (r.minX < 0 ? 4 : -4), y: r.midY - 4)
            let iconRect = CGRect(x: center.x - 9, y: center.y - 8, width: 18, height: 16)
            var mask = ctx
            mask.clipToLayer { layer in
                layer.draw(Text(Image(systemName: sym)).font(.system(size: 13, weight: .bold)), at: center)
            }
            mask.fill(Path(iconRect), with: vGradient(bc.iconTop, bc.iconBottom, iconRect))
        }
    }

    private func drawOpenClose(_ ctx: inout GraphicsContext) {
        let oc = f.openCloseColor ? (folderMode ? c.close : c.open) : (folderMode ? defaults.close : defaults.open)
        let pressed = !forExport && Int(time / 2) % 5 == 4
        let r = CGRect(x: 112, y: 213, width: 96, height: 24)
        var s = ctx
        s.addFilter(.shadow(color: oc.shadow.color, radius: 2.5, x: 0, y: 1.5))
        s.fill(Path(roundedRect: r, cornerRadius: 12), with: vGradient(oc.light, pressed ? oc.pressed : oc.unpressed, r))
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 12), with: color(oc.glow, 0.7), lineWidth: 1)
        let label = folderMode ? "Close" : "Open"
        let center = CGPoint(x: r.midX, y: r.midY)
        let dy = CGFloat(max(-3, min(3, oc.textShadowPosition)))
        ctx.draw(text(label, size: 13, weight: .bold, color: oc.textShadow), at: CGPoint(x: center.x, y: center.y - dy))
        ctx.draw(text(label, size: 13, weight: .bold, color: pressed ? oc.textPressed : oc.textUnpressed), at: center)
    }

    private func drawFolderArrow(_ ctx: inout GraphicsContext) {
        let fa = f.folderArrowColor ? c.folderArrow : defaults.folderArrow
        let r = CGRect(x: 20, y: 46, width: 46, height: 26)
        var s = ctx
        s.addFilter(.shadow(color: fa.shadow.color, radius: 2, x: 0, y: 1.5))
        s.fill(Path(roundedRect: r, cornerRadius: 13), with: vGradient(fa.highlight, fa.main, r))
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 13), with: color(fa.shading), lineWidth: 1)
        var g = ctx
        g.addFilter(.blur(radius: 1.5))
        g.draw(Text(Image(systemName: "arrow.uturn.backward")).font(.system(size: 13, weight: .black)).foregroundColor(fa.arrowGlow.color), at: CGPoint(x: r.midX, y: r.midY))
        ctx.draw(Text(Image(systemName: "arrow.uturn.backward")).font(.system(size: 13, weight: .black)).foregroundColor(fa.arrowUnpressed.color), at: CGPoint(x: r.midX, y: r.midY))
        // Folder name label in the panel
        let name = CGRect(x: 76, y: 48, width: 150, height: 22)
        ctx.fill(Path(roundedRect: name, cornerRadius: 6), with: color(fa.main, 0.85))
        ctx.draw(text("My Folder", size: 12, weight: .bold, color: fa.arrowUnpressed), at: CGPoint(x: name.midX, y: name.midY))
    }
}

/// Animated (or static) view of both screens.
struct ConsoleScreensView: View {
    @Environment(ThemeDocument.self) private var doc
    var scale: CGFloat
    var animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animate)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let renderer = PreviewRenderer(theme: doc.theme, images: doc.previewImages, icon: doc.iconImage,
                                           folderMode: doc.previewFolderMode, time: animate ? t : 0, forExport: false)
            VStack(spacing: 14 * scale) {
                ScreenBezel(scale: scale) {
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: scale, y: scale)
                        var c = ctx
                        renderer.drawTop(&c)
                    }
                    .frame(width: 412 * scale, height: 240 * scale)
                }
                ScreenBezel(scale: scale) {
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: scale, y: scale)
                        var c = ctx
                        renderer.drawBottom(&c)
                    }
                    .frame(width: 320 * scale, height: 240 * scale)
                }
            }
        }
    }
}

struct ScreenBezel<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
            .padding(8 * scale)
            .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 10 * scale, y: 4 * scale)
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
