import Foundation

/// Fictional, realistic sample data for design work and tests. Shaped like a typical large video site's
/// offer: separate picture and sound streams, four codecs, HDR at 4K, several dubbed sound tracks,
/// human and automatic subtitles. Not real media.
public enum SampleMedia {
    static let duration = 754.0   // 12:34

    static func v(_ id: String, _ ext: String, _ w: Int, _ h: Int, _ codec: String, _ kbps: Double, fps: Double = 30,
                  hdr: DynamicRange = .sdr, exact: Bool = true) -> MediaFormat {
        MediaFormat(id: id, ext: ext, width: w, height: h, fps: fps, videoCodecName: codec, videoBitrate: kbps,
                    fileSize: Int64(kbps * 1000 / 8 * duration), fileSizeIsExact: exact, dynamicRange: hdr, bitDepth: hdr.isHDR ? 10 : 8)
    }
    static func a(_ id: String, _ ext: String, _ codec: String, _ kbps: Double, _ lang: String, _ role: AudioRole) -> MediaFormat {
        MediaFormat(id: id, ext: ext, audioCodecName: codec, audioBitrate: kbps, fileSize: Int64(kbps * 1000 / 8 * duration),
                    language: lang, audioRole: role, audioChannels: 2)
    }

    public static let video: MediaInfo = {
        var m = MediaInfo(
        id: "sample-aurora",
        webpageURL: URL(string: "https://www.youtube.com/watch?v=sample-aurora")!,
        title: "Above the Clouds — A Year of Light Over the Northern Fjords",
        uploader: "Highland Skies Studio",
        site: "YouTube",
        duration: duration,
        description: "Twelve months of time-lapse photography above the cloud layer: sunrise inversions, noctilucent clouds and the aurora, filmed from three mountain huts.",
        formats: [
            v("401", "mp4", 3840, 2160, "av01.0.12M.08", 11800, fps: 60),
            v("701", "mp4", 3840, 2160, "av01.0.13M.10.0.110.09.16.09.0", 14500, fps: 60, hdr: .hdr10),
            v("315", "webm", 3840, 2160, "vp9", 17600, fps: 60),
            v("400", "mp4", 2560, 1440, "av01.0.12M.08", 6200, fps: 60),
            v("308", "webm", 2560, 1440, "vp9", 9100, fps: 60),
            v("299", "mp4", 1920, 1080, "avc1.64002a", 6100, fps: 60),
            v("303", "webm", 1920, 1080, "vp9", 3900, fps: 60),
            v("399", "mp4", 1920, 1080, "av01.0.09M.08", 2900, fps: 60),
            v("137", "mp4", 1920, 1080, "avc1.640028", 4300),
            v("298", "mp4", 1280, 720, "avc1.4d4020", 3300, fps: 60),
            v("302", "webm", 1280, 720, "vp9", 2200, fps: 60),
            v("398", "mp4", 1280, 720, "av01.0.08M.08", 1600, fps: 60),
            v("135", "mp4", 854, 480, "avc1.4d401f", 1100, exact: false),
            v("244", "webm", 854, 480, "vp9", 700, exact: false),
            v("134", "mp4", 640, 360, "avc1.4d401e", 600, exact: false),
            v("133", "mp4", 426, 240, "avc1.4d4015", 300, exact: false),
            v("160", "mp4", 256, 144, "avc1.4d400c", 110, exact: false),
            MediaFormat(id: "18", ext: "mp4", width: 640, height: 360, fps: 30, videoCodecName: "avc1.42001E", audioCodecName: "mp4a.40.2",
                        videoBitrate: 500, audioBitrate: 96, fileSize: nil, language: "en", audioRole: .original),
            a("140", "m4a", "mp4a.40.2", 129, "en", .original),
            a("251", "webm", "opus", 136, "en", .original),
            a("140-1", "m4a", "mp4a.40.2", 129, "es", .dubbed),
            a("251-1", "webm", "opus", 133, "es", .dubbed),
            a("251-2", "webm", "opus", 131, "fr", .dubbed),
            a("140-3", "m4a", "mp4a.40.2", 129, "de", .dubbed),
            a("251-3", "webm", "opus", 130, "de", .dubbed),
            a("251-4", "webm", "opus", 132, "ja", .dubbed),
            MediaFormat(id: "sb0", ext: "mhtml", width: 160, height: 90, note: "storyboard"),
        ],
        subtitles: [
            SubtitleTrack(language: "en", name: "English", isAutomatic: false),
            SubtitleTrack(language: "es", name: "Spanish", isAutomatic: false),
            SubtitleTrack(language: "en", name: "English (auto)", isAutomatic: true),
            SubtitleTrack(language: "fr", name: "French (auto)", isAutomatic: true),
            SubtitleTrack(language: "de", name: "German (auto)", isAutomatic: true),
        ],
        chapterCount: 9)
        let names = ["Sunrise over the inversion", "The sea of clouds", "Lenticular season", "Noctilucent nights", "Storm fronts",
                     "First snow", "Aurora", "Midsummer light", "A year in one minute"]
        m.chapters = names.enumerated().map { i, n in MediaInfo.Chapter(title: n, start: Double(i) * 83.0, end: i == 8 ? duration : Double(i + 1) * 83.0) }
        return m
    }()

    /// A simple site with a single combined stream and no language information.
    public static let simple = MediaInfo(
        id: "sample-simple", webpageURL: URL(string: "https://vimeo.com/000000")!, title: "Morning Fog, Short Film",
        uploader: "A. Filmmaker", site: "Vimeo", duration: 182,
        formats: [
            MediaFormat(id: "hls-720", ext: "mp4", width: 1280, height: 720, fps: 25, videoCodecName: "avc1.64001f", audioCodecName: "mp4a.40.2",
                        videoBitrate: 2400, audioBitrate: 128, fileSize: nil),
            MediaFormat(id: "hls-1080", ext: "mp4", width: 1920, height: 1080, fps: 25, videoCodecName: "avc1.640028", audioCodecName: "mp4a.40.2",
                        videoBitrate: 4800, audioBitrate: 128, fileSize: nil),
        ])

    public static let playlist = MediaCollection(
        id: "sample-list", title: "Mountain Weather, Explained", uploader: "Highland Skies Studio", site: "YouTube",
        entries: [
            .init(id: "e1", title: "Why clouds form above mountains", url: URL(string: "https://www.youtube.com/watch?v=e1")!, duration: 512),
            .init(id: "e2", title: "Temperature inversions: the sea of clouds", url: URL(string: "https://www.youtube.com/watch?v=e2")!, duration: 634),
            .init(id: "e3", title: "Reading the sky: tomorrow’s weather today", url: URL(string: "https://www.youtube.com/watch?v=e3")!, duration: 421),
            .init(id: "e4", title: "Föhn winds and lenticular clouds", url: URL(string: "https://www.youtube.com/watch?v=e4")!, duration: 701),
            .init(id: "e5", title: "Noctilucent clouds at midsummer", url: URL(string: "https://www.youtube.com/watch?v=e5")!, duration: 388),
            .init(id: "e6", title: "How to photograph the aurora", url: URL(string: "https://www.youtube.com/watch?v=e6")!, duration: 955),
        ])
}
