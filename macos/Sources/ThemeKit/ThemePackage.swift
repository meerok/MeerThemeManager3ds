import Foundation
import Network

/// The full set of files that make up a distributable theme:
/// body_LZ.bin, info.smdh, preview.png and (optionally) bgm.bcstm.
public struct ThemePackage {
    public var theme: Theme
    public var info: SMDH
    public var bgm: [UInt8]?
    public var preview: Data?

    public init(theme: Theme = Theme(), info: SMDH = SMDH(), bgm: [UInt8]? = nil, preview: Data? = nil) {
        self.theme = theme
        self.info = info
        self.bgm = bgm
        self.preview = preview
    }

    // MARK: Loading

    /// Opens a theme folder, a theme .zip, or a single body_LZ.bin.
    public static func load(url: URL) throws -> ThemePackage {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return try loadFolder(url) }
        let bytes = [UInt8](try Data(contentsOf: url))
        if url.pathExtension.lowercased() == "zip" || (bytes.count > 4 && bytes.readU32LE(0) == 0x04034B50) {
            return try loadZip(bytes)
        }
        var pkg = ThemePackage(theme: try Theme.read(body: bytes))
        let dir = url.deletingLastPathComponent()
        pkg.mergeSiblings(in: dir)
        return pkg
    }

    static func findFile(_ names: [String], in dir: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let lower = names.map { $0.lowercased() }
        return items.first { lower.contains($0.lastPathComponent.lowercased()) }
    }

    static func loadFolder(_ dir: URL) throws -> ThemePackage {
        guard let body = findFile(["body_LZ.bin", "body_lz.bin"], in: dir) else {
            throw ThemeKitError.invalidFormat("This folder doesn't contain a body_LZ.bin file.")
        }
        var pkg = ThemePackage(theme: try Theme.read(body: [UInt8](try Data(contentsOf: body))))
        pkg.mergeSiblings(in: dir)
        return pkg
    }

    mutating func mergeSiblings(in dir: URL) {
        if let u = Self.findFile(["info.smdh"], in: dir), let d = try? Data(contentsOf: u), let s = try? SMDH.read([UInt8](d)) {
            info = s
        }
        if let u = Self.findFile(["bgm.bcstm"], in: dir), let d = try? Data(contentsOf: u) {
            bgm = [UInt8](d)
        }
        if let u = Self.findFile(["preview.png"], in: dir) { preview = try? Data(contentsOf: u) }
    }

    static func loadZip(_ bytes: [UInt8]) throws -> ThemePackage {
        let entries = try Zip.read(bytes)
        func entry(_ name: String) -> Zip.Entry? {
            entries.first { ($0.name as NSString).lastPathComponent.lowercased() == name.lowercased() && !$0.name.contains("__MACOSX") }
        }
        guard let body = entry("body_LZ.bin") else {
            throw ThemeKitError.invalidFormat("This ZIP doesn't contain a body_LZ.bin file.")
        }
        var pkg = ThemePackage(theme: try Theme.read(body: body.data))
        if let s = entry("info.smdh"), let info = try? SMDH.read(s.data) { pkg.info = info }
        if let b = entry("bgm.bcstm") { pkg.bgm = b.data }
        if let p = entry("preview.png") { pkg.preview = Data(p.data) }
        return pkg
    }

    // MARK: Saving

    public struct Validation {
        public var errors: [String] = []
        public var warnings: [String] = []
        public var compressedBodySize = 0
        public var bgmSize = 0
    }

    /// Files in the order theme managers expect.
    public func files(compressedBody: [UInt8]? = nil) -> [(String, [UInt8])] {
        var list: [(String, [UInt8])] = []
        list.append(("body_LZ.bin", compressedBody ?? theme.writeCompressedBody()))
        list.append(("info.smdh", info.write()))
        if let preview { list.append(("preview.png", [UInt8](preview))) }
        if theme.flags.backgroundMusic, let bgm { list.append(("bgm.bcstm", bgm)) }
        return list
    }

    public func validate(compressedBody: [UInt8]) -> Validation {
        var v = Validation()
        v.compressedBodySize = compressedBody.count
        if compressedBody.count > ThemeLimits.maxCompressedBody {
            v.errors.append("body_LZ.bin is \(compressedBody.count.formatted()) bytes; the limit is \(ThemeLimits.maxCompressedBody.formatted()). Use smaller/simpler images or fewer sound effects.")
        }
        if theme.flags.backgroundMusic {
            if let bgm {
                v.bgmSize = bgm.count
                if bgm.count > ThemeLimits.maxBGM {
                    v.errors.append("bgm.bcstm is \(bgm.count.formatted()) bytes; the limit is \(ThemeLimits.maxBGM.formatted()). Shorten the song or use mono / a lower sample rate.")
                }
            } else {
                v.warnings.append("Background music is turned on but no music has been added. It will be exported without BGM.")
            }
        }
        if theme.flags.soundEffects && theme.soundEffectData.count > ThemeLimits.maxSoundEffects {
            v.errors.append("Sound effects are too large (\(theme.soundEffectData.count.formatted()) bytes, limit \(ThemeLimits.maxSoundEffects.formatted())).")
        }
        if info.primaryTitle.shortDescription.isEmpty {
            v.warnings.append("The theme has no name. ThemePlaza and theme managers display the name from info.smdh.")
        }
        if preview == nil { v.warnings.append("No preview.png will be included.") }
        return v
    }

    /// A filesystem-safe name based on the theme title.
    public var safeName: String {
        let raw = info.primaryTitle.shortDescription.trimmingCharacters(in: .whitespaces)
        let base = raw.isEmpty ? "My 3DS Theme" : raw
        let allowed = base.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || " -_()".unicodeScalars.contains($0) ? Character($0) : "_" }
        return String(allowed).trimmingCharacters(in: .whitespaces)
    }

    /// Writes the theme as a folder (Anemone3DS / ThemePlaza layout).
    public func writeFolder(to dir: URL, compressedBody: [UInt8]? = nil) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files(compressedBody: compressedBody) {
            try Data(data).write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        // Remove a stale bgm when music is off.
        if !theme.flags.backgroundMusic {
            let stale = dir.appendingPathComponent("bgm.bcstm")
            if FileManager.default.fileExists(atPath: stale.path) { try? FileManager.default.removeItem(at: stale) }
        }
    }

    /// Writes a .zip with the files at the root (the format ThemePlaza and Anemone3DS accept).
    public func zipData(compressedBody: [UInt8]? = nil, inFolder folder: String? = nil) -> [UInt8] {
        let prefix = folder.map { $0 + "/" } ?? ""
        return Zip.write(files(compressedBody: compressedBody).map { Zip.Entry(name: prefix + $0.0, data: $0.1) })
    }
}

