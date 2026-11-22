import Foundation

/// Uncompressed 16-bit audio, one array per channel.
public struct PCMAudio: Hashable {
    public var sampleRate: Int
    public var channels: [[Int16]]
    public var looping: Bool = false
    public var loopStart: Int = 0

    public init(sampleRate: Int, channels: [[Int16]], looping: Bool = false, loopStart: Int = 0) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.looping = looping
        self.loopStart = loopStart
    }

    public var sampleCount: Int { channels.first?.count ?? 0 }
    public var duration: Double { sampleRate > 0 ? Double(sampleCount) / Double(sampleRate) : 0 }
}

private func nextMultiple(_ v: Int, _ m: Int) -> Int { v % m == 0 ? v : v + (m - v % m) }

/// Encoded DSP-ADPCM channel with the context needed by NintendoWare containers.
struct EncodedChannel {
    var coefs: [Int16]
    var adpcm: [UInt8]
    var decoded: [Int16]
    var startPredScale: Int16
    var loopPredScale: Int16
    var loopHist1: Int16
    var loopHist2: Int16

    init(pcm: [Int16], loopStart: Int, looping: Bool) {
        coefs = DSPADPCM.calculateCoefficients(pcm)
        adpcm = DSPADPCM.encode(pcm, coefs: coefs)
        decoded = DSPADPCM.decode(adpcm, coefs: coefs, sampleCount: pcm.count)
        startPredScale = adpcm.isEmpty ? 0 : Int16(adpcm[0])
        if looping {
            let frameByte = (loopStart / 14) * 8
            loopPredScale = frameByte < adpcm.count ? Int16(adpcm[frameByte]) : 0
            loopHist1 = loopStart >= 1 ? decoded[loopStart - 1] : 0
            loopHist2 = loopStart >= 2 ? decoded[loopStart - 2] : 0
        } else {
            loopPredScale = startPredScale
            loopHist1 = 0
            loopHist2 = 0
        }
    }

    func writeAdpcmInfo(_ w: inout ByteWriter) {
        for c in coefs { w.i16(c) }
        w.i16(startPredScale); w.i16(0); w.i16(0)
        w.i16(loopPredScale); w.i16(loopHist1); w.i16(loopHist2)
        w.i16(0)
    }
}

// MARK: - BCSTM (background music)

public enum BCSTM {
    public static let samplesPerBlock = 0x3800   // 14336 samples = 0x2000 bytes of ADPCM
    public static let blockSize = 0x2000

    /// Makes the loop start a multiple of the block size by repeating the start of the loop,
    /// which is how official tools keep loops seamless.
    public static func alignLoop(_ audio: PCMAudio) -> PCMAudio {
        guard audio.looping, audio.loopStart > 0, audio.loopStart % samplesPerBlock != 0 else { return audio }
        let aligned = nextMultiple(audio.loopStart, samplesPerBlock)
        let shift = aligned - audio.loopStart
        var out = audio
        out.channels = audio.channels.map { ch in
            var c = ch
            for i in 0..<shift { c.append(ch[audio.loopStart + (i % max(1, ch.count - audio.loopStart))]) }
            return c
        }
        out.loopStart = aligned
        return out
    }

