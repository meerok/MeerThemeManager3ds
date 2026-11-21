import SwiftUI
import AppKit
import ThemeKit
import Observation
import UniformTypeIdentifiers

/// A picture the user dropped into a texture slot, kept at full resolution so it can be
/// re-fitted whenever the frame type changes.
struct SourceImage {
    /// Original picture (shrunk if huge).
    var image: CGImage
    /// `image` with the color adjustments applied.
    var adjusted: CGImage
    var edit: ImageEdit
    var fileName: String?

    init(image: CGImage, edit: ImageEdit = ImageEdit(), fileName: String? = nil) {
        let limited = ImageOps.limitSize(image)
        self.image = limited
        self.edit = edit
        self.adjusted = ImageOps.adjusted(limited, edit)
        self.fileName = fileName
    }

    var fit: FitMode { edit.fit }
}

enum EditorSection: String, CaseIterable, Identifiable, Hashable {
    case info, top, bottom, icons, buttons, folderView, text, music, sounds, converter, export
    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "Theme Info"
        case .top: return "Top Screen"
        case .bottom: return "Bottom Screen"
        case .icons: return "Icons & Cursor"
        case .buttons: return "Buttons & Arrows"
        case .folderView: return "Folder View"
        case .text: return "Text Boxes"
        case .music: return "Background Music"
        case .sounds: return "Sound Effects"
        case .converter: return "Converter Tools"
        case .export: return "Export & Share"
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        case .icons: return "square.grid.3x2"
        case .buttons: return "button.programmable"
        case .folderView: return "folder"
        case .text: return "text.bubble"
        case .music: return "music.note"
        case .sounds: return "speaker.wave.2"
        case .converter: return "arrow.triangle.2.circlepath"
        case .export: return "square.and.arrow.up"
        }
    }

    var group: String {
        switch self {
        case .info: return "Theme"
        case .top, .bottom: return "Wallpapers"
        case .icons, .buttons, .folderView, .text: return "Interface Colors"
        case .music, .sounds: return "Audio"
        case .converter, .export: return "Tools & Finish"
        }
    }
}

struct BGMSettings: Equatable {
    var sampleRate: Int = 32000
    var mono = false
    /// Loop point, in seconds from the start of the (trimmed) song.
    var loopStartSeconds: Double = 0
    var edit = AudioEdit()
}

@MainActor
@Observable
final class ThemeDocument {
    // MARK: Theme content
    var theme = Theme() { didSet { themeChanged(oldValue) } }
    var name = "" { didSet { markDirty() } }
    var themeDescription = "" { didSet { markDirty() } }
    var author = "" { didSet { markDirty() } }
    var smdh = SMDH()
    var largeIcon: RGBImage = SMDH.defaultIcon(size: 48) { didSet { iconImage = ImageOps.cgImage(largeIcon); markDirty() } }
    var iconImage: CGImage?

    var sources: [TextureSlot: SourceImage] = [:]
    var previewImages: [TextureSlot: CGImage] = [:]
    var palette: [RGB] = []

    // MARK: Audio
    var bgmData: [UInt8]?
    var bgmSourcePCM: PCMAudio?
    var bgmSourceName: String?
    var bgmSourceURL: URL?
    var bgmPreviewPCM: PCMAudio?
    var bgmSettings = BGMSettings()
    var bgmBusy = false
    var bgmProgress: Double = 0
    var sfx = SoundEffectBlock() {
        didSet { theme.soundEffectData = sfx.isEmpty ? [] : sfx.encode() }
    }
    var sfxNames: [String?] = Array(repeating: nil, count: 8)

    // MARK: State
    var fileURL: URL?
    var isDirty = false
    var statusMessage: String?
    var errorMessage: String?
    var selection: EditorSection? = .info
    var previewAnimating = true
    var previewFolderMode = false
    var previewZoom: Double = 1.5
    var exportBusy = false
    var lastExportURL: URL?

