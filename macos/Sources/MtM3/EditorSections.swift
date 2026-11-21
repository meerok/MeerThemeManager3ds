import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

struct EditorPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Theme Info

struct InfoSection: View {
    @Environment(ThemeDocument.self) private var doc
    @State private var iconTargeted = false

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .info, text: "The name, description and icon shown in theme managers like Anemone3DS and on ThemePlaza. These are saved in info.smdh.")

            Card {
                CardHeader(title: "Details", symbol: "textformat")
                LabeledField(title: "Theme Name", help: "Up to 64 characters.", count: doc.name.count, limit: 64) {
                    TextField("My Awesome Theme", text: $doc.name)
                }
                LabeledField(title: "Description", help: "Up to 128 characters.", count: doc.themeDescription.count, limit: 128) {
                    TextField("A short description of your theme", text: $doc.themeDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                LabeledField(title: "Author", help: "Your name or username.", count: doc.author.count, limit: 64) {
                    TextField("Your name", text: $doc.author)
                }
            }

            Card {
                CardHeader(title: "Theme Icon", symbol: "app.badge", subtitle: "48 × 48 pixels. A 24 × 24 version is made automatically.")
                HStack(spacing: 20) {
                    ZStack {
                        Checkerboard()
                        if let icon = doc.iconImage {
                            Image(decorative: icon, scale: 1).resizable().interpolation(.none)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(iconTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: iconTargeted ? 2 : 1))
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let u = urls.first, let img = ImageOps.loadCGImage(url: u) else { return false }
                        doc.setIcon(img)
                        return true
                    } isTargeted: { iconTargeted = $0 }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Drop a square image, or choose one. Simple, bold artwork reads best at this tiny size.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose Image…") {
                                if let u = FilePanels.open(types: FilePanels.imageTypes, title: "Choose a theme icon"),
                                   let img = ImageOps.loadCGImage(url: u) { doc.setIcon(img) }
                            }
                            Button("Use Top Wallpaper") {
                                if let top = doc.sources[.top]?.image { doc.setIcon(top) }
                            }
                            .disabled(doc.sources[.top] == nil)
                        }
                    }
                }
            }

            InfoBanner(text: "Tip: ThemePlaza shows your preview image and the name/description from this page, so it's worth filling them in before exporting.")
        }
    }
}

struct LabeledField<Field: View>: View {
    let title: String
    let help: String
    let count: Int
    let limit: Int
    @ViewBuilder var field: Field
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text("\(count)/\(limit)").font(.caption.monospacedDigit()).foregroundStyle(count > limit ? .red : .secondary)
            }
            field.textFieldStyle(.roundedBorder)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Top Screen