    /// Encodes PCM audio to a DSP-ADPCM BCSTM (version 2.1, as written by VGAudio / official tools).
    public static func encode(_ input: PCMAudio, progress: ((Double) -> Void)? = nil) -> [UInt8] {
        let audio = alignLoop(input)
        let channelCount = audio.channels.count
        let sampleCount = audio.sampleCount
        let loopStart = audio.looping ? audio.loopStart : 0

        var encoded: [EncodedChannel] = []
        for (i, ch) in audio.channels.enumerated() {
            encoded.append(EncodedChannel(pcm: ch, loopStart: loopStart, looping: audio.looping))
            progress?(Double(i + 1) / Double(channelCount))
        }

        let trackCount = (channelCount + 1) / 2
        let audioDataSize = nextMultiple(DSPADPCM.sampleCountToByteCount(sampleCount), 0x20)
        let interleaveCount = max(1, (sampleCount + samplesPerBlock - 1) / samplesPerBlock)
        let lastBlockSamples = sampleCount - (interleaveCount - 1) * samplesPerBlock
        let lastBlockSizeNoPad = DSPADPCM.sampleCountToByteCount(lastBlockSamples)
        let lastBlockSize = nextMultiple(lastBlockSizeNoPad, 0x20)
        let seekEntries = max(1, (sampleCount + samplesPerBlock - 1) / samplesPerBlock)

        let info1Size = 0x38  // CSTM v2.0 stream info (no region info), same layout BrawlLib writes
        let info2Size = 4 + 8 * trackCount
        let info3Size = (4 + 8 * channelCount) + 0x14 * trackCount + 8 * channelCount + 0x2E * channelCount
        let infoSize = nextMultiple(8 + 24 + info1Size + info2Size + info3Size, 0x20)
        let seekSize = nextMultiple(8 + seekEntries * channelCount * 4, 0x20)
        let headerSize = 0x40
        let infoOffset = headerSize
        let seekOffset = headerSize + infoSize
        let dataOffset = seekOffset + seekSize
        let dataSize = 0x20 + audioDataSize * channelCount
        let fileSize = dataOffset + dataSize

        var w = ByteWriter(capacity: fileSize)
        // Header
        w.ascii("CSTM"); w.u16(0xFEFF); w.u16(UInt16(headerSize)); w.u32(UInt32(0x02000000)); w.u32(fileSize)
        w.u16(3); w.u16(0)
        w.u16(0x4000); w.u16(0); w.u32(infoOffset); w.u32(infoSize)
        w.u16(0x4001); w.u16(0); w.u32(seekOffset); w.u32(seekSize)
        w.u16(0x4002); w.u16(0); w.u32(dataOffset); w.u32(dataSize)
        w.padTo(length: headerSize)

        // INFO
        let infoStart = w.count
        w.ascii("INFO"); w.u32(infoSize)
        let tableSize = 24
        w.u16(0x4100); w.u16(0); w.u32(tableSize)
        w.u16(0x0101); w.u16(0); w.u32(tableSize + info1Size)
        w.u16(0x0101); w.u16(0); w.u32(tableSize + info1Size + info2Size)
        // Stream info
        w.u8(2)                                   // codec: DSP-ADPCM
        w.u8(audio.looping ? 1 : 0)
        w.u8(UInt8(channelCount))
        w.u8(0)
        w.u32(audio.sampleRate)
        w.u32(loopStart)
        w.u32(sampleCount)
        w.u32(interleaveCount)
        w.u32(blockSize)
        w.u32(samplesPerBlock)
        w.u32(lastBlockSizeNoPad)
        w.u32(lastBlockSamples)
        w.u32(lastBlockSize)
        w.u32(4)                                  // bytes per seek entry
        w.u32(samplesPerBlock)                    // samples per seek entry
        w.u16(0x1F00); w.u16(0); w.u32(0x18)      // sample data reference (relative to DATA+8)
        // Track reference table
        let channelTableSize = 4 + 8 * channelCount
        w.u32(trackCount)
        for i in 0..<trackCount {
            w.u16(0x4101); w.u16(0); w.u32(info2Size + channelTableSize + 0x14 * i)
        }
        // Channel reference table
        let trackTableSize = 0x14 * trackCount
        w.u32(channelCount)
        for i in 0..<channelCount {
            w.u16(0x4102); w.u16(0); w.u32(channelTableSize + trackTableSize + 8 * i)
        }
        // Track info
        for t in 0..<trackCount {
            let chs = min(channelCount - t * 2, 2)
            w.u8(0x7F); w.u8(0x40); w.u16(0)
            w.u16(0x0100); w.u16(0); w.u32(0xC)
            w.u32(chs)
            w.u8(UInt8(t * 2)); w.u8(UInt8(chs >= 2 ? t * 2 + 1 : 0)); w.u16(0)
        }
        // Channel info → ADPCM info references
        let channelTable2Size = 8 * channelCount
        for i in 0..<channelCount {
            w.u16(0x0300); w.u16(0); w.u32(channelTable2Size - 8 * i + 0x2E * i)
        }
        for ch in encoded { ch.writeAdpcmInfo(&w) }
        w.padTo(length: infoStart + infoSize)

        // SEEK
        w.ascii("SEEK"); w.u32(seekSize)
        for e in 0..<seekEntries {
            for ch in encoded {
                if e == 0 { w.i16(0); w.i16(0) }
                else {
                    let idx = e * samplesPerBlock
                    w.i16(idx - 1 < ch.decoded.count ? ch.decoded[idx - 1] : 0)
                    w.i16(idx - 2 < ch.decoded.count ? ch.decoded[idx - 2] : 0)
                }
            }
        }
        w.padTo(length: seekOffset + seekSize)

        // DATA
        w.ascii("DATA"); w.u32(dataSize)
        w.padTo(length: dataOffset + 0x20)
        for b in 0..<interleaveCount {
            let outSize = b == interleaveCount - 1 ? lastBlockSize : blockSize
            for ch in encoded {
                let start = b * blockSize
                let end = min(start + outSize, ch.adpcm.count)
                if start < end { w.append(Array(ch.adpcm[start..<end])) }
                w.zeros(outSize - max(0, end - start))
            }
        }
        w.padTo(length: fileSize)
        return w.bytes
    }

