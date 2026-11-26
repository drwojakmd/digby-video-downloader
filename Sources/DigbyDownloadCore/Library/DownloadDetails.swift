import Foundation

/// Everything worth remembering about one download: the original as the site offered it, what was
/// chosen, and what was verified. Saved with the History entry, so it survives restarts.
public struct DownloadDetails: Codable, Sendable, Hashable, Identifiable {
    public var id: String { pageURL.absoluteString + (completedAt?.timeIntervalSince1970.description ?? "") }

    // The original
    public var title: String
    public var uploader: String?
    public var site: String
    public var pageURL: URL
    public var duration: Double?
    public var uploadDate: Date?
    public var description: String?
    public var thumbnail: URL?
    public var offered: [Offer]                 // highest resolution first
    public var soundLanguages: [String]         // "English (original)", "Spanish (dubbed)"
    public var subtitles: [String]              // "English", "French (automatic)"
    public var chapters: Int
    public var formatCount: Int

    public struct Offer: Codable, Sendable, Hashable, Identifiable {
        public var resolution: String           // "1080p"
        public var formats: [String]            // ["H.264", "VP9", "AV1"]
        public var hdr: Bool
        public var frameRate: Double?
        public var id: String { resolution }
    }

    // What was chosen
    public var choices: [Choice]                // labelled rows, in plain English
    public var chips: [String]                  // "1080p 60", "H.264", "AAC · English (original)", "MP4"
    public var streams: String                  // the engine's stream ids, e.g. "299+258"
    public var expectedBytes: Int64?
    public var expectedExact: Bool
    public var notes: [String]
    public var converted: Bool

    public struct Choice: Codable, Sendable, Hashable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
    }

    // What was verified
    public var verified: String?                // "1920×1080 · H.264 · AAC · 10:35"
    public var file: URL?
    public var bytes: Int64?
    public var completedAt: Date?
    /// Made smaller by Digby Video Compressor afterwards (nil: never sent there). Older saved details lack it.
    public var compression: CompressionRecord? = nil

    public static func make(catalogue c: FormatCatalogue, choices ch: Choices, plan p: DownloadPlan) -> DownloadDetails {
        let m = c.media
        let offered = c.tiers.map { t in
            Offer(resolution: t.name, formats: c.codecs(at: t).map(\.name), hdr: c.hasHDR(at: t),
                  frameRate: c.streams(at: t).compactMap(\.fps).max())
        }
        let langs = c.languages.map { $0.name + ($0.isOriginal ? " (original)" : $0.isDubbed ? " (dubbed)" : "") }
        let subs = c.humanSubtitles.map { Languages.name($0.language) } + c.automaticSubtitles.map { Languages.name($0.language) + " (automatic)" }
        var rows: [Choice] = [Choice(label: "Download", value: ch.kind.label)]
        if ch.kind != .audioOnly {
            let res: String = { if case .tier(let t) = ch.resolution { return t.name }; return "Best (\(p.video?.tier?.name ?? "highest"))" }()
            rows.append(Choice(label: "Resolution", value: res))
            let codec: String = { if case .specific(let v) = ch.codec { return v.name }; return "Automatic (\(p.video?.videoCodec?.name ?? "best"))" }()
            rows.append(Choice(label: "Video format", value: codec))
            if c.hasHDR { rows.append(Choice(label: "Brightness range", value: ch.preferHDR ? "HDR" : "Standard (SDR)")) }
            rows.append(Choice(label: "File type", value: ch.container.name))
        } else {
            rows.append(Choice(label: "Audio file", value: ch.audioOutput == .original ? "As it is" : ch.audioOutput.name))
        }
        if c.languages.count > 1 {
            let l: String = { if case .language(let code) = ch.language { return Languages.name(code) }; return "Original" }()
            rows.append(Choice(label: "Sound language", value: l))
        }
        if ch.subtitles.mode != .none {
            rows.append(Choice(label: "Subtitles", value: ch.subtitles.mode.label + ": " + (p.subtitles.isEmpty ? "none available"
                : p.subtitles.map { Languages.name($0.language) + ($0.isAutomatic ? " (automatic)" : "") }.joined(separator: ", "))))
        }
        if let to = p.translateTo { rows.append(Choice(label: "Translated into", value: Languages.name(to) + " (on this Mac)")) }
        if let clip = p.clip { rows.append(Choice(label: "Part", value: clip.label + (clip.exact ? ", exact cut" : ", quick cut"))) }
        if ch.manualVideoID != nil || ch.manualAudioID != nil { rows.append(Choice(label: "Streams", value: "Picked by hand")) }
        return DownloadDetails(title: m.title, uploader: m.uploader, site: m.site, pageURL: m.webpageURL, duration: m.duration,
                               uploadDate: m.uploadDate, description: m.description.map { String($0.prefix(600)) }, thumbnail: m.thumbnailURL,
                               offered: offered, soundLanguages: langs, subtitles: subs, chapters: m.chapterCount, formatCount: m.formats.count,
                               choices: rows, chips: p.chips(catalogue: c), streams: p.formatExpression, expectedBytes: p.size?.bytes,
                               expectedExact: p.size?.isExact ?? false, notes: p.notes, converted: p.convertsAnything,
                               verified: nil, file: nil, bytes: nil, completedAt: nil)
    }

    public mutating func finish(_ o: DownloadOutcome) {
        verified = o.report.summary; file = o.file; bytes = o.bytes; completedAt = Date()
    }
}

/// What Digby Video Compressor did with a download sent to it, as it reported back.
public struct CompressionRecord: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable { case sent, compressing, done, skipped, failed, cancelled }
    public var state: State
    public var setting: String                // "Balanced", "Fit 25 MB", "Compressor’s settings"
    public var originalFile: URL              // the download as it was
    public var output: URL?                   // the smaller file
    public var originalBytes: Int64?
    public var outputBytes: Int64?
    public var format: String?                // "HEVC · 1920×1080"
    public var quality: String?               // "Excellent"
    public var vmaf: Double?
    public var originalTrashed: Bool
    public var note: String?
    public var date: Date

    public init(state: State, setting: String, originalFile: URL, output: URL? = nil, originalBytes: Int64? = nil, outputBytes: Int64? = nil,
                format: String? = nil, quality: String? = nil, vmaf: Double? = nil, originalTrashed: Bool = false, note: String? = nil, date: Date = Date()) {
        self.state = state; self.setting = setting; self.originalFile = originalFile; self.output = output
        self.originalBytes = originalBytes; self.outputBytes = outputBytes; self.format = format; self.quality = quality
        self.vmaf = vmaf; self.originalTrashed = originalTrashed; self.note = note; self.date = date
    }

    /// Bytes saved (done only).
    public var savedBytes: Int64? {
        guard state == .done, let o = originalBytes, let n = outputBytes else { return nil }
        return max(0, o - n)
    }
    /// 0.62 for "62 % smaller".
    public var reduction: Double? {
        guard let s = savedBytes, let o = originalBytes, o > 0 else { return nil }
        return Double(s) / Double(o)
    }
    /// Short status for a list row: "Compressed −62 %", "Compressing…".
    public var chip: String {
        switch state {
        case .sent: return "Waiting for Compressor"
        case .compressing: return "Compressing…"
        case .done: return reduction.map { "Compressed −\(Int(($0 * 100).rounded())) %" } ?? "Compressed"
        case .skipped: return "Kept as downloaded"
        case .failed: return "Compression failed"
        case .cancelled: return "Compression cancelled"
        }
    }
    public var isFinal: Bool { ![.sent, .compressing].contains(state) }
}
