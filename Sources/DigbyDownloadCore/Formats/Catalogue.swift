import Foundation

/// An audio language the source actually offers.
public struct AudioLanguage: Sendable, Hashable, Identifiable {
    public var code: String          // base code, e.g. "en"
    public var isOriginal: Bool
    public var isDubbed: Bool
    public var id: String { code }
    public var name: String { Languages.name(code) }
}

/// Everything a source offers, regrouped into the categories people choose by.
/// Built once per analysis; changing choices never re-analyses.
public struct FormatCatalogue: Sendable, Hashable {
    public var media: MediaInfo
    public var video: [MediaFormat]          // streams with picture (video-only or muxed)
    public var audio: [MediaFormat]          // audio-only streams
    public var excludedDRM: Int
    public var tiers: [ResolutionTier]       // highest first
    public var languages: [AudioLanguage]    // original first
    public var humanSubtitles: [SubtitleTrack]
    public var automaticSubtitles: [SubtitleTrack]

    public init(_ media: MediaInfo) {
        self.media = media
        let usable = media.formats.filter { !$0.isDRM && !["mhtml", "jpg", "png", "webp"].contains($0.ext) }
        excludedDRM = media.formats.filter(\.isDRM).count
        video = usable.filter(\.hasVideo)
        audio = usable.filter { $0.hasAudio && !$0.hasVideo }
        tiers = Array(Set(video.compactMap(\.tier))).sorted(by: >)

        var langs: [String: AudioLanguage] = [:]
        for f in audio + video.filter(\.hasAudio) {
            guard let raw = f.language, !raw.isEmpty, raw != "und" else { continue }
            let code = Languages.base(raw)
            var l = langs[code] ?? AudioLanguage(code: code, isOriginal: false, isDubbed: false)
            if f.audioRole == .original { l.isOriginal = true }
            if f.audioRole == .dubbed { l.isDubbed = true }
            langs[code] = l
        }
        // A single language with no role information is the original by definition.
        if langs.count == 1, var only = langs.values.first, !only.isDubbed { only.isOriginal = true; langs[only.code] = only }
        languages = langs.values.sorted { ($0.isOriginal ? 0 : 1, $0.name) < ($1.isOriginal ? 0 : 1, $1.name) }

        humanSubtitles = media.subtitles.filter { !$0.isAutomatic }.sorted { Languages.name($0.language) < Languages.name($1.language) }
        automaticSubtitles = media.subtitles.filter(\.isAutomatic).sorted { Languages.name($0.language) < Languages.name($1.language) }
    }

    public var originalLanguage: AudioLanguage? { languages.first(where: \.isOriginal) }
    public var hasMultipleLanguages: Bool { languages.count > 1 }
    public var hasHDR: Bool { video.contains { $0.dynamicRange.isHDR } }
    public var highestFrameRate: Double? { video.compactMap(\.fps).max() }

    public func codecs(at tier: ResolutionTier?) -> [VideoCodec] {
        let pool = tier.map { t in video.filter { $0.tier == t } } ?? video
        let set = Set(pool.compactMap(\.videoCodec))
        return VideoCodec.allCases.filter { set.contains($0) }
    }
    public func streams(at tier: ResolutionTier) -> [MediaFormat] { video.filter { $0.tier == tier } }
    public func hasHDR(at tier: ResolutionTier) -> Bool { streams(at: tier).contains { $0.dynamicRange.isHDR } }
}