    public struct Info {
        public var sampleRate: Int
        public var channelCount: Int
        public var sampleCount: Int
        public var looping: Bool
        public var loopStart: Int
        public var codec: Int
        public var duration: Double { sampleRate > 0 ? Double(sampleCount) / Double(sampleRate) : 0 }
    }

    /// Decodes a BCSTM (DSP-ADPCM, PCM16 or PCM8) into PCM for previewing.
    public static func decode(_ bytes: [UInt8]) throws -> (PCMAudio, Info) {
        var r = ByteReader(bytes)
        guard try r.ascii(4) == "CSTM" else { throw ThemeKitError.invalidFormat("This is not a BCSTM file.") }
        guard try r.u16() == 0xFEFF else { throw ThemeKitError.invalidFormat("Unsupported BCSTM byte order.") }
        _ = try r.u16()
        let version = try r.u32()
        _ = try r.u32()
        let blockCount = Int(try r.u16()); try r.skip(2)
        var infoOff = 0, dataOff = 0
        for _ in 0..<blockCount {
            let type = try r.u16(); try r.skip(2)
            let off = try r.int(); _ = try r.u32()
            if type == 0x4000 { infoOff = off }
            if type == 0x4002 { dataOff = off }
        }
        guard infoOff > 0, dataOff > 0 else { throw ThemeKitError.invalidFormat("BCSTM is missing INFO or DATA.") }
        r.position = infoOff
        guard try r.ascii(4) == "INFO" else { throw ThemeKitError.invalidFormat("Invalid BCSTM INFO block.") }
        _ = try r.u32()
        let base = r.position
        try r.skip(2 + 2); let streamRef = try r.int()
        try r.skip(4); _ = try r.u32()
        try r.skip(4); let channelRef = try r.int()

        r.position = base + streamRef
        let codec = Int(try r.u8())
        let looping = try r.u8() != 0
        let channelCount = Int(try r.u8())
        try r.skip(1)
        let sampleRate = try r.int()
        let loopStart = try r.int()
        let sampleCount = try r.int()
        let blockCountI = try r.int()
        let blockSizeI = try r.int()
        _ = try r.int()
        _ = try r.int()
        _ = try r.int()
        let lastBlockSizePadded = try r.int()
        _ = try r.int(); _ = try r.int()
        try r.skip(4); let sampleDataOffset = try r.int()
        _ = version

        // Channel info → coefficients
        var coefs: [[Int16]] = []
        var starts: [(Int16, Int16)] = []
        if codec == 2 {
            let tableStart = base + channelRef
            r.position = tableStart
            let count = try r.int()
            var entryOffsets: [Int] = []
            for _ in 0..<count {
                try r.skip(4)
                let rel = try r.int()
                entryOffsets.append(tableStart + rel)
            }
            for e in entryOffsets {
                r.position = e
                try r.skip(4)
                let adpcmOff = try r.int()
                r.position = e + adpcmOff
                var c: [Int16] = []
                for _ in 0..<16 { c.append(try r.i16()) }
                _ = try r.i16()
                let h1 = try r.i16(), h2 = try r.i16()
                coefs.append(c); starts.append((h1, h2))
            }
        }

        // De-interleave
        let audioStart = dataOff + 8 + sampleDataOffset
        var perChannel = [[UInt8]](repeating: [], count: channelCount)
        var p = audioStart
        for b in 0..<blockCountI {
            let size = b == blockCountI - 1 ? lastBlockSizePadded : blockSizeI
            for c in 0..<channelCount {
                let end = min(p + size, bytes.count)
                if p < end { perChannel[c].append(contentsOf: bytes[p..<end]) }
                p += size
            }
        }
        var channels: [[Int16]] = []
        for c in 0..<channelCount {
            let raw = perChannel[c]
            switch codec {
            case 2:
                let cf = c < coefs.count ? coefs[c] : [Int16](repeating: 0, count: 16)
                let st = c < starts.count ? starts[c] : (0, 0)
                channels.append(DSPADPCM.decode(raw, coefs: cf, sampleCount: sampleCount, hist1: st.0, hist2: st.1))
            case 1:
                var s = [Int16](repeating: 0, count: sampleCount)
                for i in 0..<min(sampleCount, raw.count / 2) { s[i] = Int16(bitPattern: UInt16(raw[i * 2]) | UInt16(raw[i * 2 + 1]) << 8) }
                channels.append(s)
            case 0:
                var s = [Int16](repeating: 0, count: sampleCount)
                for i in 0..<min(sampleCount, raw.count) { s[i] = Int16(Int8(bitPattern: raw[i])) << 8 }
                channels.append(s)
            default:
                throw ThemeKitError.invalidFormat("Unsupported BCSTM codec (\(codec)).")
            }
        }
        let info = Info(sampleRate: sampleRate, channelCount: channelCount, sampleCount: sampleCount, looping: looping, loopStart: loopStart, codec: codec)
        return (PCMAudio(sampleRate: sampleRate, channels: channels, looping: looping, loopStart: loopStart), info)
    }
}

