import SwiftUI
import AppKit
import ThemeKit
import UniformTypeIdentifiers

// MARK: - Color conversion

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1) }
    var cgColor: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func c(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(c(ns.redComponent), c(ns.greenComponent), c(ns.blueComponent))
    }

    func mixed(with o: RGB, _ t: Double) -> RGB {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(a) * (1 - t) + Double(b) * t))) }
        return RGB(m(r, o.r), m(g, o.g), m(b, o.b))
    }

    var luminance: Double { (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255) }
}

extension Binding where Value == RGB {
    var swiftUIColor: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGB($0) })
    }
}

// MARK: - File panels

@MainActor
enum FilePanels {
    static func open(types: [UTType], title: String, allowFolders: Bool = false) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.allowedContentTypes = types
        p.canChooseDirectories = allowFolders
        p.canChooseFiles = true
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url : nil
    }

    static func save(name: String, type: UTType, title: String) -> URL? {
        let p = NSSavePanel()
        p.title = title
        p.nameFieldStringValue = name
        p.allowedContentTypes = [type]
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    static func chooseFolder(title: String, prompt: String) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.prompt = prompt
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    static let imageTypes: [UTType] = [.png, .jpeg, .gif, .bmp, .tiff, .heic, .webP, .image]
    static let audioTypes: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio, UTType(filenameExtension: "flac") ?? .audio,
                                       UTType(filenameExtension: "bcstm") ?? .data]
    static let sfxTypes: [UTType] = [.audio, .wav, .mp3, .aiff, UTType(filenameExtension: "bcwav") ?? .data]
}

// MARK: - Layout pieces

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

struct PageHeader: View {
    let section: EditorSection
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: section.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.title2.weight(.bold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }
}

struct CardHeader: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// A card with an on/off switch that maps to a theme flag.
struct ToggleCard<Content: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    @Binding var isOn: Bool
    var offText = "Uses the standard HOME Menu look. Turn on to customize."
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            HStack(alignment: .center) {
                CardHeader(title: title, symbol: symbol, subtitle: subtitle)
                Spacer()
                Toggle("Customize \(title)", isOn: $isOn.animation(.snappy))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(isOn ? "Using custom colors" : "Using default colors")
            }
            if isOn {
                Divider()
                content
            } else {
                Text(offText).font(.callout).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Color editing

struct HexField: View {
    @Binding var color: RGB
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("#RRGGBB", text: $text)
            .font(.system(.callout, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 84)
            .focused($focused)
            .onAppear { text = color.hex }
            .onChange(of: color) { _, c in if !focused { text = c.hex } }
            .onSubmit { commit() }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .help("Hex color code")
    }

    private func commit() {
        if let c = RGB(hex: text) { color = c } else { text = color.hex }
    }
}

struct ColorRow: View {
    let label: String
    var help: String? = nil
    @Binding var color: RGB
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if let help { Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            HexField(color: $color)
            ColorPicker(label, selection: $color.swiftUIColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(dropTargeted ? Color.accentColor.opacity(0.15) : .clear))
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let c = RGB(hex: s) else { return false }
            color = c
            return true
        } isTargeted: { dropTargeted = $0 }
    }
}

struct ColorAlphaRow: View {
    let label: String
    var help: String? = nil
    @Binding var color: RGBA

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ColorRow(label: label, help: help, color: $color.rgb)
            HStack {
                Text("Opacity").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Slider(value: Binding(get: { Double(color.a) }, set: { color.a = UInt8($0) }), in: 0...255)
                    .controlSize(.small)
                Text("\(Int(Double(color.a) / 2.55))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 6)
        }
    }
}

struct PercentSlider: View {
    let label: String
    var help: String? = nil
    @Binding var value: UInt8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int((Double(value) / 2.55).rounded()))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = UInt8($0.rounded()) }), in: 0...255)
            if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
    }
}

