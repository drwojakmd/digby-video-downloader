import Foundation

public enum AnalysisResult: Sendable {
    case single(MediaInfo)
    case collection(MediaCollection)
}

/// Turns yt-dlp's `-J` JSON into Digby's own types. The only place that knows yt-dlp's field names.
/// Real data is messy: missing codecs mean "unknown" (not "none"), "-1" means unknown, manifests
/// without details are dropped.
public enum YtDlpDecoder {
    public struct Failure: Error, CustomStringConvertible { public var description: String }

    /// yt-dlp's `live_status` for a single video ("is_live", "is_upcoming", "was_live", "not_live"), if given.
    public static func liveStatus(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["formats"] != nil else { return nil }
        if let s = root["live_status"] as? String { return s }
        return (root["is_live"] as? Bool) == true ? "is_live" : nil
    }

    public static func decode(_ data: Data) throws -> AnalysisResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(description: "The engine returned something that isn’t media information")
        }
        let type = root["_type"] as? String
        if type == "playlist" || type == "multi_video" || (root["entries"] != nil && root["formats"] == nil) {
            return .collection(collection(root))
        }
        return .single(try media(root))
    }

    static func collection(_ d: [String: Any]) -> MediaCollection {
        let entries = (d["entries"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.enumerated().compactMap { i, e -> MediaCollection.Entry? in
            let urlString = (e["webpage_url"] as? String) ?? (e["url"] as? String) ?? (e["original_url"] as? String)
            guard let s = urlString, let url = URL(string: s), url.scheme?.hasPrefix("http") == true else { return nil }
            let thumb = (e["thumbnail"] as? String) ?? ((e["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
            return .init(id: (e["id"] as? String) ?? "\(i)", title: (e["title"] as? String) ?? "Video \(i + 1)", url: url, duration: num(e["duration"]),
                         thumbnail: thumb.flatMap(URL.init(string:)))
        }
        return MediaCollection(id: (d["id"] as? String) ?? UUID().uuidString, title: (d["title"] as? String) ?? "Playlist",
                               uploader: (d["uploader"] as? String) ?? (d["channel"] as? String), site: site(d), entries: entries)
    }

    static func media(_ d: [String: Any]) throws -> MediaInfo {
        let rawFormats = (d["formats"] as? [[String: Any]]) ?? (d["url"] != nil ? [d] : [])
        var formats = rawFormats.compactMap(format)
        // Sound roles: a note saying "original" marks the original track; other languages are dubs.
        let hasOriginal = formats.contains { $0.audioRole == .original }
        if hasOriginal {
            for i in formats.indices where formats[i].hasAudio && formats[i].audioRole == .unknown && formats[i].language != nil {
                formats[i].audioRole = .dubbed
            }
        }
        guard let urlString = (d["webpage_url"] as? String) ?? (d["original_url"] as? String), let url = URL(string: urlString) else {
            throw Failure(description: "No page address in the engine’s answer")
        }
        var info = MediaInfo(id: (d["id"] as? String) ?? UUID().uuidString, webpageURL: url,
                         title: (d["title"] as? String) ?? (d["fulltitle"] as? String) ?? "Untitled",
                         uploader: (d["uploader"] as? String) ?? (d["channel"] as? String) ?? (d["creator"] as? String),
                         site: site(d), duration: num(d["duration"]), uploadDate: date(d["upload_date"] as? String),
                         description: d["description"] as? String, thumbnailURL: (d["thumbnail"] as? String).flatMap(URL.init(string:)),
                         formats: formats, subtitles: subtitles(d), chapterCount: (d["chapters"] as? [Any])?.count ?? 0)
        info.chapters = ((d["chapters"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let s = num(c["start_time"]), let e = num(c["end_time"]), e > s else { return nil }
            return MediaInfo.Chapter(title: (c["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Chapter", start: s, end: e)
        }
        return info
    }

    static let manifestExts: Set<String> = ["mpd", "m3u8", "f4m", "ism"]
    static let audioExts: Set<String> = ["m4a", "mp3", "opus", "ogg", "oga", "aac", "flac", "wav", "weba", "mka"]
    static let videoExts: Set<String> = ["mp4", "m4v", "webm", "mov", "mkv", "flv", "ts", "ogv", "avi", "3gp"]

    static func format(_ f: [String: Any]) -> MediaFormat? {
        guard let id = f["format_id"] as? String ?? (f["ext"] as? String) else { return nil }
        let ext = (f["ext"] as? String) ?? "unknown"
        let w = int(f["width"]), h = int(f["height"])
        var vcodec = f["vcodec"] as? String, acodec = f["acodec"] as? String
        // yt-dlp: "none" = absent; missing = not reported.
        let videoKnownAbsent = vcodec == "none", audioKnownAbsent = acodec == "none"
        if videoKnownAbsent { vcodec = nil }
        if audioKnownAbsent { acodec = nil }
        // Manifest entries with no codec details can't be judged; their streams appear separately.
        if manifestExts.contains(ext) && vcodec == nil && acodec == nil { return nil }
        // Some sites (X, BitChute, many smaller ones) say nothing about a video file's contents: treat it as
        // "unknown, to be inspected" rather than "no picture".
        if vcodec == nil && !videoKnownAbsent && ((w ?? 0) > 0 || (h ?? 0) > 0 || videoExts.contains(ext)) { vcodec = "unknown" }
        if acodec == nil && !audioKnownAbsent && (vcodec == "unknown" || audioExts.contains(ext)) { acodec = "unknown" }
        if vcodec == nil && acodec == nil { return nil }   // images, storyboards
        let size = int64(f["filesize"]), approx = int64(f["filesize_approx"])
        let tbr = num(f["tbr"]), vbr = num(f["vbr"]), abr = num(f["abr"])
        let note = f["format_note"] as? String
        let lower = note?.lowercased() ?? ""
        let role: AudioRole = lower.contains("descriptive") ? .descriptive : lower.contains("original") ? .original : .unknown
        var lang = f["language"] as? String
        if lang == "und" || lang?.isEmpty == true { lang = nil }
        let dr: DynamicRange = switch (f["dynamic_range"] as? String)?.uppercased() {
            case let s? where s.hasPrefix("HDR"): .hdr10
            case "HLG": .hlg
            case "DV": .dolbyVision
            default: .sdr
        }
        let hasV = vcodec != nil, hasA = acodec != nil
        var headers = (f["http_headers"] as? [String: String] ?? [:]).filter { $0.key.lowercased() != "cookie" }
        if headers.isEmpty, let r = f["referer"] as? String { headers["Referer"] = r }
        var made = MediaFormat(id: id, ext: ext, width: w, height: h, fps: num(f["fps"]).flatMap { $0 <= 240 ? $0 : nil },
                           videoCodecName: vcodec, audioCodecName: acodec,
                           videoBitrate: hasV ? (vbr ?? (hasA ? tbr.map { max(0, $0 - (abr ?? 0)) } : tbr)) : nil,
                           audioBitrate: hasA ? (abr ?? (hasV ? nil : tbr)) : nil,
                           fileSize: size ?? approx, fileSizeIsExact: size != nil,
                           language: lang, audioRole: role, dynamicRange: dr, bitDepth: nil,
                           audioChannels: int(f["audio_channels"]), note: note, isDRM: (f["has_drm"] as? Bool) == true,
                           streamURL: (f["url"] as? String).flatMap(URL.init(string:)), protocolName: f["protocol"] as? String)
        made.httpHeaders = headers
        return made
    }

    static func subtitles(_ d: [String: Any]) -> [SubtitleTrack] {
        func tracks(_ dict: [String: Any]?, automatic: Bool) -> [SubtitleTrack] {
            guard let dict else { return [] }
            var keys = dict.keys.filter { $0 != "live_chat" && $0 != "rechat" }
            // YouTube offers machine translations into every language; keep only the original-speech captions.
            if automatic, keys.contains(where: { $0.hasSuffix("-orig") }) { keys = keys.filter { $0.hasSuffix("-orig") } }
            return keys.sorted().map { key in
                let list = dict[key] as? [[String: Any]] ?? []
                let lang = key.hasSuffix("-orig") ? String(key.dropLast(5)) : key
                return SubtitleTrack(language: lang, name: list.first?["name"] as? String, isAutomatic: automatic,
                                     formats: list.compactMap { $0["ext"] as? String }, key: key)
            }
        }
        return tracks(d["subtitles"] as? [String: Any], automatic: false) + tracks(d["automatic_captions"] as? [String: Any], automatic: true)
    }

    static func site(_ d: [String: Any]) -> String {
        let known = ["Youtube": "YouTube", "YoutubeTab": "YouTube", "Vimeo": "Vimeo", "ArchiveOrg": "Internet Archive",
                     "Wikimedia": "Wikimedia Commons", "SoundcloudSet": "SoundCloud", "Soundcloud": "SoundCloud",
                     "Twitch": "Twitch", "TwitchVod": "Twitch", "Dailymotion": "Dailymotion", "BandcampAlbum": "Bandcamp", "Bandcamp": "Bandcamp"]
        if let k = d["extractor_key"] as? String, let n = known[k] { return n }
        if let dom = d["webpage_url_domain"] as? String { return dom.replacingOccurrences(of: "www.", with: "") }
        return (d["extractor_key"] as? String) ?? "Web"
    }

    static func date(_ s: String?) -> Date? {
        guard let s, s.count == 8 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
    static func num(_ v: Any?) -> Double? {
        let d: Double? = (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue
        guard let d, d > 0, d.isFinite else { return nil }
        return d
    }
    static func int(_ v: Any?) -> Int? { num(v).map { Int($0) } }
    static func int64(_ v: Any?) -> Int64? { num(v).map { Int64($0) } }
}