// MARK: - BCWAV (sound effects)

public enum BCWAV {
    /// Encodes mono PCM to a DSP-ADPCM BCWAV (version 2.1).
    public static func encode(_ audio: PCMAudio) -> [UInt8] {
        let mono: [Int16]
        if audio.channels.count > 1 {
            let n = audio.sampleCount
            mono = (0..<n).map { i in
                var s = 0
                for ch in audio.channels { s += Int(ch[i]) }
                return Int16(clamping: s / audio.channels.count)
            }
        } else {
            mono = audio.channels.first ?? []
        }
        let ch = EncodedChannel(pcm: mono, loopStart: 0, looping: false)
        let sampleCount = mono.count

        let headerSize = 0x40
        let infoBodySize = 0x14 + 4 + 8 + 0x14 + 0x2E   // stream info + table + channel info + adpcm info
        let infoSize = nextMultiple(8 + infoBodySize, 0x20)
        let audioBytes = DSPADPCM.sampleCountToByteCount(sampleCount)
        let dataSize = nextMultiple(0x20 + audioBytes, 0x20)
        let infoOffset = headerSize
        let dataOffset = headerSize + infoSize
        let fileSize = dataOffset + dataSize

        var w = ByteWriter(capacity: fileSize)
        w.ascii("CWAV"); w.u16(0xFEFF); w.u16(UInt16(headerSize)); w.u32(UInt32(0x02010000)); w.u32(fileSize)
        w.u16(2); w.u16(0)
        w.u16(0x7000); w.u16(0); w.u32(infoOffset); w.u32(infoSize)
        w.u16(0x7001); w.u16(0); w.u32(dataOffset); w.u32(dataSize)
        w.padTo(length: headerSize)

        w.ascii("INFO"); w.u32(infoSize)
        w.u8(2); w.u8(0); w.u16(0)          // DSP-ADPCM, no loop
        w.u32(audio.sampleRate)
        w.u32(0)                            // loop start
        w.u32(sampleCount)                  // loop end / sample count
        w.u32(0)                            // reserved
        // channel info reference table (offsets relative to the table start)
        w.u32(1)
        w.u16(0x7100); w.u16(0); w.u32(0xC)
        // channel info
        w.u16(0x1F00); w.u16(0); w.u32(0x18)   // samples, relative to DATA+8
        w.u16(0x0300); w.u16(0); w.u32(0x14)   // ADPCM info, relative to channel info
        w.u32(0)
        ch.writeAdpcmInfo(&w)
        w.padTo(length: infoOffset + infoSize)

        w.ascii("DATA"); w.u32(dataSize)
        w.padTo(length: dataOffset + 0x20)
        w.append(ch.adpcm)
        w.padTo(length: fileSize)
        return w.bytes
    }

