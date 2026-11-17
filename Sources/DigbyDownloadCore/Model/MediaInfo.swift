import Foundation

/// What an extractor learned about one piece of media. Digby's own type: nothing outside the
/// extraction layer knows yt-dlp's field names.
public struct MediaInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var webpageURL: URL
    public var title: String
    public var uploader: String?
    public var site: String
    public var duration: Double?
    public var uploadDate: Date?
    public var description: String?
    public var thumbnailURL: URL?
    public var formats: [MediaFormat]
    public var subtitles: [SubtitleTrack]
    public var chapterCount: Int
    /// The chapters' names and times, when the site gives them.
    public var chapters: [Chapter] = []
    public struct Chapter: Sendable, Hashable {
        public var title: String
        public var start: Double
        public var end: Double
        public init(title: String, start: Double, end: Double) { self.title = title; self.start = start; self.end = end }
    }
    /// Something about this result the person should know (e.g. the site sent a reduced list).
    public var notice: String? = nil
    /// When the video was caught on a page: the stream to give the engine (instead of the page), and the
    /// headers/cookies the page's player used. Not saved anywhere.
    public var engineURL: URL? = nil
    public var engineArguments: [String] = []

    public init(id: String, webpageURL: URL, title: String, uploader: String? = nil, site: String, duration: Double? = nil,
                uploadDate: Date? = nil, description: String? = nil, thumbnailURL: URL? = nil, formats: [MediaFormat],
                subtitles: [SubtitleTrack] = [], chapterCount: Int = 0) {
        self.id = id; self.webpageURL = webpageURL; self.title = title; self.uploader = uploader; self.site = site
        self.duration = duration; self.uploadDate = uploadDate; self.description = description; self.thumbnailURL = thumbnailURL
        self.formats = formats; self.subtitles = subtitles; self.chapterCount = chapterCount
    }
}

public enum DynamicRange: String, Sendable, Hashable, Codable {
    case sdr, hdr10, hlg, dolbyVision
    public var isHDR: Bool { self != .sdr }
}

/// How an audio track relates to the original recording.
public enum AudioRole: String, Sendable, Hashable, Codable {
    case original, dubbed, descriptive, unknown
}

/// One downloadable stream (or a stream with both picture and sound).
public struct MediaFormat: Sendable, Hashable, Identifiable {
    public var id: String
    public var ext: String
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    /// Raw codec strings as reported by the source ("avc1.640028", "opus"); nil = none.
    public var videoCodecName: String?
    public var audioCodecName: String?
    /// kbit/s
    public var videoBitrate: Double?
    public var audioBitrate: Double?
    public var fileSize: Int64?
    public var fileSizeIsExact: Bool
    public var language: String?
    public var audioRole: AudioRole
    public var dynamicRange: DynamicRange
    public var bitDepth: Int?
    public var audioChannels: Int?
    public var note: String?
    public var isDRM: Bool
    /// Direct stream address, used only to inspect unknown codecs. Never logged or stored.
    public var streamURL: URL?
    public var protocolName: String?
    /// Headers the site expects with the stream (User-Agent, Referer…). Never logged; cookies are not kept here.
    public var httpHeaders: [String: String] = [:]

    public init(id: String, ext: String, width: Int? = nil, height: Int? = nil, fps: Double? = nil,
                videoCodecName: String? = nil, audioCodecName: String? = nil, videoBitrate: Double? = nil,
                audioBitrate: Double? = nil, fileSize: Int64? = nil, fileSizeIsExact: Bool = true, language: String? = nil,
                audioRole: AudioRole = .unknown, dynamicRange: DynamicRange = .sdr, bitDepth: Int? = nil,
                audioChannels: Int? = nil, note: String? = nil, isDRM: Bool = false, streamURL: URL? = nil, protocolName: String? = nil) {
        self.id = id; self.ext = ext; self.width = width; self.height = height; self.fps = fps
        self.videoCodecName = videoCodecName; self.audioCodecName = audioCodecName
        self.videoBitrate = videoBitrate; self.audioBitrate = audioBitrate
        self.fileSize = fileSize; self.fileSizeIsExact = fileSizeIsExact; self.language = language; self.audioRole = audioRole
        self.dynamicRange = dynamicRange; self.bitDepth = bitDepth; self.audioChannels = audioChannels; self.note = note; self.isDRM = isDRM
        self.streamURL = streamURL; self.protocolName = protocolName
    }
    /// The site didn't say which codec; Digby inspects the stream to find out.
    public var hasUnknownCodec: Bool { videoCodecName == "unknown" || audioCodecName == "unknown" }

    public var hasVideo: Bool { videoCodecName != nil && (width ?? 0) > 0 && (height ?? 0) > 0 }
    public var hasAudio: Bool { audioCodecName != nil }
    public var videoCodec: VideoCodec? { videoCodecName.map(VideoCodec.init(raw:)) }
    public var audioCodec: AudioCodec? { audioCodecName.map(AudioCodec.init(raw:)) }
    public var tier: ResolutionTier? {
        guard let w = width, let h = height, hasVideo else { return nil }
        return ResolutionTier(width: w, height: h)
    }
    public var totalBitrate: Double? {
        switch (videoBitrate, audioBitrate) {
        case let (v?, a?): return v + a
        case let (v?, nil): return v
        case let (nil, a?): return a
        default: return nil
        }
    }
}

public struct SubtitleTrack: Sendable, Hashable, Identifiable {
    public var language: String
    public var name: String?
    /// Generated by the site's speech recognition rather than written by a person.
    public var isAutomatic: Bool
    public var formats: [String]
    /// The engine's own key for this track (e.g. "en-orig").
    public var key: String
    public var id: String { "\(language)-\(isAutomatic ? "auto" : "human")" }
    public init(language: String, name: String? = nil, isAutomatic: Bool, formats: [String] = ["vtt"], key: String? = nil) {
        self.language = language; self.name = name; self.isAutomatic = isAutomatic; self.formats = formats; self.key = key ?? language
    }
}

/// A playlist, channel or other collection.
public struct MediaCollection: Sendable, Hashable, Identifiable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var url: URL
        public var duration: Double?
        public var thumbnail: URL?
        public init(id: String, title: String, url: URL, duration: Double? = nil, thumbnail: URL? = nil) {
            self.id = id; self.title = title; self.url = url; self.duration = duration; self.thumbnail = thumbnail
        }
    }
    public var id: String
    public var title: String
    public var uploader: String?
    public var site: String
    public var entries: [Entry]
    public var totalDuration: Double? {
        let d = entries.compactMap(\.duration)
        return d.count == entries.count && !d.isEmpty ? d.reduce(0, +) : nil
    }
    public init(id: String, title: String, uploader: String? = nil, site: String, entries: [Entry]) {
        self.id = id; self.title = title; self.uploader = uploader; self.site = site; self.entries = entries
    }
}

/// Human-readable language names, in English, from BCP-47 codes ("en-US" → "English (US)").
public enum Languages {
    public static func name(_ code: String) -> String {
        let loc = Locale(identifier: "en")
        let parts = code.split(separator: "-")
        let base = loc.localizedString(forLanguageCode: String(parts.first ?? "")) ?? code
        if parts.count > 1, parts[1].count == 2 { return "\(base) (\(parts[1].uppercased()))" }
        return base
    }
    public static func base(_ code: String) -> String { String(code.lowercased().split(separator: "-").first ?? "") }
}