    @ObservationIgnored let player = AudioPreviewPlayer()
    @ObservationIgnored private var undoStack: [Theme] = []
    @ObservationIgnored private var redoStack: [Theme] = []
    @ObservationIgnored private var lastUndoPush = Date.distantPast
    @ObservationIgnored private var applyingHistory = false
    @ObservationIgnored private var bgmTask: Task<Void, Never>?

    init() {
        iconImage = ImageOps.cgImage(largeIcon)
    }

    var displayName: String { name.isEmpty ? "Untitled Theme" : name }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Change tracking & undo

    private func markDirty() { isDirty = true }

    private func themeChanged(_ old: Theme) {
        guard old != theme else { return }
        isDirty = true
        if !applyingHistory {
            let now = Date()
            if now.timeIntervalSince(lastUndoPush) > 0.6 {
                undoStack.append(old)
                if undoStack.count > 60 { undoStack.removeFirst() }
                redoStack.removeAll()
            }
            lastUndoPush = now
        }
        if old.textures != theme.textures { refreshPreviewImages() }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(theme)
        applyingHistory = true
        theme = prev
        sfx = SoundEffectBlock.decode(theme.soundEffectData)
        applyingHistory = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(theme)
        applyingHistory = true
        theme = next
        sfx = SoundEffectBlock.decode(theme.soundEffectData)
        applyingHistory = false
    }

    // MARK: Textures

    func refreshPreviewImages() {
        var map: [TextureSlot: CGImage] = [:]
        for slot in TextureSlot.allCases {
            guard let img = theme.textures[slot] else { continue }
            if slot.format == .a8 {
                map[slot] = ImageOps.maskImage(img)
            } else {
                map[slot] = ImageOps.cgImage(img)
            }
        }
        previewImages = map
        recomputePalette()
    }

    func recomputePalette() {
        var colors: [RGB] = []
        if let top = theme.textures.top {
            let (w, h) = ThemeGeometry.visibleSize(.top, flags: theme.flags)
            colors += ImageOps.palette(top.cropped(width: min(w, top.width), height: min(h, top.height)), maxColors: 12)
        }
        if let bottom = theme.textures.bottom {
            let (w, h) = ThemeGeometry.visibleSize(.bottom, flags: theme.flags)
            colors += ImageOps.palette(bottom.cropped(width: min(w, bottom.width), height: min(h, bottom.height)), maxColors: 12)
        }
        var seen = Set<RGB>()
        palette = colors.filter { seen.insert($0).inserted }
    }

    /// Renders the source picture of a slot into its texture canvas.
    func render(slot: TextureSlot) {
        guard let src = sources[slot] else { return }
        let (cw, ch) = ThemeGeometry.canvasSize(slot, flags: theme.flags)
        let (vw, vh) = ThemeGeometry.visibleSize(slot, flags: theme.flags)
        let visible = ImageOps.render(src.adjusted, width: vw, height: vh, edit: src.edit)
        theme.textures[slot] = visible.bled(toWidth: cw, height: ch)
    }

    /// Renders what a slot would look like with `edit`, without changing the theme (for the editor).
    func previewRender(slot: TextureSlot, edit: ImageEdit, adjusted: CGImage) -> RGBImage {
        let (vw, vh) = ThemeGeometry.visibleSize(slot, flags: theme.flags)
        return ImageOps.render(adjusted, width: vw, height: vh, edit: edit)
    }

    /// Replaces a slot's edit settings and re-renders it.
    func setEdit(_ edit: ImageEdit, for slot: TextureSlot) {
        guard var s = sources[slot] else { return }
        if s.edit.colorKey != edit.colorKey { s.adjusted = ImageOps.adjusted(s.image, edit) }
        s.edit = edit
        sources[slot] = s
        render(slot: slot)
    }

    func setImage(_ image: CGImage, for slot: TextureSlot, fileName: String? = nil) {
        let small: Set<TextureSlot> = [.folderClosed, .folderOpen, .fileLarge, .fileSmall, .topPattern, .topAltPattern]
        let src = SourceImage(image: image, edit: ImageEdit(fit: small.contains(slot) ? .stretch : .fill), fileName: fileName)
        sources[slot] = src
        render(slot: slot)
        enableFlags(for: slot)
    }

