import SwiftUI
import AppKit
import ThemeKit
import UniformTypeIdentifiers

/// Full-size editor for a texture slot: position, resize, rotate, flip and color-correct a picture,
/// previewed exactly as it will be converted for the 3DS.
struct ImageEditorView: View {
    @Environment(ThemeDocument.self) private var doc
    @Environment(\.dismiss) private var dismiss
    let slot: TextureSlot
    let title: String

    @State private var edit = ImageEdit()
    @State private var original = ImageEdit()
    @State private var adjusted: CGImage?
    @State private var preview: CGImage?
    @State private var consoleColors = true
    @State private var showGuides = true
    @State private var dragOrigin: CGPoint?
    @State private var zoomOrigin: Double?
    @State private var commitTask: Task<Void, Never>?

    private var visible: (Int, Int) { ThemeGeometry.visibleSize(slot, flags: doc.theme.flags) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                canvas
                Divider()
                ScrollView { inspector.padding(16) }
                    .frame(width: 320)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            Divider()
            footer
        }
        .frame(minWidth: 1040, idealWidth: 1180, minHeight: 660, idealHeight: 740)
        .onAppear(perform: load)
        .onChange(of: edit) { old, new in
            if old.colorKey != new.colorKey, let src = doc.sources[slot] { adjusted = ImageOps.adjusted(src.image, new) }
            refresh()
            scheduleCommit()
        }
        .onChange(of: consoleColors) { _, _ in refresh() }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let vw = visible.0
            let vh = visible.1
            let scale = min((geo.size.width - 48) / CGFloat(vw), (geo.size.height - 80) / CGFloat(vh), slot.format == .rgb565 ? 3 : 6)
            let w = CGFloat(vw) * scale, h = CGFloat(vh) * scale
            ZStack {
                LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        Checkerboard()
                        if let preview {
                            Image(decorative: preview, scale: 1)
                                .resizable()
                                .interpolation(scale >= 2 ? .none : .medium)
                        }
                        if showGuides {
                            GuidesOverlay(slot: slot, flags: doc.theme.flags, scale: scale)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                    .gesture(dragGesture(scale: scale))
                    .simultaneousGesture(zoomGesture)
                    .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }

                    Text("Drag to move · Pinch or use the Zoom slider to resize · \(vw) × \(vh) px\(consoleColors ? " · showing 3DS colors" : "")")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(minWidth: 680)
    }

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if dragOrigin == nil { dragOrigin = CGPoint(x: edit.offsetX, y: edit.offsetY) }
                guard let o = dragOrigin else { return }
                edit.offsetX = (o.x + v.translation.width / scale).rounded()
                edit.offsetY = (o.y + v.translation.height / scale).rounded()
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomOrigin == nil { zoomOrigin = edit.zoom }
                edit.zoom = min(4, max(0.1, (zoomOrigin ?? 1) * v.magnification))
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit \(title)").font(.title3.weight(.bold))
                if let name = doc.sources[slot]?.fileName {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            InspectorGroup(title: "Size & Position", symbol: "arrow.up.left.and.arrow.down.right") {
                Picker("Fit", selection: $edit.fit) {
                    Text("Fill").tag(FitMode.fill)
                    Text("Fit").tag(FitMode.fit)
                    Text("Stretch").tag(FitMode.stretch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(fitHelp).font(.caption).foregroundStyle(.secondary)
                AdjustSlider(label: "Zoom", value: $edit.zoom, range: 0.1...4, neutral: 1) { String(format: "%.0f%%", $0 * 100) }
                AdjustSlider(label: "Move X", value: $edit.offsetX, range: -Double(visible.0)...Double(visible.0), neutral: 0, step: 1) { String(format: "%+.0f px", $0) }
                AdjustSlider(label: "Move Y", value: $edit.offsetY, range: -Double(visible.1)...Double(visible.1), neutral: 0, step: 1) { String(format: "%+.0f px", $0) }
                HStack {
                    Button("Center") { edit.offsetX = 0; edit.offsetY = 0 }
                    Button("Fit Whole Picture") { edit.fit = .fit; edit.zoom = 1; edit.offsetX = 0; edit.offsetY = 0 }
                }
                .controlSize(.small)
            }

            InspectorGroup(title: "Rotate & Flip", symbol: "rotate.right") {
                HStack {
                    Button { edit.quarterTurns -= 1 } label: { Label("Left", systemImage: "rotate.left") }
                    Button { edit.quarterTurns += 1 } label: { Label("Right", systemImage: "rotate.right") }
                    Spacer()
                    Toggle(isOn: $edit.flipHorizontal) { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                        .toggleStyle(.button).help("Flip horizontally")
                    Toggle(isOn: $edit.flipVertical) { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                        .toggleStyle(.button).help("Flip vertically")
                }
                .controlSize(.small)
                AdjustSlider(label: "Straighten", value: $edit.angle, range: -45...45, neutral: 0, step: 0.5) { String(format: "%+.1f°", $0) }
            }

            InspectorGroup(title: "Background Fill", symbol: "square.dashed") {
                ColorRow(label: "Empty areas", help: "Shown where the picture doesn't cover (Fit mode, zoomed out or rotated).", color: $edit.background)
                if let c = edgeColor {
                    Button("Match Picture Edge") { edit.background = c }.controlSize(.small)
                }
            }

            InspectorGroup(title: "Color", symbol: "camera.filters") {
                AdjustSlider(label: "Brightness", value: $edit.brightness, range: -1...1, neutral: 0) { String(format: "%+.0f", $0 * 100) }
                AdjustSlider(label: "Contrast", value: $edit.contrast, range: 0.25...2, neutral: 1) { String(format: "%.0f%%", $0 * 100) }
                AdjustSlider(label: "Saturation", value: $edit.saturation, range: 0...2, neutral: 1) { String(format: "%.0f%%", $0 * 100) }
                AdjustSlider(label: "Hue", value: $edit.hue, range: -180...180, neutral: 0, step: 1) { String(format: "%+.0f°", $0) }
                AdjustSlider(label: "Warmth", value: $edit.warmth, range: -1...1, neutral: 0) { String(format: "%+.0f", $0 * 100) }
                AdjustSlider(label: "Sharpen", value: $edit.sharpen, range: 0...2, neutral: 0) { String(format: "%.0f", $0 * 50) }
                AdjustSlider(label: "Blur", value: $edit.blur, range: 0...20, neutral: 0, step: 0.5) { String(format: "%.1f px", $0) }
                AdjustSlider(label: "Vignette", value: $edit.vignette, range: 0...2, neutral: 0) { String(format: "%.0f", $0 * 50) }
                HStack(spacing: 6) {
                    presetButton("Vivid") { $0.saturation = 1.35; $0.contrast = 1.12 }
                    presetButton("Soft") { $0.contrast = 0.85; $0.brightness = 0.08; $0.saturation = 0.9 }
                    presetButton("Dim") { $0.brightness = -0.25; $0.contrast = 0.9 }
                    presetButton("B&W") { $0.saturation = 0; $0.contrast = 1.1 }
                }
                Button("Reset Colors") { edit.resetColor() }.controlSize(.small)
            }

            InspectorGroup(title: "Preview", symbol: "eye") {
                Toggle("Show real 3DS colors", isOn: $consoleColors)
                    .help("Simulates the console's 16-bit color (and dithering) so there are no surprises.")
                if slot.format == .rgb565 {
                    Toggle("Dithering (smoother gradients)", isOn: Binding(get: { doc.theme.ditherBackgrounds },
                                                                            set: { doc.theme.ditherBackgrounds = $0; refresh() }))
                }
                Toggle("Show screen guides", isOn: $showGuides)
            }
        }
    }

    private func presetButton(_ name: String, _ apply: @escaping (inout ImageEdit) -> Void) -> some View {
        Button(name) {
            var e = edit
            e.resetColor()
            apply(&e)
            edit = e
        }
        .controlSize(.small)
    }

    private var fitHelp: String {
        switch edit.fit {
        case .fill: return "Covers the whole area; edges may be cropped."
        case .fit: return "Shows the whole picture; empty space uses the background fill."
        case .stretch: return "Squeezes the picture to the exact size."
        }
    }

    private var edgeColor: RGB? {
        guard let src = doc.sources[slot] else { return nil }
        let small = ImageOps.render(src.adjusted, width: 8, height: 8, mode: .stretch)
        var r = 0, g = 0, b = 0, n = 0
        for y in 0..<8 { for x in 0..<8 where x == 0 || y == 0 || x == 7 || y == 7 {
            let p = small.pixel(x, y); r += Int(p.r); g += Int(p.g); b += Int(p.b); n += 1
        } }
        return RGB(UInt8(r / n), UInt8(g / n), UInt8(b / n))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset All") { edit.resetGeometry(); edit.resetColor(); edit.fit = original.fit }
            Button("Export as PNG…") { exportPNG() }
            Spacer()
            Button("Cancel") {
                commitTask?.cancel()
                doc.setEdit(original, for: slot)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Done") {
                commitTask?.cancel()
                doc.setEdit(edit, for: slot)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    // MARK: Logic

    private func load() {
        guard let src = doc.sources[slot] else { return }
        edit = src.edit
        original = src.edit
        adjusted = src.adjusted
        refresh()
    }

    private func refresh() {
        guard let adjusted else { return }
        var rgb = doc.previewRender(slot: slot, edit: edit, adjusted: adjusted)
        if consoleColors { rgb = ImageOps.consolePreview(rgb, format: slot.format, dither: doc.theme.ditherBackgrounds) }
        preview = ImageOps.cgImage(rgb)
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        let e = edit
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            doc.setEdit(e, for: slot)
        }
    }

    private func exportPNG() {
        guard let adjusted,
              let cg = ImageOps.cgImage(doc.previewRender(slot: slot, edit: edit, adjusted: adjusted)),
              let png = ImageOps.pngData(cg),
              let url = FilePanels.save(name: "\(title).png", type: .png, title: "Export Edited Image") else { return }
        do { try png.write(to: url); doc.status("Saved \(url.lastPathComponent).") }
        catch { doc.errorMessage = error.localizedDescription }
    }
}

/// Labeled slider that shows its value and resets on double-click.
struct AdjustSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutral: Double
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit())
                    .foregroundStyle(value == neutral ? Color.secondary : Color.accentColor)
                    .onTapGesture(count: 2) { value = neutral }
                    .help("Double-click to reset")
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

struct InspectorGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
    }
}

/// Lines showing where the 3DS screens, 3D margins and icon panel fall on the picture.
struct GuidesOverlay: View {
    let slot: TextureSlot
    let flags: ThemeFlags
    let scale: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let dash = StrokeStyle(lineWidth: 1, dash: [5, 4])
            func vline(_ x: CGFloat, _ color: Color) {
                var p = Path(); p.move(to: CGPoint(x: x * scale, y: 0)); p.addLine(to: CGPoint(x: x * scale, y: size.height))
                ctx.stroke(p, with: .color(color), style: dash)
            }
            func label(_ s: String, _ x: CGFloat, _ y: CGFloat) {
                ctx.draw(Text(s).font(.system(size: 10, weight: .semibold)).foregroundColor(.white),
                         at: CGPoint(x: x * scale + 4, y: y * scale + 3), anchor: .topLeading)
            }
            switch slot {
            case .top:
                if flags.topFrameType.scrolls {
                    ctx.stroke(Path(CGRect(x: 0, y: 0, width: 412 * scale, height: 240 * scale)), with: .color(.yellow.opacity(0.8)), style: dash)
                    ctx.stroke(Path(CGRect(x: (1008 - 412) * scale, y: 0, width: 412 * scale, height: 240 * scale)), with: .color(.yellow.opacity(0.8)), style: dash)
                    label("First screen", 6, 4)
                    label("Last screen", 1008 - 412 + 6, 4)
                } else {
                    vline(6, .red.opacity(0.7)); vline(406, .red.opacity(0.7))
                    label("3D only", 6, 4)
                }
            case .bottom:
                let pages: [CGFloat]
                switch flags.bottomFrameType {
                case .single: pages = [0]
                case .pageScroll, .bounceScroll: pages = [0, 320, 640]
                case .slowScroll, .fastScroll: pages = [0, 1008 - 320]
                }
                for (i, x) in pages.enumerated() {
                    ctx.stroke(Path(CGRect(x: x * scale, y: 0, width: 320 * scale, height: 240 * scale)), with: .color(.yellow.opacity(0.8)), style: dash)
                    ctx.stroke(Path(roundedRect: CGRect(x: (x + 12) * scale, y: 39 * scale, width: 296 * scale, height: 170 * scale), cornerRadius: 10 * scale),
                               with: .color(.white.opacity(0.55)), style: dash)
                    if pages.count > 1 { label("Screen \(i + 1)", x + 4, 4) }
                }
                label("Icons area", (pages.first ?? 0) + 14, 41)
            default:
                var h = Path(); h.move(to: CGPoint(x: 0, y: size.height / 2)); h.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                var v = Path(); v.move(to: CGPoint(x: size.width / 2, y: 0)); v.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                ctx.stroke(h, with: .color(.white.opacity(0.35)), style: dash)
                ctx.stroke(v, with: .color(.white.opacity(0.35)), style: dash)
            }
        }
        .allowsHitTesting(false)
    }
}
