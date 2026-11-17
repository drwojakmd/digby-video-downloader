import Foundation

/// A video or audio stream noticed while a page plays in Digby's built-in browser (the page catcher).
/// Only whole files and streaming playlists count: the thousands of small pieces a player fetches are ignored.
public struct CaughtStream: Sendable, Hashable, Identifiable {
    public enum Kind: Int, Sendable, Hashable, Comparable {
        case adaptive = 0   // HLS master playlist: several qualities
        case file           // a whole video file (more dependable than one quality of a stream)
        case stream         // HLS media playlist or DASH manifest
        case audio          // a whole audio file
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }
    public var url: URL
    public var kind: Kind
    public var maxHeight: Int?        // from a master playlist's RESOLUTION, or the playing video element
    public var bytes: Int64?          // for whole files, when the server says
    public var id: String { url.absoluteString }
    public init(url: URL, kind: Kind, maxHeight: Int? = nil, bytes: Int64? = nil) {
        self.url = url; self.kind = kind; self.maxHeight = maxHeight; self.bytes = bytes
    }

    public var label: String {
        switch kind {
        case .adaptive: return "Video stream" + (maxHeight.map { ", up to \(Self.tierName($0))" } ?? ", several qualities")
        case .stream: return "Video stream" + (maxHeight.map { ", \(Self.tierName($0))" } ?? "")
        case .file: return "Video file" + (maxHeight.map { ", \(Self.tierName($0))" } ?? "") + (bytes.map { " · \(Fmt.bytes($0))" } ?? "")
        case .audio: return "Audio file" + (bytes.map { " · \(Fmt.bytes($0))" } ?? "")
        }
    }
    public var explanation: String {
        switch kind {
        case .adaptive: "The player’s full stream: Digby can offer every quality it contains."
        case .stream: "One quality of the player’s stream."
        case .file: "The whole video as a single file."
        case .audio: "Just the sound."
        }
    }
    static func tierName(_ h: Int) -> String { ResolutionTier(width: h * 16 / 9, height: h).name }

    /// What a request looks like: a stream worth offering, or nil (pieces, images, scripts, tracking).
    public static func classify(_ url: URL) -> Kind? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        // pieces of a stream: segments, fragments, byte ranges, init chunks
        if path.hasSuffix(".ts") || path.hasSuffix(".m4s") || path.hasSuffix(".aac") && path.contains("seg") { return nil }
        if path.range(of: #"(seg|segment|frag|fragment|chunk|init|part)[-_./]?\d"#, options: .regularExpression) != nil { return nil }
        // (byte-range requests are pieces of a whole file: callers pass `wholeFile(_:)` first)
        if path.hasSuffix(".m3u8") || query.contains("format=m3u8") { return .stream }        // refined to .adaptive after reading it
        if path.hasSuffix(".mpd") { return .stream }
        for ext in [".mp4", ".m4v", ".webm", ".mov", ".mkv"] where path.hasSuffix(ext) { return .file }
        for ext in [".m4a", ".mp3", ".ogg", ".opus", ".flac", ".wav"] where path.hasSuffix(ext) { return .audio }
        return nil
    }

    /// The whole file behind a byte-range request (Facebook and others fetch files in pieces):
    /// the same address without its range markers. Nil when the address has none.
    public static func wholeFile(_ url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = c.queryItems else { return nil }
        let rangeKeys: Set<String> = ["bytestart", "byteend", "range", "byterange", "rn", "rbuf"]
        let kept = items.filter { !rangeKeys.contains($0.name.lowercased()) }
        guard kept.count != items.count else { return nil }
        c.queryItems = kept.isEmpty ? nil : kept
        return c.url
    }

    /// What a server's answer says a media address really is (for addresses without a telling extension).
    public static func classify(mimeType: String?) -> Kind? {
        guard let m = mimeType?.lowercased() else { return nil }
        if m.contains("mpegurl") { return .stream }
        if m.contains("dash+xml") { return .stream }
        if m.hasPrefix("video/") { return .file }
        if m.hasPrefix("audio/") { return .audio }
        return nil
    }

