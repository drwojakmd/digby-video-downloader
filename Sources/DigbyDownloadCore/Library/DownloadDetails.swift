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
