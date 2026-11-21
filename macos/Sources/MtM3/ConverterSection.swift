import SwiftUI
import AppKit
import ThemeKit
import UniformTypeIdentifiers

/// Image sizes the converter can produce.
enum ImageTarget: String, CaseIterable, Identifiable {
    case topStill, topScroll, bottomStill, bottomPages, bottomScroll, folder, fileLarge, fileSmall, icon, pattern
    var id: String { rawValue }

    var title: String {
        switch self {
        case .topStill: return "Top screen — still (412 × 240)"
        case .topScroll: return "Top screen — scrolling (1008 × 240)"
        case .bottomStill: return "Bottom screen — still (320 × 240)"
        case .bottomPages: return "Bottom screen — page flip/bounce (960 × 240)"
        case .bottomScroll: return "Bottom screen — scrolling (1008 × 240)"
        case .folder: return "Folder picture (128 × 64)"
        case .fileLarge: return "File picture, large (64 × 128)"
        case .fileSmall: return "File picture, small (32 × 64)"
        case .icon: return "Theme icon (48 × 48)"
        case .pattern: return "Top pattern (64 × 64)"
        }
    }

    var size: (Int, Int) {
        switch self {
        case .topStill: return (412, 240)
        case .topScroll: return (1008, 240)
        case .bottomStill: return (320, 240)
        case .bottomPages: return (960, 240)
        case .bottomScroll: return (1008, 240)
        case .folder: return (128, 64)
        case .fileLarge: return (64, 128)
        case .fileSmall: return (32, 64)
        case .icon: return (48, 48)
        case .pattern: return (64, 64)
        }
    }

    /// Where "Use in Theme" puts the picture, plus the frame setting it implies.
    @MainActor
    func apply(_ image: CGImage, to doc: ThemeDocument) {
        switch self {
        case .topStill: doc.theme.flags.topFrameType = .single; doc.setImage(image, for: .top)
        case .topScroll: doc.theme.flags.topFrameType = .slowScroll; doc.setImage(image, for: .top)
        case .bottomStill: doc.theme.flags.bottomFrameType = .single; doc.setImage(image, for: .bottom)
        case .bottomPages: doc.theme.flags.bottomFrameType = .pageScroll; doc.setImage(image, for: .bottom)
        case .bottomScroll: doc.theme.flags.bottomFrameType = .slowScroll; doc.setImage(image, for: .bottom)
        case .folder: doc.setImage(image, for: .folderClosed); doc.setImage(image, for: .folderOpen)
        case .fileLarge: doc.setImage(image, for: .fileLarge)
        case .fileSmall: doc.setImage(image, for: .fileSmall)
        case .icon: doc.setIcon(image)
        case .pattern: doc.setImage(image, for: .topPattern)
        }
    }
}

struct ConverterSection: View {
    @Environment(ThemeDocument.self) private var doc

    // Music
    @State private var musicURL: URL?
    @State private var musicRate = 32000
    @State private var musicMono = false
    @State private var musicLoopStart: Double = 0
    @State private var musicEdit = AudioEdit()
    // Sound effect
    @State private var sfxURL: URL?
    @State private var sfxRate = 22050
    // Decode
    @State private var nintendoURL: URL?
    // Image
    @State private var imageURL: URL?
    @State private var imageTarget: ImageTarget = .topStill
    @State private var imageFit: FitMode = .fill
    @State private var imageBackground = RGB(0, 0, 0)

    @State private var busy: String?
    @State private var progress: Double = 0

