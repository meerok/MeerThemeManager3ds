import Foundation

/// Edits applied to imported audio before it's converted to BCSTM / BCWAV.
public struct AudioEdit: Codable, Hashable {
    public var startSeconds: Double = 0     // skip the beginning
    public var maxSeconds: Double = 0       // 0 = keep everything
    public var gainDB: Double = 0           // -12 … +12
    public var normalize = true             // raise to full volume without clipping
    public var fadeInSeconds: Double = 0
    public var fadeOutSeconds: Double = 0
    public var trimSilence = false          // remove quiet lead-in / tail
    public init() {}
}

public enum AudioProcess {
    /// Applies trimming, gain/normalize and fades. Loop information is cleared.
    public static func apply(_ input: PCMAudio, _ e: AudioEdit) -> PCMAudio {
        var a = input
        a.looping = false
        a.loopStart = 0
        let rate = Double(a.sampleRate)

        if e.trimSilence { a = trimSilence(a) }

        let start = min(a.sampleCount, max(0, Int(e.startSeconds * rate)))
        var end = a.sampleCount
        if e.maxSeconds > 0 { end = min(end, start + Int(e.maxSeconds * rate)) }
        if start > 0 || end < a.sampleCount {
            a.channels = a.channels.map { Array($0[start..<max(start, end)]) }
        }
        let n = a.sampleCount
        guard n > 0 else { return a }

        var gain = pow(10, e.gainDB / 20)
        if e.normalize {
            var peak = 1
            for ch in a.channels { for s in ch { peak = max(peak, abs(Int(s))) } }
            gain *= 32000.0 / Double(peak)
        }
        let fadeIn = Int(e.fadeInSeconds * rate), fadeOut = Int(e.fadeOutSeconds * rate)
        if gain != 1 || fadeIn > 0 || fadeOut > 0 {
            a.channels = a.channels.map { ch in
                var out = ch
                for i in 0..<n {
                    var g = gain
                    if fadeIn > 0 && i < fadeIn { g *= Double(i) / Double(fadeIn) }
                    if fadeOut > 0 && i >= n - fadeOut { g *= Double(n - 1 - i) / Double(fadeOut) }
                    out[i] = Int16(clamping: Int((Double(ch[i]) * g).rounded()))
                }
                return out
            }
        }
        return a
    }

    /// Removes leading and trailing near-silence (below about -48 dB).
    public static func trimSilence(_ a: PCMAudio, threshold: Int16 = 128) -> PCMAudio {
        let n = a.sampleCount
        guard n > 0 else { return a }
        func loud(_ i: Int) -> Bool { a.channels.contains { abs(Int($0[i])) > Int(threshold) } }
        var first = 0
        while first < n && !loud(first) { first += 1 }
        var last = n - 1
        while last > first && !loud(last) { last -= 1 }
        guard first < n else { return a }
        let pad = min(Int(Double(a.sampleRate) * 0.01), first)   // keep 10 ms before the attack
        var out = a
        out.channels = a.channels.map { Array($0[(first - pad)...last]) }
        return out
    }

    /// Bytes needed for DSP-ADPCM audio of this length.
    public static func estimatedBCSTMSize(seconds: Double, sampleRate: Int, channels: Int) -> Int {
        let samples = Int(seconds * Double(sampleRate))
        return 0x200 + DSPADPCM.sampleCountToByteCount(samples) * channels + (samples / 14336 + 1) * 4 * channels
    }
}
