import Foundation

/// Nintendo DSP-ADPCM ("GC-ADPCM") codec. Port of the encoder in VGAudio (MIT, Alex Barney),
/// which itself reproduces Nintendo's DSPADPCM encoder.
public enum DSPADPCM {
    public static let samplesPerFrame = 14
    public static let bytesPerFrame = 8

    public static func sampleCountToNibbleCount(_ n: Int) -> Int {
        let frames = n / 14, extra = n % 14
        return 16 * frames + (extra == 0 ? 0 : extra + 2)
    }
    public static func sampleCountToByteCount(_ n: Int) -> Int { (sampleCountToNibbleCount(n) + 1) / 2 }
    public static func byteCountToSampleCount(_ b: Int) -> Int {
        let nibbles = b * 2
        let frames = nibbles / 16, extra = nibbles % 16
        return 14 * frames + (extra < 2 ? 0 : extra - 2)
    }

    @inline(__always) static func clamp16(_ v: Int) -> Int { v > 32767 ? 32767 : (v < -32768 ? -32768 : v) }
    @inline(__always) static func clamp4(_ v: Int) -> Int { v > 7 ? 7 : (v < -8 ? -8 : v) }
    static let signedNibbles: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, -8, -7, -6, -5, -4, -3, -2, -1]

    // MARK: Decoder

    public static func decode(_ adpcm: [UInt8], coefs: [Int16], sampleCount: Int, hist1 h1: Int16 = 0, hist2 h2: Int16 = 0) -> [Int16] {
        var pcm = [Int16](repeating: 0, count: sampleCount)
        if sampleCount == 0 { return pcm }
        var hist1 = Int(h1), hist2 = Int(h2)
        var inIndex = 0, out = 0
        let frameCount = (sampleCount + 13) / 14
        for _ in 0..<frameCount {
            guard inIndex < adpcm.count else { break }
            let ps = Int(adpcm[inIndex]); inIndex += 1
            let scale = (1 << (ps & 0xF)) * 2048
            let pred = (ps >> 4) & 0xF
            let c1 = Int(coefs[min(pred * 2, 15)]), c2 = Int(coefs[min(pred * 2 + 1, 15)])
            let toRead = min(14, sampleCount - out)
            for s in 0..<toRead {
                guard inIndex < adpcm.count else { break }
                let nib: Int
                if s % 2 == 0 { nib = signedNibbles[Int(adpcm[inIndex] >> 4)] }
                else { nib = signedNibbles[Int(adpcm[inIndex] & 0xF)]; inIndex += 1 }
                let sample = clamp16((scale * nib + c1 * hist1 + c2 * hist2 + 1024) >> 11)
                hist2 = hist1; hist1 = sample
                pcm[out] = Int16(sample); out += 1
            }
        }
        return pcm
    }

    // MARK: Encoder

    public static func encode(_ pcm: [Int16], coefs: [Int16]) -> [UInt8] {
        let sampleCount = pcm.count
        var adpcm = [UInt8](repeating: 0, count: sampleCountToByteCount(sampleCount))
        var pcmBuffer = [Int](repeating: 0, count: 16)
        var adpcmFrame = [UInt8](repeating: 0, count: 8)
        let frameCount = (sampleCount + 13) / 14
        var coefPairs = [[Int]](repeating: [0, 0], count: 8)
        for i in 0..<8 { coefPairs[i] = [Int(coefs[i * 2]), Int(coefs[i * 2 + 1])] }

        var pcmOut = [[Int]](repeating: [Int](repeating: 0, count: 16), count: 8)
        var adpcmOut = [[Int]](repeating: [Int](repeating: 0, count: 14), count: 8)
        var scales = [Int](repeating: 0, count: 8)
        var dist = [Double](repeating: 0, count: 8)

        for frame in 0..<frameCount {
            let toCopy = min(sampleCount - frame * 14, 14)
            for i in 0..<14 { pcmBuffer[2 + i] = i < toCopy ? Int(pcm[frame * 14 + i]) : 0 }

            for i in 0..<8 {
                encodeCoef(pcmBuffer, 14, coefPairs[i], &pcmOut[i], &adpcmOut[i], &scales[i], &dist[i])
            }
            var best = 0
            var minD = Double.greatestFiniteMagnitude
            for i in 0..<8 where dist[i] < minD { minD = dist[i]; best = i }
            for s in 0..<14 { pcmBuffer[s + 2] = pcmOut[best][s + 2] }
            adpcmFrame[0] = UInt8(((best << 4) | (scales[best] & 0xF)) & 0xFF)
            for i in 0..<7 {
                adpcmFrame[i + 1] = UInt8(((adpcmOut[best][i * 2] << 4) | (adpcmOut[best][i * 2 + 1] & 0xF)) & 0xFF)
            }
            let bytes = sampleCountToByteCount(toCopy)
            for b in 0..<bytes { adpcm[frame * 8 + b] = adpcmFrame[b] }
            pcmBuffer[0] = pcmBuffer[14]
            pcmBuffer[1] = pcmBuffer[15]
        }
        return adpcm
    }

    private static func encodeCoef(_ pcmIn: [Int], _ sampleCount: Int, _ coefs: [Int], _ pcmOut: inout [Int],
                                   _ adpcmOut: inout [Int], _ scalePowerOut: inout Int, _ totalDistance: inout Double) {
        var maxDistance = 0
        pcmOut[0] = pcmIn[0]
        pcmOut[1] = pcmIn[1]
        for s in 0..<sampleCount {
            let input = pcmIn[s + 2]
            let predicted = (pcmIn[s] * coefs[1] + pcmIn[s + 1] * coefs[0]) / 2048
            let d = clamp16(input - predicted)
            if abs(d) > abs(maxDistance) { maxDistance = d }
        }
        var scalePower = 0
        while scalePower <= 12 && (maxDistance > 7 || maxDistance < -8) {
            maxDistance /= 2
            scalePower += 1
        }
        scalePower = scalePower <= 1 ? -1 : scalePower - 2

        var maxOverflow = 0
        repeat {
            scalePower += 1
            let scale = (1 << scalePower) * 2048
            totalDistance = 0
            maxOverflow = 0
            for s in 0..<sampleCount {
                let input = pcmIn[s + 2] * 2048
                let predicted = pcmOut[s] * coefs[1] + pcmOut[s + 1] * coefs[0]
                let distance = input - predicted
                let q = Double(Float(distance) / Float(scale))
                let unclamped = distance > 0 ? Int(q + Double(Float(0.4999999))) : Int(q - Double(Float(0.4999999)))
                let sample = clamp4(unclamped)
                if sample != unclamped {
                    let overflow = abs(unclamped - sample)
                    if overflow > maxOverflow { maxOverflow = overflow }
                }
                adpcmOut[s] = sample
                let corrected = predicted + sample * scale
                let scaled = (corrected + 1024) >> 11
                pcmOut[s + 2] = clamp16(scaled)
                let actual = Double(pcmIn[s + 2] - pcmOut[s + 2])
                totalDistance += actual * actual
            }
            var x = maxOverflow + 8
            while x > 256 {
                scalePower += 1
                if scalePower >= 12 { scalePower = 11 }
                x >>= 1
            }
        } while scalePower < 12 && maxOverflow > 1
        scalePowerOut = scalePower
    }

    // MARK: Coefficients

    public static func calculateCoefficients(_ source: [Int16]) -> [Int16] {
        let frameCount = (source.count + 13) / 14
        var pcmHist = [Int](repeating: 0, count: 28)
        var coefs = [Int16](repeating: 0, count: 16)
        var vec1 = [Double](repeating: 0, count: 3)
        var vec2 = [Double](repeating: 0, count: 3)
        var buffer = [Double](repeating: 0, count: 3)
        var mtx = [[Double]](repeating: [0, 0, 0], count: 3)
        var vecIdxs = [Int](repeating: 0, count: 3)
        var records = [[Double]](repeating: [0, 0, 0], count: max(1, frameCount * 2))
        var recordCount = 0
        var vecBest = [[Double]](repeating: [0, 0, 0], count: 8)

        var sample = 0
        var remaining = source.count
        while sample < source.count {
            for i in 14..<28 { pcmHist[i] = 0 }
            let n = min(14, remaining)
            for i in 0..<n { pcmHist[14 + i] = Int(source[sample + i]) }
            innerProductMerge(&vec1, pcmHist)
            if abs(vec1[0]) > 10.0 {
                outerProductMerge(&mtx, pcmHist)
                if !analyzeRanges(&mtx, &vecIdxs, &buffer) {
                    bidirectionalFilter(mtx, vecIdxs, &vec1)
                    if !quadraticMerge(&vec1) {
                        finishRecord(&vec1, &records[recordCount])
                        recordCount += 1
                    }
                }
            }
            for i in 0..<14 { pcmHist[i] = pcmHist[14 + i] }
            sample += 14
            remaining -= 14
        }

        vec1 = [1.0, 0.0, 0.0]
        for z in 0..<recordCount {
            matrixFilter(records[z], &vecBest[0], &mtx)
            for y in 1...2 { vec1[y] += vecBest[0][y] }
        }
        for y in 1...2 { vec1[y] /= Double(recordCount) }   // NaN when recordCount == 0 (matches reference; handled below)
        mergeFinishRecord(vec1, &vecBest[0])

        var exp = 1
        var w = 0
        while w < 3 {
            vec2 = [0.0, -1.0, 0.0]
            for i in 0..<exp {
                for y in 0...2 { vecBest[exp + i][y] = (0.01 * vec2[y]) + vecBest[i][y] }
            }
            w += 1
            exp = 1 << w
            filterRecords(&vecBest, exp, records, recordCount)
        }

        for z in 0..<8 {
            for k in 1...2 {
                let d = -vecBest[z][k] * 2048.0
                let v: Int16
                if d.isNaN { v = 0 }
                else if d > 0.0 { v = d > 32767 ? 32767 : Int16(d.rounded(.toNearestOrEven)) }
                else { v = d < -32768 ? -32768 : Int16(d.rounded(.toNearestOrEven)) }
                coefs[z * 2 + (k - 1)] = v
            }
        }
        return coefs
    }

    private static func innerProductMerge(_ vecOut: inout [Double], _ pcm: [Int]) {
        for i in 0...2 {
            vecOut[i] = 0.0
            for x in 0..<14 { vecOut[i] -= Double(pcm[14 + x - i] * pcm[14 + x]) }
        }
    }

    private static func outerProductMerge(_ mtxOut: inout [[Double]], _ pcm: [Int]) {
        for x in 1...2 {
            for y in 1...2 {
                mtxOut[x][y] = 0.0
                for z in 0..<14 { mtxOut[x][y] += Double(pcm[14 + z - x] * pcm[14 + z - y]) }
            }
        }
    }

    private static func analyzeRanges(_ mtx: inout [[Double]], _ vecIdxsOut: inout [Int], _ recips: inout [Double]) -> Bool {
        var val = 0.0, tmp = 0.0
        for x in 1...2 {
            val = max(abs(mtx[x][1]), abs(mtx[x][2]))
            if val < Double.leastNonzeroMagnitude { return true }
            recips[x] = 1.0 / val
        }
        var maxIndex = 0
        for i in 1...2 {
            for x in 1..<i {
                tmp = mtx[x][i]
                for y in 1..<x { tmp -= mtx[x][y] * mtx[y][i] }
                mtx[x][i] = tmp
            }
            val = 0.0
            for x in i...2 {
                tmp = mtx[x][i]
                for y in 1..<i { tmp -= mtx[x][y] * mtx[y][i] }
                mtx[x][i] = tmp
                tmp = abs(tmp) * recips[x]
                if tmp >= val { val = tmp; maxIndex = x }
            }
            if maxIndex != i {
                for y in 1...2 {
                    tmp = mtx[maxIndex][y]
                    mtx[maxIndex][y] = mtx[i][y]
                    mtx[i][y] = tmp
                }
                recips[maxIndex] = recips[i]
            }
            vecIdxsOut[i] = maxIndex
            if i != 2 {
                tmp = 1.0 / mtx[i][i]
                for x in (i + 1)...2 { mtx[x][i] *= tmp }
            }
        }
        var minV = 1.0e10, maxV = 0.0
        for i in 1...2 {
            tmp = abs(mtx[i][i])
            if tmp < minV { minV = tmp }
            if tmp > maxV { maxV = tmp }
        }
        return minV / maxV < 1.0e-10
    }

    private static func bidirectionalFilter(_ mtx: [[Double]], _ vecIdxs: [Int], _ vecOut: inout [Double]) {
        var tmp = 0.0
        var x = 0
        for i in 1...2 {
            let index = vecIdxs[i]
            tmp = vecOut[index]
            vecOut[index] = vecOut[i]
            if x != 0 {
                for y in x...(i - 1) { tmp -= vecOut[y] * mtx[i][y] }
            } else if tmp != 0.0 {
                x = i
            }
            vecOut[i] = tmp
        }
        var i = 2
        while i > 0 {
            tmp = vecOut[i]
            if i + 1 <= 2 { for y in (i + 1)...2 { tmp -= vecOut[y] * mtx[i][y] } }
            vecOut[i] = tmp / mtx[i][i]
            i -= 1
        }
        vecOut[0] = 1.0
    }

    private static func quadraticMerge(_ v: inout [Double]) -> Bool {
        let v2 = v[2]
        let tmp = 1.0 - (v2 * v2)
        if tmp == 0.0 { return true }
        let v0 = (v[0] - (v2 * v2)) / tmp
        let v1 = (v[1] - (v[1] * v2)) / tmp
        v[0] = v0
        v[1] = v1
        return abs(v1) > 1.0
    }

    private static func finishRecord(_ inR: inout [Double], _ outR: inout [Double]) {
        for z in 1...2 {
            if inR[z] >= 1.0 { inR[z] = 0.9999999999 }
            else if inR[z] <= -1.0 { inR[z] = -0.9999999999 }
        }
        outR[0] = 1.0
        outR[1] = (inR[2] * inR[1]) + inR[1]
        outR[2] = inR[2]
    }

    private static func matrixFilter(_ src: [Double], _ dst: inout [Double], _ mtx: inout [[Double]]) {
        mtx[2][0] = 1.0
        for i in 1...2 { mtx[2][i] = -src[i] }
        var i = 2
        while i > 0 {
            let val = 1.0 - (mtx[i][i] * mtx[i][i])
            for y in 1...i { mtx[i - 1][y] = ((mtx[i][i] * mtx[i][y]) + mtx[i][y]) / val }
            i -= 1
        }
        dst[0] = 1.0
        for i in 1...2 {
            dst[i] = 0.0
            for y in 1...i { dst[i] += mtx[i][y] * dst[i - y] }
        }
    }

    private static func mergeFinishRecord(_ src: [Double], _ dst: inout [Double]) {
        var tmp = [Double](repeating: 0, count: 3)
        var val = src[0]
        dst[0] = 1.0
        for i in 1...2 {
            var v2 = 0.0
            for y in stride(from: 1, to: i, by: 1) { v2 += dst[y] * src[i - y] }
            if val > 0.0 { dst[i] = -(v2 + src[i]) / val } else { dst[i] = 0.0 }
            tmp[i] = dst[i]
            for y in stride(from: 1, to: i, by: 1) { dst[y] += dst[i] * dst[i - y] }
            val *= 1.0 - (dst[i] * dst[i])
        }
        finishRecord(&tmp, &dst)
    }

    private static func contrastVectors(_ s1: [Double], _ s2: [Double]) -> Double {
        let val = (s2[2] * s2[1] + -s2[1]) / (1.0 - s2[2] * s2[2])
        let val1 = (s1[0] * s1[0]) + (s1[1] * s1[1]) + (s1[2] * s1[2])
        let val2 = (s1[0] * s1[1]) + (s1[1] * s1[2])
        let val3 = s1[0] * s1[2]
        return val1 + (2.0 * val * val2) + (2.0 * (-s2[1] * val + -s2[2]) * val3)
    }

    private static func filterRecords(_ vecBest: inout [[Double]], _ exp: Int, _ records: [[Double]], _ recordCount: Int) {
        var bufferList = [[Double]](repeating: [0, 0, 0], count: 8)
        var mtx = [[Double]](repeating: [0, 0, 0], count: 3)
        var buffer1 = [Int](repeating: 0, count: 8)
        var buffer2 = [Double](repeating: 0, count: 3)
        for _ in 0..<2 {
            for y in 0..<exp {
                buffer1[y] = 0
                for i in 0...2 { bufferList[y][i] = 0.0 }
            }
            for z in 0..<recordCount {
                var index = 0
                var value = 1.0e30
                for i in 0..<exp {
                    let t = contrastVectors(vecBest[i], records[z])
                    if t < value { value = t; index = i }
                }
                buffer1[index] += 1
                matrixFilter(records[z], &buffer2, &mtx)
                for i in 0...2 { bufferList[index][i] += buffer2[i] }
            }
            for i in 0..<exp where buffer1[i] > 0 {
                for y in 0...2 { bufferList[i][y] /= Double(buffer1[i]) }
            }
            for i in 0..<exp { mergeFinishRecord(bufferList[i], &vecBest[i]) }
        }
    }
}