struct TopScreenSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .top, text: "The upper screen's background. Use a picture, a solid color, or a color with a moving pattern.")

            Card {
                CardHeader(title: "Background Style", symbol: "paintpalette")
                ModePicker(options: [
                    (TopDrawType.none, "Default", "circle.slash"),
                    (TopDrawType.solidColor, "Color", "paintbrush.fill"),
                    (TopDrawType.solidColorTexture, "Color + Pattern", "square.grid.3x3.topleft.filled"),
                    (TopDrawType.texture, "Picture", "photo.fill"),
                ], selection: $doc.theme.flags.topDrawType)
            }

            switch doc.theme.flags.topDrawType {
            case .texture:
                Card {
                    CardHeader(title: "Movement", symbol: "arrow.left.and.right", subtitle: "Scrolling wallpapers are wider and pan as you scroll through your icons.")
                    Picker("Movement", selection: $doc.theme.flags.topFrameType) {
                        Text("Still").tag(TopFrameType.single)
                        Text("Slow Scroll").tag(TopFrameType.slowScroll)
                        Text("Fast Scroll").tag(TopFrameType.fastScroll)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Card {
                    ImageSlotView(slot: .top, title: "Top Wallpaper",
                                  detail: doc.theme.flags.topFrameType.scrolls
                                    ? "Best size: 1008 × 240 (it scrolls horizontally)."
                                    : "Best size: 412 × 240. The outer 6 px on each side are only visible in 3D.",
                                  showPositioning: true, thumbHeight: 150)
                    Toggle("Smooth gradients (dithering)", isOn: $doc.theme.ditherBackgrounds)
                        .help("Reduces color banding when the wallpaper is converted to the 3DS's 16-bit color.")
                }
            case .solidColor, .solidColorTexture:
                Card {
                    CardHeader(title: "Color", symbol: "paintbrush")
                    ColorRow(label: "Background Color", color: $doc.theme.colors.topBackground.main)
                    PercentSlider(label: "Gradient Strength", help: "How strongly the glow fades down the screen.", value: $doc.theme.colors.topBackground.gradient)
                    PercentSlider(label: "Gradient Brightness", help: "0% fades to black, 100% fades to white.", value: $doc.theme.colors.topBackground.gradientColor)
                }
                if doc.theme.flags.topDrawType == .solidColorTexture {
                    Card {
                        ImageSlotView(slot: .topPattern, title: "Pattern",
                                      detail: "64 × 64 grayscale mask that tiles across the screen. White = visible, black = transparent.",
                                      thumbHeight: 100)
                        PercentSlider(label: "Pattern Opacity", value: $doc.theme.colors.topBackground.textureOpacity)
                    }
                    Card {
                        ImageSlotView(slot: .topAltPattern, title: "Second Pattern (optional)",
                                      detail: "Another 64 × 64 mask layered on top, moving in a different direction.",
                                      thumbHeight: 100)
                        PercentSlider(label: "Second Pattern Opacity", value: $doc.theme.colors.topBackground.alternateOpacity)
                    }
                }
            case .none:
                InfoBanner(text: "The default HOME Menu background will be used. Pick a style above to customize it.", symbol: "info.circle")
            }
            PaletteStrip()
        }
    }
}

// MARK: - Bottom Screen

struct BottomScreenSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .bottom, text: "The lower (touch) screen behind your icons. Use a picture or recolor the panels.")

            Card {
                CardHeader(title: "Background Style", symbol: "paintpalette")
                ModePicker(options: [
                    (BottomDrawType.none, "Default", "circle.slash"),
                    (BottomDrawType.solidColor, "Colors", "paintbrush.fill"),
                    (BottomDrawType.texture, "Picture", "photo.fill"),
                ], selection: $doc.theme.flags.bottomDrawType)
            }

            switch doc.theme.flags.bottomDrawType {
            case .texture:
                Card {
                    CardHeader(title: "Movement", symbol: "arrow.left.and.right", subtitle: "How the wallpaper moves when you scroll through your icons.")
                    Picker("Movement", selection: $doc.theme.flags.bottomFrameType) {
                        Text("Still").tag(BottomFrameType.single)
                        Text("Slow Scroll").tag(BottomFrameType.slowScroll)
                        Text("Fast Scroll").tag(BottomFrameType.fastScroll)
                        Text("Page Flip").tag(BottomFrameType.pageScroll)
                        Text("Bounce").tag(BottomFrameType.bounceScroll)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(movementHelp).font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    ImageSlotView(slot: .bottom, title: "Bottom Wallpaper", detail: sizeHelp, showPositioning: true, thumbHeight: 150)
                    Toggle("Smooth gradients (dithering)", isOn: $doc.theme.ditherBackgrounds)
                }
            case .solidColor:
                panelCards(doc: doc)
            case .none:
                InfoBanner(text: "The default HOME Menu background will be used. Pick a style above to customize it.", symbol: "info.circle")
            }
            PaletteStrip()
        }
    }

    @ViewBuilder
    private func panelCards(doc: ThemeDocument) -> some View {
        @Bindable var doc = doc
        ToggleCard(title: "Inner Panel", symbol: "rectangle.inset.filled", subtitle: "The rounded area that holds your icons.", isOn: $doc.theme.flags.bottomInnerColor) {
            ColorRow(label: "Panel Color", color: $doc.theme.colors.bottomInner.main)
            ColorRow(label: "Border", color: $doc.theme.colors.bottomInner.border)
            ColorRow(label: "Bottom Highlight", help: "Thin line along the panel's lower edge.", color: $doc.theme.colors.bottomInner.highlight)
            ColorAlphaRow(label: "Shadow", help: "Soft shadow around the panel.", color: $doc.theme.colors.bottomInner.glow)
        }
        ToggleCard(title: "Outer Frame", symbol: "rectangle.dashed", subtitle: "The area around the inner panel.", isOn: $doc.theme.flags.bottomOuterColor) {
            ColorRow(label: "Frame Color", color: $doc.theme.colors.bottomOuter.main)
            ColorRow(label: "Side Glow", help: "Gradient on the left and right edges.", color: $doc.theme.colors.bottomOuter.glow)
            ColorRow(label: "Stripes", help: "Fine lines near the bottom.", color: $doc.theme.colors.bottomOuter.stripes)
        }
    }

    private var movementHelp: String {
        switch doc.theme.flags.bottomFrameType {
        case .single: return "The wallpaper stays put."
        case .slowScroll, .fastScroll: return "The wallpaper pans smoothly with your icons."
        case .pageScroll: return "The wallpaper jumps one screen (320 px) at a time, across 3 screens."
        case .bounceScroll: return "Like Page Flip, but bounces back from the last screen."
        }
    }

    private var sizeHelp: String {
        switch doc.theme.flags.bottomFrameType {
        case .single: return "Best size: 320 × 240."
        case .pageScroll, .bounceScroll: return "Best size: 960 × 240 (three 320 × 240 screens side by side)."
        case .slowScroll, .fastScroll: return "Best size: 1008 × 240 (it scrolls horizontally)."
        }
    }
}