    var body: some View {
        EditorPage {
            PageHeader(section: .converter, text: "Turn everyday files into the formats the 3DS needs (and back again). Everything happens on your Mac, so you don't need any other converters.")

            if let busy {
                Card {
                    HStack(spacing: 12) {
                        ProgressView(value: progress > 0 ? progress : nil).frame(width: 160)
                        Text(busy).foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: MP3 → BCSTM
            Card {
                CardHeader(title: "Music → BCSTM", symbol: "music.note",
                           subtitle: "MP3, WAV, M4A/AAC, AIFF, FLAC or CAF → looping bgm.bcstm (DSP-ADPCM).")
                DropField(url: $musicURL, types: FilePanels.audioTypes.filter { $0 != UTType(filenameExtension: "bcstm") }, prompt: "Drop a song here")
                Picker("Quality", selection: $musicRate) {
                    Text("22 kHz").tag(22050); Text("32 kHz").tag(32000); Text("44 kHz").tag(44100)
                }
                .pickerStyle(.segmented)
                Toggle("Mono (fits twice as much music)", isOn: $musicMono)
                AdjustSlider(label: "Start at", value: $musicEdit.startSeconds, range: 0...600, neutral: 0, step: 0.5) { ThemeDocument.formatTime($0) }
                AdjustSlider(label: "Loop back to", value: $musicLoopStart, range: 0...600, neutral: 0, step: 0.5) { $0 == 0 ? "Beginning" : ThemeDocument.formatTime($0) }
                AdjustSlider(label: "Fade out", value: $musicEdit.fadeOutSeconds, range: 0...10, neutral: 0, step: 0.5) { $0 == 0 ? "Off" : String(format: "%.1f s", $0) }
                Toggle("Normalize volume", isOn: $musicEdit.normalize)
                HStack {
                    Spacer()
                    Button("Convert & Save…") { convertMusic(useInTheme: false) }.disabled(musicURL == nil || busy != nil)
                    Button("Use as Theme Music") { useMusicInTheme() }.buttonStyle(.borderedProminent).disabled(musicURL == nil || busy != nil)
                }
                Text("Songs longer than the 3DS limit (\(ThemeDocument.formatTime(maxSeconds))) at these settings are trimmed automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // MARK: Audio → BCWAV
            Card {
                CardHeader(title: "Sound → BCWAV", symbol: "speaker.wave.2",
                           subtitle: "Short sounds for HOME Menu sound effects. Silence is trimmed and volume is leveled.")
                DropField(url: $sfxURL, types: FilePanels.audioTypes, prompt: "Drop a short sound here")
                Picker("Quality", selection: $sfxRate) {
                    Text("16 kHz (smallest)").tag(16000); Text("22 kHz").tag(22050); Text("32 kHz").tag(32000)
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    Button("Convert & Save…") { convertSound() }.disabled(sfxURL == nil || busy != nil)
                }
            }

            // MARK: Nintendo audio → WAV
            Card {
                CardHeader(title: "BCSTM / BCWAV → WAV", symbol: "waveform",
                           subtitle: "Turn 3DS audio back into a normal WAV you can open in any audio app.")
                DropField(url: $nintendoURL, types: [UTType(filenameExtension: "bcstm") ?? .data, UTType(filenameExtension: "bcwav") ?? .data, .data],
                          prompt: "Drop a .bcstm or .bcwav here")
                HStack {
                    if let u = nintendoURL, u.pathExtension.lowercased() == "bcstm" || u.pathExtension.lowercased() == "bcwav" {
                        Button { previewNintendo() } label: { Label("Play", systemImage: "play.fill") }
                        Button { doc.player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    }
                    Spacer()
                    Button("Convert & Save…") { convertToWav() }.disabled(nintendoURL == nil || busy != nil)
                }
            }

            // MARK: Image → 3DS size
            Card {
                CardHeader(title: "Picture Resizer", symbol: "photo.on.rectangle.angled",
                           subtitle: "Resize any picture to an exact 3DS theme size. For full control, add it to the theme and click Edit….")
                DropField(url: $imageURL, types: FilePanels.imageTypes, prompt: "Drop a picture here")
                Picker("Size", selection: $imageTarget) {
                    ForEach(ImageTarget.allCases) { Text($0.title).tag($0) }
                }
                Picker("Fit", selection: $imageFit) {
                    ForEach(FitMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if imageFit == .fit { ColorRow(label: "Background", color: $imageBackground) }
                if let preview = resizedPreview {
                    HStack {
                        Spacer()
                        Image(decorative: preview, scale: 1)
                            .resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                }
                HStack {
                    Spacer()
                    Button("Save PNG…") { saveResized() }.disabled(imageURL == nil)
                    Button("Use in Theme") { useImageInTheme() }.buttonStyle(.borderedProminent).disabled(imageURL == nil)
                }
            }

            // MARK: Theme extractor
            Card {
                CardHeader(title: "Extract a Theme", symbol: "shippingbox",
                           subtitle: "Pull the wallpapers, icons, music and sounds out of any theme (folder, .zip or body_LZ.bin) as PNG and WAV files.")
                HStack {
                    Spacer()
                    Button("Choose Theme & Extract…") { extractTheme() }.disabled(busy != nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private var maxSeconds: Double {
        let ch = Double(musicMono ? 1 : 2)
        return Double(ThemeLimits.maxBGM - 0x1000) / (Double(musicRate) * 8.0 / 14.0 * ch)
    }

    private var resizedPreview: CGImage? {
        guard let u = imageURL, let img = ImageOps.loadCGImage(url: u) else { return nil }
        let (w, h) = imageTarget.size
        var e = ImageEdit(fit: imageFit)
        e.background = imageBackground
        return ImageOps.cgImage(ImageOps.render(ImageOps.limitSize(img), width: w, height: h, edit: e))
    }

    private func run(_ label: String, _ work: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) throws -> Void) {
        busy = label
        progress = 0
        Task {
            let result: Error? = await Task.detached(priority: .userInitiated) { () -> Error? in
                do {
                    try work { p in Task { @MainActor in progress = p } }
                    return nil
                } catch { return error }
            }.value
            busy = nil
            if let result { doc.errorMessage = result.localizedDescription } else { doc.status("Done!") }
        }
    }

    nonisolated private static func preparedMusic(from url: URL, rate: Int, mono: Bool, edit: AudioEdit, loopStart: Double) throws -> PCMAudio {
        var pcm = AudioProcess.apply(try AudioImport.load(url: url, sampleRate: rate, channels: mono ? 1 : 2, maxSeconds: 900), edit)
        let limit = Double(ThemeLimits.maxBGM - 0x1000) / (Double(rate) * 8.0 / 14.0 * Double(mono ? 1 : 2))
        let maxSamples = Int(limit * Double(rate))
        if pcm.sampleCount > maxSamples { pcm.channels = pcm.channels.map { Array($0.prefix(maxSamples)) } }
        pcm.looping = true
        pcm.loopStart = min(Int(loopStart * Double(rate)), max(0, pcm.sampleCount - 14336))
        return pcm
    }

    private func convertMusic(useInTheme: Bool) {
        guard let src = musicURL,
              let out = FilePanels.save(name: "bgm.bcstm", type: UTType(filenameExtension: "bcstm") ?? .data, title: "Save BCSTM") else { return }
        let rate = musicRate, mono = musicMono, edit = musicEdit, loop = musicLoopStart
        run("Converting \(src.lastPathComponent) to BCSTM…") { progress in
            let pcm = try Self.preparedMusic(from: src, rate: rate, mono: mono, edit: edit, loopStart: loop)
            let bytes = BCSTM.encode(pcm, progress: progress)
            try Data(bytes).write(to: out)
        }
    }

    private func useMusicInTheme() {
        guard let src = musicURL else { return }
        doc.bgmSettings.sampleRate = musicRate
        doc.bgmSettings.mono = musicMono
        doc.bgmSettings.edit = musicEdit
        doc.bgmSettings.loopStartSeconds = musicLoopStart
        doc.importMusic(url: src)
        doc.selection = .music
    }

    private func convertSound() {
        guard let src = sfxURL,
              let out = FilePanels.save(name: src.deletingPathExtension().lastPathComponent + ".bcwav",
                                        type: UTType(filenameExtension: "bcwav") ?? .data, title: "Save BCWAV") else { return }
        let rate = sfxRate
        run("Converting \(src.lastPathComponent) to BCWAV…") { _ in
            var e = AudioEdit(); e.trimSilence = true; e.maxSeconds = 4
            let pcm = AudioProcess.apply(try AudioImport.load(url: src, sampleRate: rate, channels: 1, maxSeconds: 10), e)
            try Data(BCWAV.encode(pcm)).write(to: out)
        }
    }

    private func decodeNintendo(_ url: URL) throws -> PCMAudio {
        let bytes = [UInt8](try Data(contentsOf: url))
        if bytes.count >= 4 && bytes[0] == 0x43 && bytes[1] == 0x57 { return try BCWAV.decode(bytes) }   // "CW"
        return try BCSTM.decode(bytes).0
    }

    private func previewNintendo() {
        guard let u = nintendoURL else { return }
        do { doc.player.play(try decodeNintendo(u), loop: true) }
        catch { doc.errorMessage = "Couldn't read this file: \(error.localizedDescription)" }
    }

    private func convertToWav() {
        guard let src = nintendoURL,
              let out = FilePanels.save(name: src.deletingPathExtension().lastPathComponent + ".wav", type: .wav, title: "Save WAV") else { return }
        do {
            try AudioImport.wavData(try decodeNintendo(src)).write(to: out)
            doc.status("Saved \(out.lastPathComponent).")
        } catch {
            doc.errorMessage = "Couldn't convert this file: \(error.localizedDescription)"
        }
    }

    private func saveResized() {
        guard let img = resizedPreview, let png = ImageOps.pngData(img),
              let out = FilePanels.save(name: "\(imageURL?.deletingPathExtension().lastPathComponent ?? "image")-\(imageTarget.size.0)x\(imageTarget.size.1).png",
                                        type: .png, title: "Save Resized Picture") else { return }
        do { try png.write(to: out); doc.status("Saved \(out.lastPathComponent).") }
        catch { doc.errorMessage = error.localizedDescription }
    }

    private func useImageInTheme() {
        guard let u = imageURL, let img = ImageOps.loadCGImage(url: u) else { return }
        imageTarget.apply(img, to: doc)
        doc.status("Added to the theme. Click Edit… on it to fine-tune.")
    }

    private func extractTheme() {
        guard let src = FilePanels.open(types: [.folder, .zip, .data], title: "Choose a theme to extract", allowFolders: true),
              let dest = FilePanels.chooseFolder(title: "Choose where to save the extracted files", prompt: "Extract Here") else { return }
        do {
            let pkg = try ThemePackage.load(url: src)
            let name = pkg.safeName
            let dir = dest.appendingPathComponent(name + " (extracted)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var count = 0
            func savePNG(_ img: RGBImage?, _ file: String, crop: (Int, Int)? = nil) throws {
                guard var img else { return }
                if let crop { img = img.cropped(width: min(crop.0, img.width), height: min(crop.1, img.height)) }
                guard let cg = ImageOps.cgImage(img), let png = ImageOps.pngData(cg) else { return }
                try png.write(to: dir.appendingPathComponent(file)); count += 1
            }
            let t = pkg.theme, f = t.flags
            try savePNG(t.textures.top, "top.png", crop: ThemeGeometry.visibleSize(.top, flags: f))
            try savePNG(t.textures.bottom, "bottom.png", crop: ThemeGeometry.visibleSize(.bottom, flags: f))
            try savePNG(t.textures.topPattern, "top_pattern.png")
            try savePNG(t.textures.topAltPattern, "top_pattern2.png")
            try savePNG(t.textures.folderClosed, "folder_closed.png")
            try savePNG(t.textures.folderOpen, "folder_open.png")
            try savePNG(t.textures.fileLarge, "file_large.png")
            try savePNG(t.textures.fileSmall, "file_small.png")
            try savePNG(pkg.info.largeIcon, "icon.png")
            if let p = pkg.preview { try p.write(to: dir.appendingPathComponent("preview.png")); count += 1 }
            if let bgm = pkg.bgm, let decoded = try? BCSTM.decode(bgm) {
                try AudioImport.wavData(decoded.0).write(to: dir.appendingPathComponent("bgm.wav")); count += 1
            }
            let sfx = SoundEffectBlock.decode(t.soundEffectData)
            for slot in SoundEffectSlot.allCases {
                if let d = sfx.sounds[slot.rawValue], let pcm = try? BCWAV.decode([UInt8](d)) {
                    let file = "sfx_\(slot.rawValue + 1)_\(slot.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "-")).wav"
                    try AudioImport.wavData(pcm).write(to: dir.appendingPathComponent(file)); count += 1
                }
            }
            try ThemePreset(flags: t.flags, colors: t.colors).jsonData().write(to: dir.appendingPathComponent("colors.json")); count += 1
            doc.status("Extracted \(count) files from “\(name)”.")
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            doc.errorMessage = "Couldn't extract that theme: \(error.localizedDescription)"
        }
    }
}

/// Drop target + chooser for a single file.
struct DropField: View {
    @Binding var url: URL?
    let types: [UTType]
    let prompt: String
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: url == nil ? "tray.and.arrow.down" : "doc.fill")
                .font(.system(size: 18)).foregroundStyle(url == nil ? Color.secondary : Color.accentColor)
            Text(url?.lastPathComponent ?? prompt)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(url == nil ? "Choose…" : "Change…") {
                if let u = FilePanels.open(types: types, title: prompt) { url = u }
            }
            .controlSize(.small)
            if url != nil {
                Button { url = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [5, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            url = u
            return true
        } isTargeted: { targeted = $0 }
    }
}
