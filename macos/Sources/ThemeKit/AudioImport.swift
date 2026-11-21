import Foundation
import AVFoundation

/// Imports any audio file macOS can read (WAV, MP3, AAC/M4A, AIFF, FLAC, CAF…) as 16-bit PCM.
public enum AudioImport {
    public static func load(url: URL, sampleRate: Int, channels: Int, maxSeconds: Double? = nil) throws -> PCMAudio {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                                            channels: AVAudioChannelCount(channels), interleaved: false) else {
            throw ThemeKitError.invalidFormat("Unsupported output audio format.")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ThemeKitError.invalidFormat("macOS can't convert this audio file.")
        }
        if inFormat.channelCount > 1 && channels == 1 {
            converter.downmix = true
        }
        let ratio = Double(sampleRate) / inFormat.sampleRate
        var expected = Int(Double(file.length) * ratio) + 4096
        if let maxSeconds { expected = min(expected, Int(maxSeconds * Double(sampleRate)) + 4096) }

        var out = [[Float]](repeating: [], count: channels)
        for c in 0..<channels { out[c].reserveCapacity(expected) }

        let inCapacity: AVAudioFrameCount = 16384
        let outCapacity = AVAudioFrameCount(Double(inCapacity) * ratio) + 1024
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw ThemeKitError.invalidFormat("Could not allocate audio buffers.")
        }
        var finished = false
        var readError: Error?
        let maxFrames = maxSeconds.map { Int($0 * Double(sampleRate)) }

        while true {
            outBuffer.frameLength = 0
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
                if finished { inputStatus.pointee = .endOfStream; return nil }
                do {
                    inBuffer.frameLength = 0
                    try file.read(into: inBuffer, frameCount: inCapacity)
                } catch {
                    readError = error
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let convError { throw convError }
            let n = Int(outBuffer.frameLength)
            if n > 0, let data = outBuffer.floatChannelData {
                for c in 0..<channels {
                    out[c].append(contentsOf: UnsafeBufferPointer(start: data[c], count: n))
                }
            }
            if let maxFrames, (out.first?.count ?? 0) >= maxFrames { break }
            if status == .endOfStream || status == .error { break }
            if status == .inputRanDry && finished && n == 0 { break }
        }
        if let readError, out.first?.isEmpty ?? true { throw readError }

        var pcm = out.map { ch in ch.map { Int16(clamping: Int(($0 * 32767).rounded())) } }
        if let maxFrames {
            pcm = pcm.map { Array($0.prefix(maxFrames)) }
        }
        return PCMAudio(sampleRate: sampleRate, channels: pcm)
    }

    /// Writes PCM audio as a standard 16-bit WAV file (for previewing with AVAudioPlayer).
    public static func wavData(_ audio: PCMAudio) -> Data {
        let ch = max(1, audio.channels.count)
        let n = audio.sampleCount
        var w = ByteWriter(capacity: 44 + n * ch * 2)
        w.ascii("RIFF"); w.u32(36 + n * ch * 2); w.ascii("WAVE")
        w.ascii("fmt "); w.u32(16); w.u16(1); w.u16(UInt16(ch)); w.u32(audio.sampleRate)
        w.u32(audio.sampleRate * ch * 2); w.u16(UInt16(ch * 2)); w.u16(16)
        w.ascii("data"); w.u32(n * ch * 2)
        for i in 0..<n {
            for c in 0..<ch { w.i16(audio.channels[c][i]) }
        }
        return Data(w.bytes)
    }
}