// MARK: - Icons & Cursor

struct IconsSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .icons, text: "The selection cursor, folder icons and file icons in your HOME Menu grid.")
            PaletteStrip()

            ToggleCard(title: "Cursor", symbol: "viewfinder", subtitle: "The highlight around the selected icon.", isOn: $doc.theme.flags.cursorColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.cursor.main)
                ColorRow(label: "Light Edge", color: $doc.theme.colors.cursor.light)
                ColorRow(label: "Shading", color: $doc.theme.colors.cursor.shading)
                ColorRow(label: "Glow", help: "The pulsing glow around the cursor.", color: $doc.theme.colors.cursor.glow)
            }

            ToggleCard(title: "Folder Colors", symbol: "folder.fill", subtitle: "Colors of the 3D folder icons.", isOn: $doc.theme.flags.folderColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.folder.main)
                ColorRow(label: "Light", color: $doc.theme.colors.folder.light)
                ColorRow(label: "Shading", color: $doc.theme.colors.folder.shading)
                ColorRow(label: "Shadow", color: $doc.theme.colors.folder.shadow)
            }

            ToggleCard(title: "Folder Pictures", symbol: "photo.on.rectangle", subtitle: "Wrap your own art onto folder icons (both images required).",
                       isOn: $doc.theme.flags.folderTexture, offText: "Folders use their colors. Turn on to add pictures.") {
                HStack(alignment: .top, spacing: 16) {
                    ImageSlotView(slot: .folderClosed, title: "Closed", detail: "128 × 64", thumbHeight: 90)
                    ImageSlotView(slot: .folderOpen, title: "Open", detail: "128 × 64", thumbHeight: 90)
                }
                if doc.theme.flags.folderTexture && (doc.theme.textures.folderClosed == nil || doc.theme.textures.folderOpen == nil) {
                    InfoBanner(text: "Add both the closed and open images, or folder pictures won't be included.", symbol: "exclamationmark.triangle", tint: .orange)
                }
            }

            ToggleCard(title: "File Colors", symbol: "doc.fill", subtitle: "Colors of the 3D file / cartridge icons.", isOn: $doc.theme.flags.fileColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.file.main)
                ColorRow(label: "Light", color: $doc.theme.colors.file.light)
                ColorRow(label: "Shading", color: $doc.theme.colors.file.shading)
                ColorAlphaRow(label: "Shadow", color: $doc.theme.colors.file.shadow)
            }

            ToggleCard(title: "File Pictures", symbol: "doc.richtext", subtitle: "Your own art on file icons (both images required).",
                       isOn: $doc.theme.flags.fileTexture, offText: "Files use their colors. Turn on to add pictures.") {
                HStack(alignment: .top, spacing: 16) {
                    ImageSlotView(slot: .fileLarge, title: "Large", detail: "64 × 128", thumbHeight: 110)
                    ImageSlotView(slot: .fileSmall, title: "Small", detail: "32 × 64", thumbHeight: 110)
                }
                if doc.theme.flags.fileTexture && (doc.theme.textures.fileLarge == nil || doc.theme.textures.fileSmall == nil) {
                    InfoBanner(text: "Add both the large and small images, or file pictures won't be included.", symbol: "exclamationmark.triangle", tint: .orange)
                }
            }
        }
    }
}

