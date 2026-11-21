import AVFoundation
import ThemeKit

/// Plays PCM audio, honoring the loop point (intro once, then loop forever) like the 3DS does.
final class AudioPreviewPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false
    private(set) var isPlaying = false

    func play(_ pcm: PCMAudio, loop: Bool) {
        stop()
        guard pcm.sampleCount > 0, !pcm.channels.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(pcm.sampleRate),
                                         channels: AVAudioChannelCount(pcm.channels.count), interleaved: false) else { return }
        if !attached {
            engine.attach(node)
            attached = true
        }
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        func buffer(_ range: Range<Int>) -> AVAudioPCMBuffer? {
            guard !range.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)) else { return nil }
            b.frameLength = AVAudioFrameCount(range.count)
            guard let data = b.floatChannelData else { return nil }
            for (c, ch) in pcm.channels.enumerated() {
                let dst = data[c]
                var j = 0
                for i in range { dst[j] = Float(ch[i]) / 32768; j += 1 }
            }
            return b
        }

        do {
            if !engine.isRunning { try engine.start() }
        } catch { return }

        let loopStart = (loop && pcm.looping) ? min(pcm.loopStart, pcm.sampleCount - 1) : 0
        if loop {
            if loopStart > 0, let intro = buffer(0..<loopStart) { node.scheduleBuffer(intro, completionHandler: nil) }
            if let body = buffer(loopStart..<pcm.sampleCount) { node.scheduleBuffer(body, at: nil, options: .loops, completionHandler: nil) }
        } else if let all = buffer(0..<pcm.sampleCount) {
            node.scheduleBuffer(all, completionHandler: nil)
        }
        node.play()
        isPlaying = true
    }

    func stop() {
        if attached { node.stop() }
        isPlaying = false
    }
}
