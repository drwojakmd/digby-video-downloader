import Foundation

/// Video formats grouped the way people choose them, not the way sites list them.
public enum VideoCodec: String, CaseIterable, Sendable, Hashable, Codable {
    case avc, hevc, av1, vp9, other

    public init(raw: String) {
        let s = raw.lowercased()
        if s.hasPrefix("avc") || s.hasPrefix("h264") || s == "h.264" { self = .avc }
        else if s.hasPrefix("hvc") || s.hasPrefix("hev") || s.hasPrefix("h265") || s == "hevc" { self = .hevc }
        else if s.hasPrefix("av01") || s == "av1" { self = .av1 }
        else if s.hasPrefix("vp09") || s.hasPrefix("vp9") { self = .vp9 }
        else { self = .other }
    }

    /// Technical name.
    public var name: String {
        switch self { case .avc: "H.264"; case .hevc: "HEVC"; case .av1: "AV1"; case .vp9: "VP9"; case .other: "Other" }
    }
    /// Plain-English label used on the pill.
    public var plainLabel: String {
        switch self {
        case .avc: "Plays everywhere"; case .hevc: "Smaller · Apple"; case .av1: "Smallest · newest"
        case .vp9: "Web format"; case .other: "Other"
        }
    }
    /// Relative bitrate needed for the same picture (H.264 = 1). Used only to rank streams of the
    /// same resolution; real files vary.
    public var efficiency: Double {
        switch self { case .avc: 1.0; case .vp9: 0.65; case .hevc: 0.6; case .av1: 0.5; case .other: 1.2 }
    }
}

public enum AudioCodec: String, CaseIterable, Sendable, Hashable, Codable {
    case aac, opus, vorbis, mp3, flac, ac3, eac3, other

    public init(raw: String) {
        let s = raw.lowercased()
        if s.hasPrefix("mp4a") || s == "aac" { self = .aac }
        else if s == "opus" { self = .opus }
        else if s == "vorbis" { self = .vorbis }
        else if s == "mp3" || s == "mp4a.40.34" { self = .mp3 }
        else if s == "flac" { self = .flac }
        else if s == "ac-3" || s == "ac3" { self = .ac3 }
        else if s == "ec-3" || s == "eac3" { self = .eac3 }
        else { self = .other }
    }
    public var name: String {
        switch self {
        case .aac: "AAC"; case .opus: "Opus"; case .vorbis: "Vorbis"; case .mp3: "MP3"; case .flac: "FLAC"
        case .ac3: "Dolby Digital"; case .eac3: "Dolby Digital Plus"; case .other: "Other"
        }
    }
    public var isLossless: Bool { self == .flac }
}

/// Resolution tiers. A video's tier comes from the width it would have at 16:9, so a
/// 1920 × 800 film is "1080p" (as people expect), and portrait video uses its short side.
public enum ResolutionTier: Int, CaseIterable, Sendable, Hashable, Codable, Comparable {
    case p144 = 144, p240 = 240, p360 = 360, p480 = 480, p720 = 720, p1080 = 1080, p1440 = 1440, p2160 = 2160, p4320 = 4320

    public init(width: Int, height: Int) {
        let short = Double(min(width, height)), long = Double(max(width, height))
        let equivalent = max(short, long * 9 / 16)
        self = ResolutionTier.allCases.reversed().first { equivalent >= Double($0.rawValue) * 0.92 } ?? .p144
    }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self { case .p4320: "8K"; case .p2160: "4K"; default: "\(rawValue)p" }
    }
    /// Plain-English label.
    public var plainLabel: String {
        switch self {
        case .p4320: "8K"; case .p2160: "4K Ultra HD"; case .p1440: "Quad HD"; case .p1080: "Full HD"; case .p720: "HD"
        case .p480: "Standard"; case .p360: "Low"; case .p240: "Very low"; case .p144: "Tiny"
        }
    }
}

/// Output files. Knows which streams each can hold without converting them.
public enum Container: String, CaseIterable, Sendable, Hashable, Codable {
    case mp4, mkv, webm, mov

    public var name: String { self == .webm ? "WebM" : rawValue.uppercased() }
    public var plainLabel: String {
        switch self { case .mp4: "Works everywhere"; case .mkv: "Keeps everything"; case .webm: "Web"; case .mov: "Apple & editing" }
    }
    public func holds(_ v: VideoCodec) -> Bool {
        switch self {
        case .mkv: true
        // VP9 can technically go in MP4, but few MP4 players handle it, which breaks MP4's promise.
        case .mp4: [.avc, .hevc, .av1].contains(v)
        case .mov: [.avc, .hevc].contains(v)
        case .webm: [.vp9, .av1].contains(v)
        }
    }
    /// Audio this container holds in a way that common players (QuickTime, browsers, TVs) play.
    public func holds(_ a: AudioCodec) -> Bool {
        switch self {
        case .mkv: true
        case .mp4: [.aac, .mp3, .ac3, .eac3].contains(a)
        case .mov: [.aac, .ac3, .eac3].contains(a)
        case .webm: [.opus, .vorbis].contains(a)
        }
    }
    /// The audio codec Digby converts to when the source's audio doesn't fit.
    public var fallbackAudio: AudioCodec { self == .webm ? .opus : .aac }
    /// Subtitles can be embedded (MP4/MOV use the mov_text format, WebM needs WebVTT).
    public var embedsSubtitles: Bool { true }
}

/// What the Mac running Digby can play natively (QuickTime, Finder preview, Photos).
public struct PlaybackEnvironment: Sendable, Hashable {
    public var decodesAV1: Bool
    public init(decodesAV1: Bool) { self.decodesAV1 = decodesAV1 }
    public func playsInQuickTime(_ v: VideoCodec, in c: Container) -> Bool {
        guard c == .mp4 || c == .mov else { return false }
        switch v { case .avc, .hevc: return true; case .av1: return decodesAV1; default: return false }
    }
}