// MARK: - Color/flag presets

/// Portable preset of a theme's colors and flags (JSON), similar to Usagi's metadata export.
public struct ThemePreset: Codable {
    public var formatVersion = 1
    public var flags: ThemeFlags
    public var colors: ThemeColors
    public init(flags: ThemeFlags, colors: ThemeColors) { self.flags = flags; self.colors = colors }

    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func load(_ data: Data) throws -> ThemePreset {
        try JSONDecoder().decode(ThemePreset.self, from: data)
    }
}

// MARK: - CHMM2 network sender

/// Thread-safe "only once" flag.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Sends a theme ZIP to CHMM2 ("YATA SENDER" protocol, TCP port 5000).
public final class ThemeSender {
    public enum SendError: LocalizedError {
        case badAddress, timeout, handshake, connection(String)
        public var errorDescription: String? {
            switch self {
            case .badAddress: return "Enter your 3DS's IP address (for example 192.168.1.42)."
            case .timeout: return "Couldn't reach the 3DS. Make sure CHMM2 is open and waiting to receive, and that your Mac and 3DS are on the same Wi-Fi."
            case .handshake: return "The 3DS answered, but not with the CHMM2 receiver handshake."
            case .connection(let s): return s
            }
        }
    }

    public init() {}

    public func send(zip: [UInt8], to ip: String, progress: @escaping (Double) -> Void) async throws {
        guard IPv4Address(ip) != nil else { throw SendError.badAddress }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: 5000, using: .tcp)
        defer { conn.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            let finish: @Sendable (Result<Void, Error>) -> Void = { r in
                if once.claim() { cont.resume(with: r) }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let e): finish(.failure(SendError.connection(e.localizedDescription)))
                case .waiting: break
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) { finish(.failure(SendError.timeout)) }
        }
        let hello = try await receive(conn, 11)
        guard String(decoding: hello, as: UTF8.self) == "YATA SENDER" else { throw SendError.handshake }
        var offset = 0
        while offset < zip.count {
            let end = min(offset + 8192, zip.count)
            try await sendChunk(conn, Data(zip[offset..<end]))
            offset = end
            progress(Double(offset) / Double(zip.count))
        }
        let bye = try await receive(conn, 9)
        guard String(decoding: bye, as: UTF8.self) == "YATA TERM" else { throw SendError.handshake }
    }

    private func receive(_ c: NWConnection, _ n: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            c.receive(minimumIncompleteLength: n, maximumLength: n) { data, _, _, error in
                if let error { cont.resume(throwing: SendError.connection(error.localizedDescription)); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func sendChunk(_ c: NWConnection, _ d: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: d, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: SendError.connection(error.localizedDescription)) }
                else { cont.resume() }
            })
        }
    }
}