/// Colors pulled from the wallpapers that can be dragged onto any color row.
struct PaletteStrip: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        if !doc.palette.isEmpty {
            Card {
                CardHeader(title: "Wallpaper Palette", symbol: "eyedropper.halffull",
                           subtitle: "Drag a swatch onto any color below. Click to copy its hex code.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 6)], spacing: 6) {
                    ForEach(doc.palette, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(c.color)
                            .frame(width: 26, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.15)))
                            .draggable(c.hex)
                            .help(c.hex)
                            .onTapGesture {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(c.hex, forType: .string)
                                doc.status("Copied \(c.hex)")
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Image slots

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) {
                    let dark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(dark ? .gray.opacity(0.25) : .gray.opacity(0.1)))
                }
            }
        }
    }
}

struct ImageSlotView: View {
    @Environment(ThemeDocument.self) private var doc
    let slot: TextureSlot
    let title: String
    let detail: String
    var showPositioning = false
    var thumbHeight: CGFloat = 120
    @State private var targeted = false
    @State private var editing = false

    private var visible: (Int, Int) { ThemeGeometry.visibleSize(slot, flags: doc.theme.flags) }
    private var canvas: (Int, Int) { ThemeGeometry.canvasSize(slot, flags: doc.theme.flags) }

    private var thumbnail: CGImage? {
        guard let img = doc.previewImages[slot] else { return nil }
        let (w, h) = visible
        return img.cropping(to: CGRect(x: 0, y: 0, width: min(w, img.width), height: min(h, img.height))) ?? img
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(sizeLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }

            ZStack {
                Checkerboard()
                if let thumb = thumbnail {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .interpolation(slot.format == .rgb565 ? .medium : .none)
                        .aspectRatio(contentMode: .fit)
                        .background(slot.format == .a8 ? Color.black : Color.clear)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
                        Text("Drop any picture here — it's resized automatically").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(targeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: thumbnail == nil ? [5, 4] : []))
            )
            .contentShape(Rectangle())
            .onTapGesture { if doc.sources[slot] != nil { editing = true } else { choose() } }
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }
                doc.loadImage(from: u, into: slot)
                return true
            } isTargeted: { targeted = $0 }

            HStack(spacing: 8) {
                Button { choose() } label: { Label(doc.sources[slot] == nil ? "Choose…" : "Replace…", systemImage: "folder") }
                if doc.sources[slot] != nil {
                    Button { editing = true } label: { Label("Edit…", systemImage: "slider.horizontal.below.rectangle") }
                        .help("Crop, resize, rotate, flip and adjust colors")
                    Picker("Fit", selection: Binding(get: { doc.sources[slot]?.edit.fit ?? .fill },
                                                     set: { v in doc.updateEdit(slot) { $0.fit = v } })) {
                        ForEach(FitMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    Spacer()
                    Button(role: .destructive) { doc.clearImage(slot) } label: { Label("Remove", systemImage: "trash") }
                } else {
                    Spacer()
                }
            }
            .controlSize(.small)
        }
        .sheet(isPresented: $editing) {
            ImageEditorView(slot: slot, title: title)
                .environment(doc)
        }
    }

    private var sizeLabel: String {
        let (vw, vh) = visible, (cw, ch) = canvas
        return vw == cw && vh == ch ? "\(cw) × \(ch)" : "\(vw) × \(vh) visible"
    }

    private func choose() {
        if let u = FilePanels.open(types: FilePanels.imageTypes, title: "Choose an image for \(title)") {
            doc.loadImage(from: u, into: slot)
        }
    }
}

/// Big segmented choice with icons, used for the screen modes.
struct ModePicker<T: Hashable>: View {
    let options: [(T, String, String)]   // value, title, symbol
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let selected = opt.0 == selection
                Button {
                    withAnimation(.snappy) { selection = opt.0 }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: opt.2).font(.system(size: 18, weight: .medium))
                        Text(opt.1).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct InfoBanner: View {
    let text: String
    var symbol = "lightbulb"
    var tint: Color = .accentColor
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.08)))
    }
}

struct SizeMeter: View {
    let label: String
    let used: Int
    let limit: Int
    var body: some View {
        let frac = limit > 0 ? Double(used) / Double(limit) : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text("\(formatBytes(used)) of \(formatBytes(limit))").font(.caption.monospacedDigit())
                    .foregroundStyle(frac > 1 ? .red : .secondary)
            }
            ProgressView(value: min(frac, 1))
                .tint(frac > 1 ? .red : (frac > 0.85 ? .orange : .accentColor))
        }
    }
}