    func updateEdit(_ slot: TextureSlot, _ change: (inout ImageEdit) -> Void) {
        guard let s = sources[slot] else { return }
        var e = s.edit
        change(&e)
        setEdit(e, for: slot)
    }

    func clearImage(_ slot: TextureSlot) {
        sources[slot] = nil
        theme.textures[slot] = nil
    }

    private func enableFlags(for slot: TextureSlot) {
        switch slot {
        case .top: theme.flags.topDrawType = .texture
        case .topPattern, .topAltPattern: theme.flags.topDrawType = .solidColorTexture
        case .bottom: theme.flags.bottomDrawType = .texture
        case .folderClosed, .folderOpen:
            if theme.textures.folderClosed != nil && theme.textures.folderOpen != nil { theme.flags.folderTexture = true }
        case .fileLarge, .fileSmall:
            if theme.textures.fileLarge != nil && theme.textures.fileSmall != nil { theme.flags.fileTexture = true }
        }
    }

    /// Called when frame types change: rebuild canvases at the new size.
    func frameTypesChanged() {
        for slot in [TextureSlot.top, .bottom] where sources[slot] != nil { render(slot: slot) }
        recomputePalette()
    }

    func loadImage(from url: URL, into slot: TextureSlot) {
        guard let img = ImageOps.loadCGImage(url: url) else {
            errorMessage = "“\(url.lastPathComponent)” couldn't be opened as an image."
            return
        }
        setImage(img, for: slot, fileName: url.lastPathComponent)
        if slot == .top || slot == .bottom { status("Picture added. Click Edit… to crop, resize, rotate or adjust colors.") }
    }

    func setIcon(_ image: CGImage) {
        largeIcon = ImageOps.render(image, width: 48, height: 48, mode: .fill)
        smdh.smallIcon = SMDH.downscale(largeIcon, to: 24)
    }

    // MARK: Status

