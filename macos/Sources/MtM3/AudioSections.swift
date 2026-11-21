import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

// MARK: - Background Music

struct MusicSection: View {
    @Environment(ThemeDocument.self) private var doc
    @State private var targeted = false
    @State private var playing = false

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .music, text: "Add a song that plays on the HOME Menu. Drop in any MP3, WAV, M4A, AAC, AIFF or FLAC. MtM3 converts it to the 3DS's looping BCSTM format for you, no other tools needed.")

            Card {
                HStack {
                    CardHeader(title: "Music", symbol: "music.note.list", subtitle: doc.bgmSourceName ?? "No music added")
                    Spacer()
                    Toggle("Play music on the HOME Menu", isOn: $doc.theme.flags.backgroundMusic)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(doc.bgmData == nil)
                        .help("Turns the BGM flag on or off")
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(targeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [6, 4]))
                    if doc.bgmBusy {
                        VStack(spacing: 8) {
                            ProgressView(value: doc.bgmProgress).frame(width: 220)
                            Text("Converting to 3DS format…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else if let pcm = doc.bgmPreviewPCM {
                        WaveformView(pcm: pcm, loopStart: pcm.looping ? pcm.loopStart : nil)
                            .padding(10)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text("Drop an audio file here").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 110)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let u = urls.first else { return false }
                    doc.importMusic(url: u)
                    return true
                } isTargeted: { targeted = $0 }

                HStack {
                    Button {
                        if let u = FilePanels.open(types: FilePanels.audioTypes, title: "Choose music") { doc.importMusic(url: u) }
                    } label: { Label("Choose Audio…", systemImage: "folder") }

                    if let pcm = doc.bgmPreviewPCM {
                        Button {
                            if playing { doc.player.stop(); playing = false }
                            else { doc.player.play(pcm, loop: true); playing = true }
                        } label: { Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill") }
                        Text("\(ThemeDocument.formatTime(pcm.duration)) · \(pcm.sampleRate / 1000) kHz · \(pcm.channels.count == 1 ? "Mono" : "Stereo")")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if doc.bgmData != nil || doc.bgmSourcePCM != nil {
                        Button(role: .destructive) { doc.removeMusic(); playing = false } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .controlSize(.small)

                if doc.bgmData != nil || doc.bgmSourcePCM != nil {
                    SizeMeter(label: "bgm.bcstm size", used: doc.bgmData?.count ?? doc.estimatedBGMSize, limit: ThemeLimits.maxBGM)
                }
            }

            if let src = doc.bgmSourcePCM {
                Card {
                    CardHeader(title: "Trim & Volume", symbol: "scissors",
                               subtitle: "Pick the part of the song you want. Changes apply when you click Apply & Re-convert.")
                    AdjustSlider(label: "Start at", value: $doc.bgmSettings.edit.startSeconds, range: 0...max(1, src.duration - 1), neutral: 0, step: 0.5) {
                        ThemeDocument.formatTime($0)
                    }
                    AdjustSlider(label: "Length", value: $doc.bgmSettings.edit.maxSeconds, range: 0...max(10, src.duration), neutral: 0, step: 1) {
                        $0 == 0 ? "Whole song" : ThemeDocument.formatTime($0)
                    }
                    AdjustSlider(label: "Loop back to", value: $doc.bgmSettings.loopStartSeconds, range: 0...max(1, doc.editedBGMSeconds - 1), neutral: 0, step: 0.5) {
                        $0 == 0 ? "Beginning" : ThemeDocument.formatTime($0)
                    }
                    Toggle("Normalize volume (make it as loud as possible without distortion)", isOn: $doc.bgmSettings.edit.normalize)
                    AdjustSlider(label: "Volume", value: $doc.bgmSettings.edit.gainDB, range: -12...12, neutral: 0, step: 0.5) { String(format: "%+.1f dB", $0) }
                    AdjustSlider(label: "Fade in", value: $doc.bgmSettings.edit.fadeInSeconds, range: 0...10, neutral: 0, step: 0.5) { $0 == 0 ? "Off" : String(format: "%.1f s", $0) }
                    AdjustSlider(label: "Fade out", value: $doc.bgmSettings.edit.fadeOutSeconds, range: 0...10, neutral: 0, step: 0.5) { $0 == 0 ? "Off" : String(format: "%.1f s", $0) }
                    Toggle("Remove silence at the start and end", isOn: $doc.bgmSettings.edit.trimSilence)
                    Text("Tip: fade-outs make songs that don't loop cleanly sound smoother when they restart.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Card {
                    CardHeader(title: "Quality", symbol: "slider.horizontal.3",
                               subtitle: "Lower quality fits a longer song into the 3DS's 3.3 MB music limit.")
                    Picker("Sample rate", selection: $doc.bgmSettings.sampleRate) {
                        Text("22 kHz (longest)").tag(22050)
                        Text("32 kHz (recommended)").tag(32000)
                        Text("44 kHz (best)").tag(44100)
                    }
                    Picker("Channels", selection: $doc.bgmSettings.mono) {
                        Text("Stereo").tag(false)
                        Text("Mono (twice as long)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text("At these settings up to \(ThemeDocument.formatTime(doc.maxBGMSeconds)) fits; your selection is \(ThemeDocument.formatTime(doc.editedBGMSeconds)). Anything longer is trimmed automatically. The loop point snaps to the nearest 0.45 s block so the loop is seamless.")
                        .font(.caption).foregroundStyle(doc.editedBGMSeconds > doc.maxBGMSeconds ? .orange : .secondary)
                    HStack {
                        Button("Reset") { doc.bgmSettings = BGMSettings() }
                        Spacer()
                        Button {
                            playing = false
                            doc.applyMusicSettings()
                        } label: { Label("Apply & Re-convert", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderedProminent)
                        .disabled(doc.bgmBusy)
                    }
                }
            }

            InfoBanner(text: "Already have a .bcstm (for example from LoopingAudioConverter)? Drop it in and it'll be used as-is.")
        }
        .onDisappear { doc.player.stop(); playing = false }
    }
}

struct WaveformView: View {
    let pcm: PCMAudio
    let loopStart: Int?

    var body: some View {
        Canvas { ctx, size in
            guard let ch = pcm.channels.first, !ch.isEmpty else { return }
            let bins = max(1, Int(size.width / 2))
            let per = max(1, ch.count / bins)
            var path = Path()
            for b in 0..<bins {
                let start = b * per
                if start >= ch.count { break }
                let end = min(ch.count, start + per)
                var peak: Int16 = 0
                var i = start
                while i < end { peak = max(peak, ch[i] == Int16.min ? Int16.max : abs(ch[i])); i += max(1, per / 64) }
                let h = CGFloat(peak) / 32768 * size.height / 2
                let x = CGFloat(b) * 2
                path.addRect(CGRect(x: x, y: size.height / 2 - h, width: 1.2, height: max(1, h * 2)))
            }
            ctx.fill(path, with: .color(.accentColor.opacity(0.8)))
            if let loopStart, loopStart > 0 {
                let x = CGFloat(loopStart) / CGFloat(ch.count) * size.width
                var l = Path(); l.move(to: CGPoint(x: x, y: 0)); l.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(l, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                ctx.draw(Text("Loop").font(.caption2.bold()).foregroundColor(.orange), at: CGPoint(x: x + 4, y: 6), anchor: .topLeading)
            }
        }
    }
}

// MARK: - Sound Effects

struct SoundsSection: View {
    @Environment(ThemeDocument.self) private var doc

    var body: some View {
        @Bindable var doc = doc
        EditorPage {
            PageHeader(section: .sounds, text: "Replace the HOME Menu's sound effects. Drop any short MP3/WAV/M4A onto a slot. It's trimmed, leveled and converted to BCWAV automatically.")

            Card {
                HStack {
                    CardHeader(title: "Custom Sound Effects", symbol: "speaker.wave.3")
                    Spacer()
                    Toggle("Use custom sound effects", isOn: $doc.theme.flags.soundEffects)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(doc.sfx.isEmpty)
                }
                SizeMeter(label: "Sound effects size", used: doc.sfx.isEmpty ? 0 : doc.sfx.estimatedSize, limit: ThemeLimits.maxSoundEffects)
            }

            Card {
                ForEach(SoundEffectSlot.allCases) { slot in
                    SoundSlotRow(slot: slot)
                    if slot != SoundEffectSlot.allCases.last { Divider() }
                }
            }

            InfoBanner(text: "Custom sound effects are experimental on some theme managers. Keep them short: all eight together must fit in about 187 KB.", symbol: "exclamationmark.triangle", tint: .orange)
        }
    }
}

struct SoundSlotRow: View {
    @Environment(ThemeDocument.self) private var doc
    let slot: SoundEffectSlot
    @State private var targeted = false

    var body: some View {
        let data = doc.sfx.sounds[slot.rawValue]
        HStack(spacing: 12) {
            Image(systemName: slot.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(data == nil ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.18)))
                .foregroundStyle(data == nil ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title).font(.callout.weight(.medium))
                Text(data == nil ? slot.detail : "\(doc.sfxNames[slot.rawValue] ?? "Custom sound") · \(formatBytes(data?.count ?? 0))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if data != nil {
                Button { doc.playSound(slot) } label: { Image(systemName: "play.fill") }.help("Play")
                Button(role: .destructive) { doc.clearSound(slot) } label: { Image(systemName: "xmark") }.help("Remove")
            }
            Button("Choose…") {
                if let u = FilePanels.open(types: FilePanels.sfxTypes, title: "Choose a sound for \(slot.title)") { doc.importSound(url: u, slot: slot) }
            }
        }
        .controlSize(.small)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.12) : .clear))
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            doc.importSound(url: u, slot: slot)
            return true
        } isTargeted: { targeted = $0 }
    }
}