    /// Decodes a BCWAV for previewing (DSP-ADPCM, PCM16, PCM8; first channel only).
    public static func decode(_ bytes: [UInt8]) throws -> PCMAudio {
        var r = ByteReader(bytes)
        guard try r.ascii(4) == "CWAV" else { throw ThemeKitError.invalidFormat("This is not a BCWAV file.") }
        guard try r.u16() == 0xFEFF else { throw ThemeKitError.invalidFormat("Unsupported BCWAV byte order.") }
        try r.skip(2 + 4 + 4)
        let blocks = Int(try r.u16()); try r.skip(2)
        var infoOff = 0, dataOff = 0
        for _ in 0..<blocks {
            let type = try r.u16(); try r.skip(2)
            let off = try r.int(); _ = try r.u32()
            if type == 0x7000 { infoOff = off }
            if type == 0x7001 { dataOff = off }
        }
        guard infoOff > 0, dataOff > 0 else { throw ThemeKitError.invalidFormat("BCWAV is missing INFO or DATA.") }
        r.position = infoOff + 8
        let codec = Int(try r.u8()); try r.skip(3)
        let rate = try r.int()
        _ = try r.int()
        let count = try r.int()
        try r.skip(4)
        let tableStart = r.position
        let n = try r.int()
        guard n > 0 else { throw ThemeKitError.invalidFormat("BCWAV has no channels.") }
        try r.skip(4)
        let chRel = try r.int()
        let chInfo = tableStart + chRel
        r.position = chInfo
        try r.skip(4); let sampleOff = try r.int()
        try r.skip(4); let adpcmOff = try r.int()
        let start = dataOff + 8 + sampleOff
        guard start <= bytes.count else { throw ThemeKitError.unexpectedEnd }
        let raw = Array(bytes[start..<bytes.count])
        var pcm: [Int16]
        switch codec {
        case 2:
            r.position = chInfo + adpcmOff
            var c: [Int16] = []
            for _ in 0..<16 { c.append(try r.i16()) }
            _ = try r.i16()
            let h1 = try r.i16(), h2 = try r.i16()
            pcm = DSPADPCM.decode(raw, coefs: c, sampleCount: count, hist1: h1, hist2: h2)
        case 1:
            pcm = (0..<min(count, raw.count / 2)).map { Int16(bitPattern: UInt16(raw[$0 * 2]) | UInt16(raw[$0 * 2 + 1]) << 8) }
        case 0:
            pcm = (0..<min(count, raw.count)).map { Int16(Int8(bitPattern: raw[$0])) << 8 }
        default:
            throw ThemeKitError.invalidFormat("Unsupported BCWAV codec (\(codec)).")
        }
        return PCMAudio(sampleRate: rate, channels: [pcm])
    }