    func status(_ s: String) {
        statusMessage = s
        let msg = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.statusMessage == msg { self.statusMessage = nil }
        }
    }

    // MARK: New / Open

    func reset() {
        player.stop()
        applyingHistory = true
        theme = Theme()
        applyingHistory = false
        name = ""; themeDescription = ""; author = ""
        smdh = SMDH(); largeIcon = SMDH.defaultIcon(size: 48)
        sources = [:]; bgmSourceURL = nil; bgmData = nil; bgmSourcePCM = nil; bgmPreviewPCM = nil; bgmSourceName = nil
        bgmSettings = BGMSettings()
        sfx = SoundEffectBlock(); sfxNames = Array(repeating: nil, count: 8)
        fileURL = nil; undoStack = []; redoStack = []
        refreshPreviewImages()
        isDirty = false
        selection = .info
    }

    func open(url: URL) {
        do {
            let pkg = try ThemePackage.load(url: url)
            reset()
            applyingHistory = true
            theme = pkg.theme
            applyingHistory = false
            smdh = pkg.info
            let t = pkg.info.primaryTitle
            name = t.shortDescription; themeDescription = t.longDescription; author = t.publisher
            largeIcon = pkg.info.largeIcon
            // Make the decoded textures editable sources.
            for slot in TextureSlot.allCases {
                guard let img = theme.textures[slot] else { continue }
                let (vw, vh) = ThemeGeometry.visibleSize(slot, flags: theme.flags)
                let visible = img.cropped(width: min(vw, img.width), height: min(vh, img.height))
                if let cg = ImageOps.cgImage(visible) { sources[slot] = SourceImage(image: cg, edit: ImageEdit(fit: .stretch), fileName: "From theme") }
            }
            sfx = SoundEffectBlock.decode(theme.soundEffectData)
            for i in 0..<8 where sfx.sounds[i] != nil { sfxNames[i] = "From theme" }
            if let bgm = pkg.bgm {
                bgmData = bgm
                bgmSourceName = "bgm.bcstm (from theme)"
                if let decoded = try? BCSTM.decode(bgm) { bgmPreviewPCM = decoded.0 }
            }
            refreshPreviewImages()
            fileURL = url
            isDirty = false
            RecentFiles.add(url)
            status("Opened “\(displayName)”.")
        } catch {
            errorMessage = "Couldn't open “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    // MARK: Music

    /// Length of the song after trimming (before the automatic size limit).
    var editedBGMSeconds: Double {
        guard let src = bgmSourcePCM else { return bgmPreviewPCM?.duration ?? 0 }
        var seconds = max(0, src.duration - bgmSettings.edit.startSeconds)
        if bgmSettings.edit.maxSeconds > 0 { seconds = min(seconds, bgmSettings.edit.maxSeconds) }
        return seconds
    }

    var estimatedBGMSize: Int {
        guard bgmSourcePCM != nil else { return bgmData?.count ?? 0 }
        return AudioProcess.estimatedBCSTMSize(seconds: min(editedBGMSeconds, maxBGMSeconds),
                                               sampleRate: bgmSettings.sampleRate, channels: bgmSettings.mono ? 1 : 2)
    }

    /// Longest duration that fits the 3DS limit with the current settings.
    var maxBGMSeconds: Double {
        let ch = Double(bgmSettings.mono ? 1 : 2)
        let bytesPerSecond = Double(bgmSettings.sampleRate) * 8.0 / 14.0 * ch
        return Double(ThemeLimits.maxBGM - 0x1000) / bytesPerSecond
    }

    func importMusic(url: URL) {
        player.stop()
        if url.pathExtension.lowercased() == "bcstm" {
            do {
                let bytes = [UInt8](try Data(contentsOf: url))
                let (pcm, _) = try BCSTM.decode(bytes)
                bgmData = bytes
                bgmSourcePCM = nil
                bgmPreviewPCM = pcm
                bgmSourceName = url.lastPathComponent
                theme.flags.backgroundMusic = true
                if bytes.count > ThemeLimits.maxBGM {
                    errorMessage = "This BCSTM is \(bytes.count.formatted()) bytes, which is over the 3DS limit of \(ThemeLimits.maxBGM.formatted()) bytes. The 3DS may refuse to play it."
                }
                status("Loaded \(url.lastPathComponent).")
            } catch {
                errorMessage = "Couldn't read this BCSTM: \(error.localizedDescription)"
            }
            return
        }
        bgmBusy = true
        bgmProgress = 0
        bgmSourceName = url.lastPathComponent
        bgmSourceURL = url
        let rate = bgmSettings.sampleRate, mono = bgmSettings.mono
        bgmTask?.cancel()
        bgmTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let pcm = try AudioImport.load(url: url, sampleRate: rate, channels: mono ? 1 : 2, maxSeconds: 600)
                await MainActor.run {
                    self?.bgmSourcePCM = pcm
                    self?.theme.flags.backgroundMusic = true
                    self?.encodeMusic()
                }
            } catch {
                await MainActor.run {
                    self?.bgmBusy = false
                    self?.errorMessage = "Couldn't import “\(url.lastPathComponent)”: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Re-imports at a new sample rate / channel count if needed, then encodes.
    func applyMusicSettings(reimportFrom url: URL? = nil) {
        guard let src = bgmSourcePCM else { return }
        let needsResample = src.sampleRate != bgmSettings.sampleRate || src.channels.count != (bgmSettings.mono ? 1 : 2)
        if needsResample {
            if let original = bgmSourceURL, FileManager.default.fileExists(atPath: original.path) {
                importMusic(url: original)
            } else {
                // Original file is gone: resample what we have via a temporary WAV.
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mtm3-bgm-\(UUID().uuidString).wav")
                try? AudioImport.wavData(src).write(to: tmp)
                let name = bgmSourceName
                importMusic(url: tmp)
                bgmSourceName = name
            }
            return
        }
        encodeMusic()
    }

    func encodeMusic() {
        guard let source = bgmSourcePCM else { bgmBusy = false; return }
        player.stop()
        bgmBusy = true
        var pcm = AudioProcess.apply(source, bgmSettings.edit)
        let limit = maxBGMSeconds
        let maxSamples = Int(limit * Double(pcm.sampleRate))
        var trimmed = false
        if pcm.sampleCount > maxSamples {
            pcm.channels = pcm.channels.map { Array($0.prefix(maxSamples)) }
            trimmed = true
        }
        pcm.looping = true
        pcm.loopStart = min(Int(bgmSettings.loopStartSeconds * Double(pcm.sampleRate)), max(0, pcm.sampleCount - 14336))
        let input = pcm
        let wasTrimmed = trimmed
        Task.detached(priority: .userInitiated) { [weak self] in
            let bytes = BCSTM.encode(input) { p in Task { @MainActor in self?.bgmProgress = p } }
            let preview = try? BCSTM.decode(bytes).0
            await MainActor.run {
                guard let self else { return }
                self.bgmData = bytes
                self.bgmPreviewPCM = preview
                self.bgmBusy = false
                self.isDirty = true
                if wasTrimmed {
                    self.status("Music was trimmed to \(Self.formatTime(limit)) to fit the 3DS size limit.")
                } else {
                    self.status("Music converted (\(formatBytes(bytes.count))).")
                }
            }
        }
    }

    func removeMusic() {
        player.stop()
        bgmData = nil; bgmSourcePCM = nil; bgmPreviewPCM = nil; bgmSourceName = nil; bgmSourceURL = nil
        theme.flags.backgroundMusic = false
    }

    nonisolated static func formatTime(_ s: Double) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Sound effects

    func importSound(url: URL, slot: SoundEffectSlot) {
        do {
            let data: Data
            if url.pathExtension.lowercased() == "bcwav" {
                let bytes = [UInt8](try Data(contentsOf: url))
                _ = try BCWAV.decode(bytes)
                data = Data(bytes)
            } else {
                var edit = AudioEdit()
                edit.trimSilence = true
                edit.maxSeconds = 4
                let pcm = AudioProcess.apply(try AudioImport.load(url: url, sampleRate: 22050, channels: 1, maxSeconds: 10), edit)
                data = Data(BCWAV.encode(pcm))
            }
            sfx.sounds[slot.rawValue] = data
            sfxNames[slot.rawValue] = url.lastPathComponent
            theme.flags.soundEffects = true
            if sfx.estimatedSize > ThemeLimits.maxSoundEffects {
                errorMessage = "Sound effects now total \(sfx.estimatedSize.formatted()) bytes, over the \(ThemeLimits.maxSoundEffects.formatted())-byte limit. Use shorter sounds."
            }
        } catch {
            errorMessage = "Couldn't import “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    func clearSound(_ slot: SoundEffectSlot) {
        sfx.sounds[slot.rawValue] = nil
        sfxNames[slot.rawValue] = nil
        if sfx.isEmpty { theme.flags.soundEffects = false }
    }

    func playSound(_ slot: SoundEffectSlot) {
        guard let d = sfx.sounds[slot.rawValue], let pcm = try? BCWAV.decode([UInt8](d)) else { return }
        player.play(pcm, loop: false)
    }

    // MARK: Export

    func makePackage(preview: Data?) -> ThemePackage {
        smdh.setAllTitles(name: name, description: themeDescription, author: author)
        smdh.largeIcon = largeIcon
        smdh.smallIcon = SMDH.downscale(largeIcon, to: 24)
        var t = theme
        t.soundEffectData = theme.flags.soundEffects ? sfx.encode() : []
        return ThemePackage(theme: t, info: smdh, bgm: bgmData, preview: preview)
    }
}

func formatBytes(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

/// Recently opened themes.
@MainActor
enum RecentFiles {
    static let key = "RecentThemes"
    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func add(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)), forKey: key)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
