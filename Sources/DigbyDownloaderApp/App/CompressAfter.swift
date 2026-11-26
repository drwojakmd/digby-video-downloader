import Foundation
import DigbyDownloadCore

/// "After downloading, compress it with Digby Video Compressor": remembered in Settings, copied onto
/// each download when it starts (so changing it later never alters downloads already waiting).
struct CompressAfter: Codable, Equatable {
    enum Size: String, Codable, CaseIterable, Identifiable {
        case light, balanced, small, smallest, fitSize, compressorSettings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light: "Light"
            case .balanced: "Balanced"
            case .small: "Small"
            case .smallest: "Smallest"
            case .fitSize: "Fit a Size"
            case .compressorSettings: "Compressor’s Settings"
            }
        }
        /// Plain English, one line each (the Compressor's own quality levels underneath).
        var blurb: String {
            switch self {
            case .light: "High quality: differences only show frame by frame. Smaller, not tiny."
            case .balanced: "Much smaller and still looks very good. Recommended."
            case .small: "A small file. Fine detail softens in busy scenes."
            case .smallest: "The smallest file. Some visible loss is likely: fine when you only need the content."
            case .fitSize: "Aims for the size you choose, such as under 25 MB for email. Quality follows from it."
            case .compressorSettings: "Uses whatever Digby Video Compressor is set to, including its resolution and format choices."
            }
        }
        /// Digby Video Compressor's QualityLevel raw value (0 Maximum Quality … 4 Maximum Compression).
        var compressorQuality: Int? {
            switch self {
            case .light: 1
            case .balanced: 2
            case .small: 3
            case .smallest: 4
            case .fitSize, .compressorSettings: nil
            }
        }

        /// A rough range for the compressed file, as a share of the download. Sites already compress their
        /// video, so how much more comes off depends mostly on how efficient their format is: older H.264
        /// shrinks most, VP9 and HEVC less, AV1 least. Real results vary with the content (talking heads
        /// shrink far more than confetti), so this is a guide; the Compressor measures the real size once it
        /// has the file, and keeps the original when it can't save much.
        /// nil for "Fit a Size" and "Compressor's Settings", which this can't predict.
        func estimate(downloadBytes: Int64, codec: VideoCodec?) -> ClosedRange<Int64>? {
            guard downloadBytes > 0, let level = compressorQuality else { return nil }
            // [low, high] share of the download, per level (1 Light … 4 Smallest).
            let shares: [Int: (Double, Double)]
            switch codec {
            case .av1?:
                shares = [1: (0.80, 1.0), 2: (0.60, 0.90), 3: (0.45, 0.70), 4: (0.30, 0.50)]
            case .vp9?, .hevc?:
                shares = [1: (0.70, 0.95), 2: (0.50, 0.80), 3: (0.35, 0.60), 4: (0.20, 0.40)]
            default:    // H.264 and anything unknown
                shares = [1: (0.55, 0.80), 2: (0.35, 0.60), 3: (0.25, 0.45), 4: (0.15, 0.30)]
            }
            guard let (lo, hi) = shares[level] else { return nil }
            let b = Double(downloadBytes)
            return Int64(b * lo)...Int64(b * hi)
        }
    }

    /// "≈ 150–250 MB", rounded so it doesn't look more exact than it is.
    static func rangeLabel(_ r: ClosedRange<Int64>) -> String {
        let gb = r.upperBound >= 1_000_000_000
        let unit = gb ? 1e9 : 1e6
        func f(_ b: Int64) -> String {
            let v = Double(b) / unit
            if v >= 100 { return String(Int((v / 10).rounded() * 10)) }
            if v >= 10 { return String(Int(v.rounded())) }
            return String(format: "%.1f", v)
        }
        return "≈ \(f(r.lowerBound))–\(f(r.upperBound)) \(gb ? "GB" : "MB")"
    }

    var on = false
    var size: Size = .balanced
    /// For "Fit a Size".
    var targetMB: Int = 100
    /// Keep the big download as well. Off: it goes to the Trash once the smaller copy is made and checked.
    var keepOriginal = false

    var summary: String {
        let s = size == .fitSize ? "about \(targetMB) MB" : size.label.lowercased()
        return "Compress (\(s))" + (keepOriginal ? ", keep the original" : ", original to the Trash")
    }
}

/// The note Digby Video Compressor reads when it opens a file from here (see its Handoff.swift).
/// Kept in the Compressor's private Application Support folder, which web pages can't write to.
struct CompressHandoff: Codable {
    var file: String
    var quality: Int?
    var targetBytes: Int64?
    var replaceOriginal: Bool
    var created: Date

    static var folder: URL {
        ProcessInfo.processInfo.environment["DIGBY_HANDOFF_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Digby Video Compressor").appendingPathComponent("Handoff")
    }

    init(file: URL, using c: CompressAfter, now: Date = Date()) {
        self.file = file.standardizedFileURL.path
        quality = c.size.compressorQuality
        targetBytes = c.size == .fitSize ? Int64(max(1, c.targetMB)) * 1_000_000 : nil
        replaceOriginal = !c.keepOriginal
        created = now
    }

    /// Writes the note; returns false if it couldn't (the file then just opens, as before).
    @discardableResult
    func write() -> Bool {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try enc.encode(self).write(to: Self.folder.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
            return true
        } catch { return false }
    }
}

/// The Compressor's report on a video sent from here (its `HandoffResult`), read from `Handoff/Results`.
struct CompressResultNote: Codable {
    var file: String
    var state: String
    var setting: String
    var output: String?
    var originalBytes: Int64?
    var outputBytes: Int64?
    var format: String?
    var quality: String?
    var vmaf: Double?
    var originalTrashed: Bool?
    var note: String?
    var date: Date?

    static var folder: URL { CompressHandoff.folder.appendingPathComponent("Results", isDirectory: true) }

    /// Every note waiting, with where it is (to delete it once used).
    static func readAll() -> [(url: URL, note: CompressResultNote)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return urls.filter { $0.pathExtension == "json" }.compactMap { u in
            guard let d = try? Data(contentsOf: u), let n = try? dec.decode(CompressResultNote.self, from: d) else { return nil }
            return (u, n)
        }
    }

    var record: CompressionRecord {
        CompressionRecord(state: CompressionRecord.State(rawValue: state) ?? .failed, setting: setting,
                          originalFile: URL(fileURLWithPath: file), output: output.map { URL(fileURLWithPath: $0) },
                          originalBytes: originalBytes, outputBytes: outputBytes, format: format, quality: quality, vmaf: vmaf,
                          originalTrashed: originalTrashed ?? false, note: note, date: date ?? Date())
    }
}

extension CompressAfter {
    /// The setting as this app names it ("Balanced", "Fit 25 MB"), kept in Downloaded.
    var settingLabel: String { size == .fitSize ? "Fit \(max(1, targetMB)) MB" : size.label }
}