// MARK: - Buttons & Arrows

struct ButtonsSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .buttons, text: "The scroll arrows, the Open/Close button and the corner buttons on the bottom screen.")
            PaletteStrip()

            ToggleCard(title: "Arrow Buttons", symbol: "arrow.left.arrow.right.square", subtitle: "The tabs on the left and right edges used to scroll.", isOn: $doc.theme.flags.arrowButtonColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.arrowButton.main)
                ColorRow(label: "Highlight", color: $doc.theme.colors.arrowButton.light)
                ColorRow(label: "Shading", color: $doc.theme.colors.arrowButton.shading)
                ColorAlphaRow(label: "Shadow", color: $doc.theme.colors.arrowButton.shadow)
            }

            ToggleCard(title: "Arrows", symbol: "arrowtriangle.right.fill", subtitle: "The arrow symbols inside the arrow buttons.", isOn: $doc.theme.flags.arrowColor) {
                ColorRow(label: "Arrow", color: $doc.theme.colors.arrow.unpressed)
                ColorRow(label: "Arrow (Pressed)", color: $doc.theme.colors.arrow.pressed)
                ColorRow(label: "Outline", color: $doc.theme.colors.arrow.border)
            }

            ToggleCard(title: "Open & Close Buttons", symbol: "capsule.fill", subtitle: "“Open” appears when software is selected; “Close” appears in folders.", isOn: $doc.theme.flags.openCloseColor) {
                OpenCloseEditor(title: "Open Button", colors: $doc.theme.colors.open)
                Divider()
                OpenCloseEditor(title: "Close Button", colors: $doc.theme.colors.close)
            }

            ToggleCard(title: "Top Corner Buttons", symbol: "rectangle.portrait.topleft.inset.filled", subtitle: "The buttons in the top-left and top-right of the bottom screen.", isOn: $doc.theme.flags.topCornerColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.topCorner.main)
                ColorRow(label: "Light", color: $doc.theme.colors.topCorner.light)
                ColorRow(label: "Shadow", color: $doc.theme.colors.topCorner.shadow)
                ColorRow(label: "Icon / Text", color: $doc.theme.colors.topCorner.text)
            }

            ToggleCard(title: "Bottom Corner Buttons", symbol: "rectangle.portrait.bottomleft.inset.filled", subtitle: "The buttons in the bottom-left and bottom-right corners.", isOn: $doc.theme.flags.bottomCornerColor) {
                ColorRow(label: "Main", color: $doc.theme.colors.bottomCorner.main)
                ColorRow(label: "Highlight", color: $doc.theme.colors.bottomCorner.highlight)
                ColorRow(label: "Border", color: $doc.theme.colors.bottomCorner.border)
                ColorRow(label: "Shadow", color: $doc.theme.colors.bottomCorner.baseShadow)
                ColorRow(label: "Icon (Top)", color: $doc.theme.colors.bottomCorner.iconTop)
                ColorRow(label: "Icon (Bottom)", color: $doc.theme.colors.bottomCorner.iconBottom)
                ColorRow(label: "Icon Text", color: $doc.theme.colors.bottomCorner.iconText)
            }
        }
    }
}