    /// Reads an HLS playlist's text: a master (lists qualities) and its best resolution.
    public static func inspectPlaylist(_ text: String) -> (isMaster: Bool, maxHeight: Int?) {
        let isMaster = text.contains("#EXT-X-STREAM-INF")
        var best: Int?
        if let re = try? NSRegularExpression(pattern: #"RESOLUTION=(\d+)x(\d+)"#) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 2), in: text), let h = Int(text[r]) { best = max(best ?? 0, h) }
            }
        }
        return (isMaster, best)
    }

    /// The one to suggest: a full adaptive stream first, then the highest resolution, then the biggest file.
    public static func best(_ list: [CaughtStream]) -> CaughtStream? {
        list.sorted { a, b in
            if a.kind != b.kind { return a.kind < b.kind }
            if (a.maxHeight ?? 0) != (b.maxHeight ?? 0) { return (a.maxHeight ?? 0) > (b.maxHeight ?? 0) }
            return (a.bytes ?? 0) > (b.bytes ?? 0)
        }.first
    }
}

extension CaughtPage {
    /// Page titles carry the site's name and slogans ("Film : Free Download… : Internet Archive",
    /// "File:Film.webm - Wikimedia Commons"): keep the part that names the video.
    public static func cleanTitle(_ raw: String, host: String?) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = host?.lowercased().replacingOccurrences(of: "www.", with: "").split(separator: ".").first.map(String.init) ?? ""
        for sep in [" | ", " — ", " – ", " - ", " : ", " · "] where t.contains(sep) {
            let parts = t.components(separatedBy: sep)
            if parts.count >= 2, let last = parts.last?.lowercased(), !label.isEmpty, last.contains(label) || label.contains(last.replacingOccurrences(of: " ", with: "")) {
                t = parts[0]
                break
            }
        }
        if t.hasPrefix("File:") { t = String(t.dropFirst(5)) }
        for ext in [".webm", ".mp4", ".mov", ".mkv", ".ogv", ".m4v"] where t.lowercased().hasSuffix(ext) { t = String(t.dropLast(ext.count)) }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? raw : t
    }
}

/// The page a stream was caught on, to carry the right name, picture and request headers through.
public struct CaughtPage: Sendable, Hashable {
    public var pageURL: URL
    public var title: String?
    public var thumbnail: URL?
    public var siteName: String?
    public var userAgent: String
    public var cookieFile: URL?
    public init(pageURL: URL, title: String?, thumbnail: URL?, siteName: String?, userAgent: String, cookieFile: URL?) {
        self.pageURL = pageURL; self.title = title; self.thumbnail = thumbnail; self.siteName = siteName
        self.userAgent = userAgent; self.cookieFile = cookieFile
    }
}

extension YtDlpEngine {
    /// Analyses a stream caught on a page, sending what the page's player sent (its address as Referer, the
    /// browser's identity and the page's cookies), then names the result after the page rather than the file.
    public func analyse(caught s: CaughtStream, on page: CaughtPage, cancel: CancelToken? = nil) async throws -> MediaInfo {
        let extra = Self.requestArguments(for: page)
        guard case .single(var m) = try await analyse(s.url, cancel: cancel, extraArguments: extra) else {
            throw Failure(kind: .unsupportedFormat, title: "That stream is a list, not a video", explanation: "Choose another stream from the page.",
                          retryable: false, suggestsEngineUpdate: false, detail: "")
        }
        m.engineURL = s.url
        m.engineArguments = extra
        m.webpageURL = page.pageURL
        if let t = page.title, !t.isEmpty { m.title = CaughtPage.cleanTitle(t, host: page.pageURL.host) }
        if let i = page.thumbnail { m.thumbnailURL = i }
        m.site = page.siteName ?? SignInSite.site(for: page.pageURL)?.displayName ?? m.site
        m.notice = [m.notice, "Caught from the page while it played."].compactMap { $0 }.joined(separator: " ")
        return m
    }

    /// Reads the page itself with the session of Digby's own browser (cookies the person signed in with or
    /// earned by passing a site check, and the same browser identity). The engine then sees what the person saw.
    public func analyse(pageWithSession page: CaughtPage, cancel: CancelToken? = nil) async throws -> AnalysisResult {
        var a = ["--add-header", "User-Agent:\(page.userAgent)"]
        if let c = page.cookieFile { a += ["--cookies", c.path] }
        var r = try await analyse(page.pageURL, cancel: cancel, extraArguments: a)
        if case .single(var m) = r { m.engineArguments = a; m.engineURL = nil; r = .single(m) }
        return r
    }

    static func requestArguments(for page: CaughtPage) -> [String] {
        var a = ["--add-header", "Referer:\(page.pageURL.absoluteString)", "--add-header", "User-Agent:\(page.userAgent)"]
        if let origin = page.pageURL.host.map({ "\(page.pageURL.scheme ?? "https")://\($0)" }) { a += ["--add-header", "Origin:\(origin)"] }
        if let c = page.cookieFile { a += ["--cookies", c.path] }
        return a
    }
}
