import Foundation
import ThemeKit

// Command-line companion for Meer Theme Manager 3ds (MtM3): batch conversion and self-tests.
//
//   mtm3-cli info <theme folder | .zip | body_LZ.bin>
//   mtm3-cli bgm <audio file> <out.bcstm> [--rate 32000] [--mono] [--loop-start seconds]
//   mtm3-cli selftest <output folder>

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("""
    mtm3-cli — tools for 3DS HOME Menu themes
      info <theme>                         Show what's inside a theme folder, zip or body_LZ.bin
      bgm <audio> <out.bcstm> [--rate N] [--mono] [--loop-start S]
                                           Convert any audio file to a looping BCSTM
      sfx <audio> <out.bcwav>              Convert audio to a BCWAV sound effect
      selftest <folder>                    Write test files used to verify the encoders
    """)
    exit(0)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch args[1] {
case "info":
    guard args.count >= 3 else { fail("usage: info <theme>") }
    do {
        let pkg = try ThemePackage.load(url: URL(fileURLWithPath: args[2]))
        let f = pkg.theme.flags
        print("Name:        \(pkg.info.primaryTitle.shortDescription)")
        print("Description: \(pkg.info.primaryTitle.longDescription)")
        print("Author:      \(pkg.info.primaryTitle.publisher)")
        print("Top:         \(f.topDrawType) / \(f.topFrameType)")
        print("Bottom:      \(f.bottomDrawType) / \(f.bottomFrameType)")
        print("Folder tex:  \(f.folderTexture)  File tex: \(f.fileTexture)")
        print("BGM flag:    \(f.backgroundMusic)  bgm file: \(pkg.bgm.map { "\($0.count) bytes" } ?? "none")")
        print("SFX:         \(f.soundEffects) (\(pkg.theme.soundEffectData.count) bytes)")
        let body = pkg.theme.writeCompressedBody()
        print("Re-encoded body_LZ.bin: \(body.count) bytes")
    } catch { fail("error: \(error.localizedDescription)") }

case "bgm":
    guard args.count >= 4 else { fail("usage: bgm <audio> <out.bcstm>") }
    do {
        let rate = Int(option("--rate") ?? "32000") ?? 32000
        let mono = args.contains("--mono")
        var pcm = try AudioImport.load(url: URL(fileURLWithPath: args[2]), sampleRate: rate, channels: mono ? 1 : 2)
        pcm.looping = true
        if let s = option("--loop-start"), let sec = Double(s) { pcm.loopStart = Int(sec * Double(rate)) }
        let out = BCSTM.encode(pcm)
        try Data(out).write(to: URL(fileURLWithPath: args[3]))
        print("Wrote \(out.count) bytes (\(String(format: "%.1f", pcm.duration)) s)\(out.count > ThemeLimits.maxBGM ? " — WARNING: over the 3DS limit" : "")")
    } catch { fail("error: \(error.localizedDescription)") }

case "sfx":
    guard args.count >= 4 else { fail("usage: sfx <audio> <out.bcwav>") }
    do {
        let pcm = try AudioImport.load(url: URL(fileURLWithPath: args[2]), sampleRate: 16000, channels: 1)
        let out = BCWAV.encode(pcm)
        try Data(out).write(to: URL(fileURLWithPath: args[3]))
        print("Wrote \(out.count) bytes")
    } catch { fail("error: \(error.localizedDescription)") }

case "selftest":
    guard args.count >= 3 else { fail("usage: selftest <folder>") }
    let dir = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func write(_ name: String, _ bytes: [UInt8]) {
        try! Data(bytes).write(to: dir.appendingPathComponent(name))
        print("  \(name): \(bytes.count) bytes")
    }

    // Deterministic test signal: two tones + noise, stereo, 32 kHz, 5 s.
    let rate = 32000
    let n = rate * 5 + 1234
    var seed: UInt32 = 12345
    func rnd() -> Double { seed = seed &* 1103515245 &+ 12345; return Double((seed >> 16) & 0x7FFF) / 32767.0 - 0.5 }
    var left = [Int16](repeating: 0, count: n), right = [Int16](repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / Double(rate)
        let env = min(1.0, t * 4)
        left[i] = Int16(clamping: Int(env * (9000 * sin(2 * .pi * 440 * t) + 3000 * sin(2 * .pi * 1250 * t) + 1500 * rnd())))
        right[i] = Int16(clamping: Int(env * (8000 * sin(2 * .pi * 330 * t) + 2500 * sin(2 * .pi * 2210 * t) + 1500 * rnd())))
    }
    let pcm = PCMAudio(sampleRate: rate, channels: [left, right], looping: true, loopStart: 0)
    print("Writing self-test files to \(dir.path)")
    write("test_signal.wav", [UInt8](AudioImport.wavData(pcm)))
    write("test_loop0.bcstm", BCSTM.encode(pcm))
    var pcm2 = pcm; pcm2.loopStart = 14336 * 3   // aligned loop
    write("test_loop3blocks.bcstm", BCSTM.encode(pcm2))
    var pcm3 = pcm; pcm3.loopStart = 50000       // unaligned loop (gets aligned)
    write("test_loopunaligned.bcstm", BCSTM.encode(pcm3))
    write("test_mono.bcwav", BCWAV.encode(PCMAudio(sampleRate: 16000, channels: [Array(left.prefix(8000))])))
    let coefs = DSPADPCM.calculateCoefficients(left)
    write("test_left.coefs", coefs.flatMap { [UInt8(truncatingIfNeeded: UInt16(bitPattern: $0)), UInt8(truncatingIfNeeded: UInt16(bitPattern: $0) >> 8)] })

    // Theme with every feature enabled
    var theme = Theme()
    var f = ThemeFlags()
    f.topDrawType = .texture; f.topFrameType = .slowScroll
    f.bottomDrawType = .texture; f.bottomFrameType = .bounceScroll
    f.cursorColor = true; f.folderColor = true; f.fileColor = true; f.arrowButtonColor = true; f.arrowColor = true
    f.openCloseColor = true; f.gameTextDrawType = .colored; f.bottomInnerColor = true; f.bottomOuterColor = true
    f.folderBackgroundColor = true; f.folderArrowColor = true; f.bottomCornerColor = true; f.topCornerColor = true
    f.demoTextColor = true; f.folderTexture = true; f.fileTexture = true; f.backgroundMusic = true; f.soundEffects = true
    theme.flags = f
    func gradient(_ w: Int, _ h: Int) -> RGBImage {
        var img = RGBImage(width: w, height: h)
        for y in 0..<h { for x in 0..<w { img.setPixel(x, y, RGB(UInt8(x * 255 / max(1, w - 1)), UInt8(y * 255 / max(1, h - 1)), UInt8((x ^ y) & 0xFF))) } }
        return img
    }
    theme.textures.top = gradient(1024, 256)
    theme.textures.bottom = gradient(1024, 256)
    theme.textures.folderClosed = gradient(128, 64)
    theme.textures.folderOpen = gradient(128, 64)
    theme.textures.fileLarge = gradient(64, 128)
    theme.textures.fileSmall = gradient(32, 64)
    theme.colors.cursor.main = RGB(1, 2, 3)
    theme.colors.topCorner.text = RGB(200, 100, 50)
    var sfx = SoundEffectBlock()
    sfx.sounds[0] = Data(BCWAV.encode(PCMAudio(sampleRate: 16000, channels: [Array(left.prefix(4000))])))
    sfx.sounds[4] = Data(BCWAV.encode(PCMAudio(sampleRate: 16000, channels: [Array(right.prefix(3000))])))
    theme.soundEffectData = sfx.encode()
    let raw = theme.writeBody()
    write("theme_body_decompressed.bin", raw)
    let lz = LZ11.compress(raw)
    write("body_LZ.bin", lz)
    let back = try! LZ11.decompress(lz)
    print("  LZ11 round trip: \(back == raw ? "OK" : "MISMATCH")")
    let reread = try! Theme.read(body: lz)
    print("  Theme flags round trip: \(reread.flags == theme.flags ? "OK" : "MISMATCH")")
    print("  Theme colors round trip: \(reread.colors.cursor == theme.colors.cursor && reread.colors.topCorner == theme.colors.topCorner ? "OK" : "MISMATCH")")
    print("  SFX round trip: \(SoundEffectBlock.decode(reread.soundEffectData) == sfx ? "OK" : "MISMATCH")")
    let rt = reread.writeBody()
    print("  Body re-encode stable: \(rt.count == raw.count ? "size OK" : "size differs")")
    var info = SMDH()
    info.setAllTitles(name: "Self Test", description: "Generated by mtm3-cli", author: "MtM3")
    write("info.smdh", info.write())
    let infoBack = try! SMDH.read(info.write())
    print("  SMDH round trip: \(infoBack.primaryTitle == info.primaryTitle ? "OK" : "MISMATCH")")

    // Static variant + color/pattern variant
    var t2 = Theme()
    t2.flags.topDrawType = .solidColorTexture
    t2.flags.bottomDrawType = .solidColor
    t2.textures.topPattern = ThemeDefaults.defaultPattern
    t2.textures.topAltPattern = gradient(64, 64)
    t2.colors.topBackground.main = RGB(255, 128, 0)
    write("body_pattern_LZ.bin", t2.writeCompressedBody())
    let t2b = try! Theme.read(body: t2.writeCompressedBody())
    print("  Pattern texture round trip: \(t2b.textures.topPattern == t2.textures.topPattern ? "OK" : "MISMATCH")")

    // Big random body for LZ timing
    var big = [UInt8](repeating: 0, count: 1_100_000)
    for i in 0..<big.count { big[i] = UInt8(truncatingIfNeeded: (i / 7) ^ Int(rnd() * 4)) }
    let t0 = Date()
    let bigLZ = LZ11.compress(big)
    let dt = Date().timeIntervalSince(t0)
    print("  LZ11 1.1MB: \(bigLZ.count) bytes in \(String(format: "%.2f", dt)) s, round trip \((try? LZ11.decompress(bigLZ)) == big ? "OK" : "MISMATCH")")
    print("Done.")

default:
    fail("Unknown command \(args[1])")
}
