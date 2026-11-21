import SwiftUI
import AppKit
import ThemeKit
import UniformTypeIdentifiers

extension ThemeDocument {
    /// Renders preview.png (412×480).
    func renderPreviewPNG() -> Data? {
        let renderer = PreviewRenderer(theme: theme, images: previewImages, icon: iconImage, folderMode: false, time: 0, forExport: true)
        let r = ImageRenderer(content: ExportPreviewView(renderer: renderer))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return ImageOps.pngData(cg)
    }

    /// Builds all files off the main thread. Returns the package and its compressed body.
    func buildPackage() async -> (ThemePackage, [UInt8]) {
        let pkg = makePackage(preview: renderPreviewPNG())
        let theme = pkg.theme
        let body = await Task.detached(priority: .userInitiated) { theme.writeCompressedBody() }.value
        return (pkg, body)
    }

    func exportFolder() {
        guard let parent = FilePanels.chooseFolder(title: "Choose where to save the theme folder", prompt: "Export Here") else { return }
        exportBusy = true
        Task {
            let (pkg, body) = await buildPackage()
            let v = pkg.validate(compressedBody: body)
            if let e = v.errors.first { errorMessage = e; exportBusy = false; return }
            let dir = parent.appendingPathComponent(pkg.safeName)
            do {
                try pkg.writeFolder(to: dir, compressedBody: body)
                lastExportURL = dir
                fileURL = dir
                isDirty = false
                RecentFiles.add(dir)
                status("Exported “\(pkg.safeName)”.")
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            exportBusy = false
        }
    }

    func exportZip() {
        let suggested = makePackage(preview: nil).safeName + ".zip"
        guard let url = FilePanels.save(name: suggested, type: .zip, title: "Export Theme ZIP") else { return }
        exportBusy = true
        Task {
            let (pkg, body) = await buildPackage()
            let v = pkg.validate(compressedBody: body)
            if let e = v.errors.first { errorMessage = e; exportBusy = false; return }
            do {
                try Data(pkg.zipData(compressedBody: body)).write(to: url, options: .atomic)
                lastExportURL = url
                isDirty = false
                status("Saved \(url.lastPathComponent).")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            exportBusy = false
        }
    }

    func savePreviewImage() {
        guard let png = renderPreviewPNG(),
              let url = FilePanels.save(name: "preview.png", type: .png, title: "Save Preview Image") else { return }
        do { try png.write(to: url); status("Saved preview image.") } catch { errorMessage = error.localizedDescription }
    }

    func exportPreset() {
        guard let url = FilePanels.save(name: "\(makePackage(preview: nil).safeName) Colors.json", type: .json, title: "Export Colors & Settings") else { return }
        do {
            try ThemePreset(flags: theme.flags, colors: theme.colors).jsonData().write(to: url)
            status("Saved colors to \(url.lastPathComponent).")
        } catch { errorMessage = error.localizedDescription }
    }

    func importPreset() {
        guard let url = FilePanels.open(types: [.json], title: "Import Colors & Settings") else { return }
        do {
            let p = try ThemePreset.load(Data(contentsOf: url))
            var t = theme
            t.colors = p.colors
            // Keep picture-dependent modes only if the pictures exist.
            var f = p.flags
            if f.topDrawType == .texture && t.textures.top == nil { f.topDrawType = theme.flags.topDrawType }
            if f.bottomDrawType == .texture && t.textures.bottom == nil { f.bottomDrawType = theme.flags.bottomDrawType }
            if f.folderTexture && (t.textures.folderClosed == nil || t.textures.folderOpen == nil) { f.folderTexture = false }
            if f.fileTexture && (t.textures.fileLarge == nil || t.textures.fileSmall == nil) { f.fileTexture = false }
            f.backgroundMusic = theme.flags.backgroundMusic
            f.soundEffects = theme.flags.soundEffects
            t.flags = f
            theme = t
            frameTypesChanged()
            status("Imported colors from \(url.lastPathComponent).")
        } catch {
            errorMessage = "That file isn't an MtM3 color preset."
        }
    }
}

struct ExportSection: View {
    @Environment(ThemeDocument.self) private var doc
    @AppStorage("chmmIP") private var ip = ""
    @State private var validation: ThemePackage.Validation?
    @State private var checking = false
    @State private var sending = false
    @State private var sendProgress: Double = 0
    @State private var sendResult: String?

    var body: some View {
        EditorPage {
            PageHeader(section: .export, text: "Save your theme in the format ThemePlaza, Anemone3DS and other theme managers use: body_LZ.bin, info.smdh, preview.png and bgm.bcstm.")

            Card {
                CardHeader(title: "Checklist", symbol: "checklist", subtitle: "Make sure everything fits the 3DS's limits before you share.")
                if checking {
                    HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                } else if let v = validation {
                    SizeMeter(label: "body_LZ.bin", used: v.compressedBodySize, limit: ThemeLimits.maxCompressedBody)
                    if doc.theme.flags.backgroundMusic, doc.bgmData != nil {
                        SizeMeter(label: "bgm.bcstm", used: v.bgmSize, limit: ThemeLimits.maxBGM)
                    }
                    ForEach(v.errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout) }
                    ForEach(v.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                    if v.errors.isEmpty && v.warnings.isEmpty {
                        Label("Everything looks good and fits within the limits.", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.callout)
                    }
                }
                FileListView()
            }

            Card {
                CardHeader(title: "Save", symbol: "square.and.arrow.down")
                HStack(spacing: 12) {
                    BigActionButton(title: "Export Folder", subtitle: "For your SD card's /Themes folder", symbol: "folder.fill.badge.plus") { doc.exportFolder() }
                    BigActionButton(title: "Export ZIP", subtitle: "Upload to ThemePlaza or share", symbol: "doc.zipper") { doc.exportZip() }
                }
                .disabled(doc.exportBusy)
                if doc.exportBusy { ProgressView("Building theme…").controlSize(.small) }
                HStack {
                    Button("Save Preview Image…") { doc.savePreviewImage() }
                    Button("Export Colors…") { doc.exportPreset() }
                    Button("Import Colors…") { doc.importPreset() }
                    Spacer()
                }
                .controlSize(.small)
            }

            Card {
                CardHeader(title: "Upload to ThemePlaza", symbol: "globe", subtitle: "themeplaza.art hosts community themes that can be installed by QR code.")
                VStack(alignment: .leading, spacing: 6) {
                    StepRow(n: 1, text: "Export your theme (folder or ZIP) using the buttons above.")
                    StepRow(n: 2, text: "Sign in at themeplaza.art and choose Upload → Theme.")
                    StepRow(n: 3, text: "Attach body_LZ.bin, preview.png and (if you added music) bgm.bcstm from the exported folder. Fill in the name and description.")
                    StepRow(n: 4, text: "After approval, anyone can scan its QR code with Anemone3DS or the Theme Plaza app to install it.")
                }
                Button { NSWorkspace.shared.open(URL(string: "https://themeplaza.art/themes")!) } label: {
                    Label("Open ThemePlaza", systemImage: "arrow.up.right.square")
                }
            }

            Card {
                CardHeader(title: "Install Directly", symbol: "sdcard", subtitle: "Put the exported folder or ZIP in /Themes on your SD card, then apply it with Anemone3DS.")
                Divider()
                CardHeader(title: "Send to 3DS over Wi-Fi", symbol: "wifi", subtitle: "Open CHMM2 on your 3DS, choose to receive a theme, and enter the IP address it shows.")
                HStack {
                    TextField("3DS IP address, e.g. 192.168.1.42", text: $ip)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button {
                        send()
                    } label: { Label("Send", systemImage: "paperplane.fill") }
                    .disabled(ip.isEmpty || sending)
                    if sending { ProgressView(value: sendProgress).frame(width: 100) }
                }
                if let sendResult { Text(sendResult).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .task(id: doc.theme) { await runChecks() }
    }

    private func runChecks() async {
        checking = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        let (pkg, body) = await doc.buildPackage()
        if Task.isCancelled { return }
        validation = pkg.validate(compressedBody: body)
        checking = false
    }

    private func send() {
        sending = true
        sendResult = nil
        sendProgress = 0
        let address = ip.trimmingCharacters(in: .whitespaces)
        Task {
            let (pkg, body) = await doc.buildPackage()
            let zip = pkg.zipData(compressedBody: body, inFolder: pkg.safeName)
            do {
                try await ThemeSender().send(zip: zip, to: address) { p in Task { @MainActor in sendProgress = p } }
                sendResult = "Sent! Your theme should appear in CHMM2."
            } catch {
                sendResult = error.localizedDescription
            }
            sending = false
        }
    }
}

struct FileListView: View {
    @Environment(ThemeDocument.self) private var doc
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("body_LZ.bin", "Theme graphics, colors\(doc.theme.flags.soundEffects ? " & sound effects" : "")", true)
            row("info.smdh", "Name, description, author & icon", true)
            row("preview.png", "412 × 480 screenshot of both screens", true)
            row("bgm.bcstm", "Background music", doc.theme.flags.backgroundMusic && doc.bgmData != nil)
        }
        .padding(.top, 4)
    }

    private func row(_ name: String, _ detail: String, _ included: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: included ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(included ? .green : .secondary)
            Text(name).font(.system(.callout, design: .monospaced))
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct StepRow: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BigActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(hover ? 0.95 : 0.8)], startPoint: .top, endPoint: .bottom)))
            .scaleEffect(hover ? 1.01 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