struct OpenCloseEditor: View {
    let title: String
    @Binding var colors: OpenCloseColors
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ColorRow(label: "Button", color: $colors.unpressed)
            ColorRow(label: "Button (Pressed)", color: $colors.pressed)
            ColorRow(label: "Highlight", color: $colors.light)
            ColorRow(label: "Glow / Edge", color: $colors.glow)
            ColorAlphaRow(label: "Shadow", color: $colors.shadow)
            ColorRow(label: "Text", color: $colors.textUnpressed)
            ColorRow(label: "Text (Pressed)", color: $colors.textPressed)
            ColorRow(label: "Text Shadow", color: $colors.textShadow)
            HStack {
                Text("Text Shadow Offset").font(.callout)
                Slider(value: Binding(get: { Double(colors.textShadowPosition) }, set: { colors.textShadowPosition = Float(($0 * 4).rounded() / 4) }), in: -3...3)
                Text(String(format: "%+.2f", colors.textShadowPosition)).font(.caption.monospacedDigit()).frame(width: 44)
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Folder View

struct FolderViewSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .folderView, text: "How the bottom screen looks while a folder is open. Switch the preview to Folder view to see it.")
            PaletteStrip()

            ToggleCard(title: "Folder Background", symbol: "square.inset.filled", subtitle: "The inner panel shown inside folders.", isOn: $doc.theme.flags.folderBackgroundColor) {
                ColorRow(label: "Panel Color", color: $doc.theme.colors.folderBackground.main)
                ColorRow(label: "Border", color: $doc.theme.colors.folderBackground.border)
                ColorRow(label: "Bottom Highlight", color: $doc.theme.colors.folderBackground.highlight)
                ColorAlphaRow(label: "Shadow", color: $doc.theme.colors.folderBackground.glow)
            }

            ToggleCard(title: "Folder Back Button", symbol: "arrow.uturn.backward.circle", subtitle: "The button that leaves the folder, and the folder name tab.", isOn: $doc.theme.flags.folderArrowColor) {
                ColorRow(label: "Button", color: $doc.theme.colors.folderArrow.main)
                ColorRow(label: "Highlight", color: $doc.theme.colors.folderArrow.highlight)
                ColorRow(label: "Shading", color: $doc.theme.colors.folderArrow.shading)
                ColorRow(label: "Glow", color: $doc.theme.colors.folderArrow.glow)
                ColorAlphaRow(label: "Shadow", color: $doc.theme.colors.folderArrow.shadow)
                ColorRow(label: "Arrow", color: $doc.theme.colors.folderArrow.arrowUnpressed)
                ColorRow(label: "Arrow (Pressed)", color: $doc.theme.colors.folderArrow.arrowPressed)
                ColorRow(label: "Arrow Glow", color: $doc.theme.colors.folderArrow.arrowGlow)
            }

            Button {
                withAnimation { doc.previewFolderMode.toggle() }
            } label: {
                Label(doc.previewFolderMode ? "Show Home View in Preview" : "Show Folder View in Preview", systemImage: "eye")
            }
        }
    }
}

// MARK: - Text

struct TextSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .text, text: "Text boxes on the top screen, like the selected software's title.")
            PaletteStrip()

            Card {
                CardHeader(title: "Software Title Box", symbol: "character.bubble", subtitle: "The box showing the name of the selected software.")
                Picker("Style", selection: $doc.theme.flags.gameTextDrawType) {
                    Text("Default").tag(GameTextDrawType.standard)
                    Text("Custom Colors").tag(GameTextDrawType.colored)
                    Text("Hidden").tag(GameTextDrawType.hidden)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if doc.theme.flags.gameTextDrawType == .colored {
                    Divider()
                    ColorRow(label: "Box", color: $doc.theme.colors.gameText.main)
                    ColorRow(label: "Highlight", color: $doc.theme.colors.gameText.light)
                    ColorAlphaRow(label: "Shadow", color: $doc.theme.colors.gameText.shadow)
                    ColorRow(label: "Text", color: $doc.theme.colors.gameText.text)
                } else if doc.theme.flags.gameTextDrawType == .hidden {
                    Text("The one-row title box is hidden, leaving your top wallpaper unobstructed.").font(.callout).foregroundStyle(.secondary)
                }
            }

            ToggleCard(title: "Demo Text", symbol: "text.alignleft", subtitle: "Box used for demo and informational text on the top screen.", isOn: $doc.theme.flags.demoTextColor) {
                ColorRow(label: "Box", color: $doc.theme.colors.demoText.main)
                ColorRow(label: "Text", color: $doc.theme.colors.demoText.text)
            }
        }
    }
}
