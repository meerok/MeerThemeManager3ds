import SwiftUI
import AppKit
import ThemeKit
import UniformTypeIdentifiers

enum AppBranding {
    /// The MtM3 logo: the bundled Logo.png, falling back to the app icon.
    @MainActor static let logo: NSImage = {
        if let url = Bundle.main.url(forResource: "Logo", withExtension: "png"), let img = NSImage(contentsOf: url) { return img }
        return NSApplication.shared.applicationIconImage ?? NSImage()
    }()

    @MainActor
    static func showAbout() {
        let credits = NSAttributedString(string: "Make Nintendo 3DS HOME Menu themes on your Mac.\nFormats based on Usagi 3DS Theme Editor and 3dbrew; DSP-ADPCM encoder ported from VGAudio.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Meer Theme Manager 3ds (MtM3)",
            .applicationIcon: logo,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: ((URL) -> Void)?
    var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let u = urls.first else { return }
        if let openHandler { openHandler(u) } else { pendingURL = u }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MtM3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var doc = ThemeDocument()

    var body: some Scene {
        Window("Meer Theme Manager 3ds", id: "main") {
            ContentView()
                .environment(doc)
                .frame(minWidth: 1100, minHeight: 680)
                .onAppear {
                    appDelegate.openHandler = { url in doc.open(url: url) }
                    if let u = appDelegate.pendingURL { doc.open(url: u); appDelegate.pendingURL = nil }
                }
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Meer Theme Manager 3ds") { AppBranding.showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Theme") { confirmDiscard { doc.reset() } }
                    .keyboardShortcut("n")
                Button("Open Theme…") {
                    confirmDiscard {
                        if let u = FilePanels.open(types: [.folder, .zip, .data], title: "Open a theme folder, ZIP or body_LZ.bin", allowFolders: true) {
                            doc.open(url: u)
                        }
                    }
                }
                .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(RecentFiles.urls, id: \.self) { u in
                        Button(u.lastPathComponent) { confirmDiscard { doc.open(url: u) } }
                    }
                    Divider()
                    Button("Clear Menu") { RecentFiles.clear() }
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export Theme Folder…") { doc.exportFolder() }
                    .keyboardShortcut("s")
                Button("Export Theme ZIP…") { doc.exportZip() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Save Preview Image…") { doc.savePreviewImage() }
                Button("Export Colors & Settings…") { doc.exportPreset() }
                Button("Import Colors & Settings…") { doc.importPreset() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { doc.undo() }.keyboardShortcut("z").disabled(!doc.canUndo)
                Button("Redo") { doc.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!doc.canRedo)
            }
            CommandMenu("Preview") {
                Button(doc.previewAnimating ? "Pause Animation" : "Play Animation") { doc.previewAnimating.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button(doc.previewFolderMode ? "Show Home View" : "Show Folder View") { doc.previewFolderMode.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
            CommandMenu("Go") {
                ForEach(Array(EditorSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { doc.selection = s }
                        .keyboardShortcut(i < 10 ? KeyboardShortcut(KeyEquivalent(Character(i < 9 ? "\(i + 1)" : "0")), modifiers: .command) : nil)
                }
            }
        }
    }

    @MainActor
    private func confirmDiscard(_ action: () -> Void) {
        guard doc.isDirty else { action(); return }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes to “\(doc.displayName)”?"
        alert.informativeText = "Your changes haven't been exported yet."
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
}