    /// Size declared in a CWAV header (offset 0x0C).
    public static func declaredSize(_ bytes: [UInt8]) -> Int {
        bytes.count >= 0x10 ? Int(bytes.readU32LE(0x0C)) : 0
    }
}

// MARK: - Theme sound-effect block

public enum SoundEffectSlot: Int, CaseIterable, Identifiable {
    case cursor = 0, launch, openFolder, closeFolder, frame1, frame2, frame3, openLid
    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .cursor: return "Cursor Move"
        case .launch: return "Launch Software"
        case .openFolder: return "Open Folder"
        case .closeFolder: return "Close Folder"
        case .frame1: return "Scroll Sound 1"
        case .frame2: return "Scroll Sound 2"
        case .frame3: return "Scroll Sound 3"
        case .openLid: return "Open Lid / Wake"
        }
    }

    public var detail: String {
        switch self {
        case .cursor: return "Plays when the cursor moves between icons."
        case .launch: return "Plays when software is opened from the HOME Menu."
        case .openFolder: return "Plays when a folder is opened."
        case .closeFolder: return "Plays when a folder is closed."
        case .frame1, .frame2, .frame3: return "Played while the icon grid scrolls or changes page."
        case .openLid: return "Plays when the system is woken by opening the lid."
        }
    }

    public var symbol: String {
        switch self {
        case .cursor: return "cursorarrow.motionlines"
        case .launch: return "play.circle"
        case .openFolder: return "folder"
        case .closeFolder: return "folder.badge.minus"
        case .frame1, .frame2, .frame3: return "arrow.left.and.right"
        case .openLid: return "sun.max"
        }
    }
}

/// The SFX section of body_LZ.bin: eight optional BCWAV files.
public struct SoundEffectBlock: Hashable {
    public var sounds: [Data?] = Array(repeating: nil, count: 8)

    public init() {}

    public var isEmpty: Bool { sounds.allSatisfy { $0 == nil || $0!.isEmpty } }

    public var estimatedSize: Int { 8 + 44 + sounds.reduce(0) { $0 + 8 + ($1?.count ?? 0) } }

    public func encode() -> [UInt8] {
        var w = ByteWriter()
        w.u32(2)
        w.u32(0x64)
        for i in 0..<8 {
            if i == SoundEffectSlot.frame1.rawValue {
                for v: UInt32 in [0x00, 0x64, 0x00, 0x64, 0x64, 0x00, 0x64, 0x64, 0x00, 0x00, 0x00] { w.u32(v) }
            }
            let d = sounds[i] ?? Data()
            w.u32(d.count)
            w.u32(d.isEmpty ? 1 : 0x50)
            w.append(d)
        }
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) -> SoundEffectBlock {
        var block = SoundEffectBlock()
        guard bytes.count >= 8 else { return block }
        var r = ByteReader(bytes)
        do {
            try r.skip(8)
            for i in 0..<8 {
                if r.remaining == 0 { break }
                if i == SoundEffectSlot.frame1.rawValue { try r.skip(44) }
                var size = try r.int()
                _ = try r.u32()
                if size == 0 { continue }
                if size > r.remaining { size = r.remaining }
                let chunk = try r.read(size)
                guard chunk.count >= 4, String(decoding: chunk[0..<4], as: UTF8.self) == "CWAV" else { break }
                block.sounds[i] = Data(chunk)
            }
        } catch { }
        return block
    }
}
