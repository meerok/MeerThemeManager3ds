import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ThemeDocument.self) private var doc
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var doc = doc
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            editor
                .navigationSplitViewColumnWidth(min: 440, ideal: 560)
        } detail: {
            PreviewPane()
                .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        }
        .navigationTitle(doc.displayName + (doc.isDirty ? " — Edited" : ""))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { doc.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!doc.canUndo).help("Undo (⌘Z)")
                Button { doc.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!doc.canRedo).help("Redo (⇧⌘Z)")
                Button { openTheme() } label: { Label("Open", systemImage: "folder") }
                    .help("Open a theme folder, ZIP or body_LZ.bin")
                Button { doc.selection = .export } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .help("Export & share")
            }
        }
        .onChange(of: doc.theme.flags.topFrameType) { _, _ in doc.frameTypesChanged() }
        .onChange(of: doc.theme.flags.bottomFrameType) { _, _ in doc.frameTypesChanged() }
        .alert("Something went wrong", isPresented: Binding(get: { doc.errorMessage != nil }, set: { if !$0 { doc.errorMessage = nil } })) {
            Button("OK", role: .cancel) { doc.errorMessage = nil }
        } message: {
            Text(doc.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let msg = doc.statusMessage {
                Text(msg)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: doc.statusMessage)
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            let ext = u.pathExtension.lowercased()
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue || ext == "zip" || ext == "bin" { doc.open(url: u); return true }
            return false
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch doc.selection ?? .info {
        case .info: InfoSection()
        case .top: TopScreenSection()
        case .bottom: BottomScreenSection()
        case .icons: IconsSection()
        case .buttons: ButtonsSection()
        case .folderView: FolderViewSection()
        case .text: TextSection()
        case .music: MusicSection()
        case .sounds: SoundsSection()
        case .converter: ConverterSection()
        case .export: ExportSection()
        }
    }

    private func openTheme() {
        if let u = FilePanels.open(types: [.folder, .zip, .data], title: "Open a theme folder, ZIP or body_LZ.bin", allowFolders: true) {
            doc.open(url: u)
        }
    }
}

struct SidebarView: View {
    @Environment(ThemeDocument.self) private var doc

    private var groups: [(String, [EditorSection])] {
        var out: [(String, [EditorSection])] = []
        for s in EditorSection.allCases {
            if let i = out.firstIndex(where: { $0.0 == s.group }) { out[i].1.append(s) } else { out.append((s.group, [s])) }
        }
        return out
    }

    var body: some View {
        @Bindable var doc = doc
        List(selection: $doc.selection) {
            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { s in
                        Label {
                            HStack {
                                Text(s.title)
                                Spacer()
                                if isCustomized(s) {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).help("Customized")
                                }
                            }
                        } icon: {
                            Image(systemName: s.symbol)
                        }
                        .tag(s)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(nsImage: AppBranding.logo)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MtM3").font(.headline)
                    Text("Meer Theme Manager 3ds").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if let icon = doc.iconImage {
                    Image(decorative: icon, scale: 1).resizable().frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(doc.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(doc.author.isEmpty ? "No author" : doc.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private func isCustomized(_ s: EditorSection) -> Bool {
        let f = doc.theme.flags
        switch s {
        case .info: return !doc.name.isEmpty
        case .top: return f.topDrawType != .none
        case .bottom: return f.bottomDrawType != .none
        case .icons: return f.cursorColor || f.folderColor || f.folderTexture || f.fileColor || f.fileTexture
        case .buttons: return f.arrowButtonColor || f.arrowColor || f.openCloseColor || f.topCornerColor || f.bottomCornerColor
        case .folderView: return f.folderBackgroundColor || f.folderArrowColor
        case .text: return f.gameTextDrawType != .standard || f.demoTextColor
        case .music: return f.backgroundMusic && doc.bgmData != nil
        case .sounds: return f.soundEffects
        case .converter, .export: return false
        }
    }
}

struct PreviewPane: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        GeometryReader { geo in
            let fitScale = min((geo.size.width - 48) / 428, (geo.size.height - 120) / 512)
            let scale = max(0.5, min(doc.previewZoom, fitScale))
            ZStack {
                LinearGradient(colors: [Color(white: 0.20), Color(white: 0.13)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    ConsoleScreensView(scale: scale, animate: doc.previewAnimating)
                    Spacer(minLength: 12)
                    controls
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var controls: some View {
        @Bindable var doc = doc
        return HStack(spacing: 10) {
            Picker("View", selection: $doc.previewFolderMode) {
                Label("Home", systemImage: "house.fill").tag(false)
                Label("Folder", systemImage: "folder.fill").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)

            Button {
                doc.previewAnimating.toggle()
            } label: {
                Image(systemName: doc.previewAnimating ? "pause.fill" : "play.fill")
            }
            .help(doc.previewAnimating ? "Pause animation" : "Play animation")

            Menu {
                ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { z in
                    Button("\(Int(z * 100))%") { doc.previewZoom = z }
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36)
            .help("Preview size")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}
