import Foundation

/// Paths of the engines in use. `.managed` is the app's own verified install; tests can point elsewhere.
public struct EngineTools: Sendable {
    public var ytdlp: URL, deno: URL, ffmpeg: URL, ffprobe: URL
    /// A folder holding both ffmpeg and ffprobe (what yt-dlp is pointed at).
    public var ffmpegLocation: URL
    public init(ytdlp: URL, deno: URL, ffmpeg: URL, ffprobe: URL, ffmpegLocation: URL? = nil) {
        self.ytdlp = ytdlp; self.deno = deno; self.ffmpeg = ffmpeg; self.ffprobe = ffprobe
        self.ffmpegLocation = ffmpegLocation ?? ffmpeg.deletingLastPathComponent()
    }

    public static var managed: EngineTools {
        // Launch the real files, not the links: the yt-dlp build locates its libraries next to itself.
        func real(_ t: ToolID) -> URL { DependencyManager.executable(t).resolvingSymlinksInPath() }
        return EngineTools(ytdlp: real(.ytdlp), deno: real(.deno), ffmpeg: real(.ffmpeg), ffprobe: real(.ffprobe),
                           ffmpegLocation: DependencyManager.binDirectory)
    }
    public var available: Bool {
        [ytdlp, deno, ffmpeg, ffprobe].allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// Cancels whatever engine process a job is currently running.
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: RunningProcess?
    private var _cancelled = false
    private var _paused = false
    public init() {}
    /// Stopped by Pause (partial data kept) rather than Cancel.
    public var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return _paused }
    public func pause() { lock.lock(); _paused = true; lock.unlock(); cancel() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    public func cancel() {
        lock.lock(); _cancelled = true; let p = process; lock.unlock()
        p?.cancel()
    }
    func attach(_ p: RunningProcess) {
        lock.lock(); process = p; let c = _cancelled; lock.unlock()
        if c { p.cancel() }
    }
}

/// The yt-dlp extraction engine behind Digby's own interface.
public struct YtDlpEngine: Sendable {
    public var tools: EngineTools
    public init(tools: EngineTools = .managed) { self.tools = tools }

    /// Options passed on every run: ignore any personal yt-dlp configuration, never self-update
    /// (Digby manages versions), and use the managed JavaScript runtime and FFmpeg.
    var baseArguments: [String] {
        ["--ignore-config", "--no-update", "--no-colors", "--no-cache-dir",
         "--js-runtimes", "deno:\(tools.deno.path)",
         "--ffmpeg-location", tools.ffmpegLocation.path]
        // Same route to the internet as the Mac itself (e.g. a VPN's local proxy), even when launched from Finder.
        + (SystemNetwork.httpsProxy.map { ["--proxy", $0] } ?? [])
    }

    /// Reads a link: one video, or the list of a playlist/channel (entries listed quickly, analysed when chosen).
    public func analyse(_ url: URL, cancel: CancelToken? = nil, extraArguments: [String] = []) async throws -> AnalysisResult {
        guard tools.available else { throw failure(.missingEngine, "The download engines aren’t installed yet", "Digby is setting them up; try again in a moment.") }
        Log.write("analyse \(url.absoluteString)")
        var refresh = false, r: ProcessResult, browserFallback: Browser? = nil
        while true {
            let access = !extraArguments.isEmpty ? extraArguments
                : browserFallback.map { ["--cookies-from-browser", $0.rawValue] } ?? signInArguments(for: url, refresh: refresh)
            let args = baseArguments + access + ["-J", "--flat-playlist", "--", url.absoluteString]
            r = try await ProcessRunner.run(tools.ytdlp, args, started: { cancel?.attach($0) })
            afterRun(url)
            if r.cancelled { throw ErrorClassifier.cancelled() }
            if r.succeeded { break }
            var f = ErrorClassifier.classify(stderr: r.stderr, exitCode: r.status)
            // "Unable to extract" from a page that doesn't exist is a missing page, not a changed site.
            f = await PageStatus.correct(f, for: url)
            if f.kind == .unavailable { Log.write("analyse failed (page missing): \(f.detail)"); throw f }
            // The saved sign-in may have expired: copy it from the browser again, once.
            if !refresh, Self.needsSignIn(f), canRefreshSignIn(url) { refresh = true; Log.write("refreshing sign-in and retrying"); continue }
            // Allowed by the person: when a site refuses, try once more as them (their browser's sign-in, read fresh),
            // and remember it for that site if it works.
            let settings = SignInSettings.load()
            if browserFallback == nil, extraArguments.isEmpty, let b = settings.anySite, let site = SignInSite.site(for: url),
               settings.sites[site] == nil, Self.signInMightHelp(f) {
                browserFallback = b; Log.write("retrying with \(b.rawValue) sign-in"); continue
            }
            Log.write("analyse failed (\(f.kind.rawValue)): \(f.detail)")
            throw f
        }
        if let b = browserFallback, let site = SignInSite.site(for: url) {
            var s = SignInSettings.load(); s.sites[site] = .browser(b); try? s.save()
        }
        if let live = YtDlpDecoder.liveStatus(Data(r.stdout.utf8)), live == "is_live" || live == "is_upcoming" {
            Log.write("analyse: \(live), not downloadable yet")
            throw live == "is_live" ? ErrorClassifier.liveNow() : ErrorClassifier.classify(stderr: "ERROR: This live event will begin in a while")
        }
        var result = try YtDlpDecoder.decode(Data(r.stdout.utf8))
        if case .single(var m) = result {
            m = await FormatInspector(ffprobe: tools.ffprobe).fillUnknownCodecs(m)
            // YouTube sometimes answers with only a combined low-resolution file (no separate streams).
            if SignInSite.site(for: url) == .youtube, !m.formats.contains(where: { $0.hasVideo && !$0.hasAudio }) {
                m.notice = SignInSettings.load().sites[.youtube] == nil
                    ? "YouTube sent only a reduced list of formats. This is common on VPNs; using your YouTube sign-in (Settings → Privacy) usually restores every resolution."
                    : "YouTube sent only a reduced list of formats this time. Trying again in a minute, or signing in again (Settings → Privacy), usually restores every resolution."
            }
            result = .single(m)
        }
        return result
    }

    func failure(_ k: Failure.Kind, _ t: String, _ e: String) -> Failure {
        Failure(kind: k, title: t, explanation: e, retryable: false, suggestsEngineUpdate: false, detail: "")
    }
}

/// Some sites don't say which codecs their files use. FFprobe reads just the stream headers to find out,
/// so Digby can still tell you whether a file plays everywhere or needs converting.
public struct FormatInspector: Sendable {
    var ffprobe: URL
    public init(ffprobe: URL) { self.ffprobe = ffprobe }

    public func fillUnknownCodecs(_ media: MediaInfo) async -> MediaInfo {
        var m = media
        let targets = m.formats.indices.filter { i in
            let f = m.formats[i]
            // Direct files and HLS playlists can be inspected; DASH manifests can't be read this way.
            return f.hasUnknownCodec && f.streamURL?.scheme?.hasPrefix("http") == true && !(f.protocolName ?? "").contains("dash")
        }.prefix(8)
        guard !targets.isEmpty else { return m }
        await withTaskGroup(of: (Int, ProbeResult?).self) { group in
            for i in targets {
                let url = m.formats[i].streamURL!
                var headers = m.formats[i].httpHeaders
                if headers["Referer"] == nil { headers["Referer"] = m.webpageURL.absoluteString }
                group.addTask { (i, await probe(url, headers: headers)) }
            }
            for await (i, r) in group {
                guard let r else { continue }
                var f = m.formats[i]
                f.videoCodecName = r.video
                f.audioCodecName = r.audio
                if let w = r.width { f.width = w }
                if let h = r.height { f.height = h }
                if f.fps == nil, let fps = r.fps, fps > 0, fps <= 240 { f.fps = fps }   // some files report a timebase, not a frame rate
                if f.audioChannels == nil { f.audioChannels = r.channels }
                if f.videoBitrate == nil, f.audioBitrate == nil, let b = r.bitrate { f.videoBitrate = b }
                m.formats[i] = f
            }
        }
        // Anything still unknown can't be promised to fit a file type; leave it out rather than guess.
        m.formats.removeAll { $0.hasUnknownCodec && $0.videoCodecName != nil && $0.width == nil }
        return m
    }

    struct ProbeResult: Sendable { var video: String?; var audio: String?; var width: Int?; var height: Int?; var fps: Double?; var channels: Int?; var bitrate: Double? }

    func probe(_ url: URL, headers: [String: String] = [:]) async -> ProbeResult? {
        var handle: RunningProcess?
        let timer = DispatchWorkItem { handle?.cancel(grace: 1) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timer)
        defer { timer.cancel() }
        guard let r = try? await ProcessRunner.run(ffprobe, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format",
                                                              "-rw_timeout", "15000000"] + SystemNetwork.ffmpegNetworkOptions
                                                              + Self.headerOptions(headers) + [url.absoluteString],
                                                    started: { handle = $0 }),
              r.succeeded, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any] else { return nil }
        let streams = j["streams"] as? [[String: Any]] ?? []
        let v = streams.first { ($0["codec_type"] as? String) == "video" && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
        let a = streams.first { ($0["codec_type"] as? String) == "audio" }
        var fps: Double?
        if let s = v?["avg_frame_rate"] as? String {
            let p = s.split(separator: "/").compactMap { Double($0) }
            if p.count == 2, p[1] > 0, p[0] > 0 { fps = (p[0] / p[1] * 1000).rounded() / 1000 }
        }
        let bitrate = ((j["format"] as? [String: Any])?["bit_rate"] as? String).flatMap(Double.init).map { $0 / 1000 }
        return ProbeResult(video: Self.codecTag(v), audio: Self.codecTag(a), width: v?["width"] as? Int, height: v?["height"] as? Int,
                           fps: fps, channels: a?["channels"] as? Int, bitrate: bitrate)
    }

    /// The site's expected headers for FFmpeg's HTTP reader (header names and values are sanitised to single lines).
    static func headerOptions(_ h: [String: String]) -> [String] {
        let clean = h.filter { !$0.key.isEmpty }.map { k, v in
            "\(k.filter { $0.isLetter || $0.isNumber || $0 == "-" }): \(v.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))"
        }
        guard !clean.isEmpty else { return [] }
        if let ua = h.first(where: { $0.key.lowercased() == "user-agent" })?.value {
            return ["-user_agent", ua, "-headers", clean.filter { !$0.lowercased().hasPrefix("user-agent") }.map { $0 + "\r\n" }.joined()]
        }
        return ["-headers", clean.map { $0 + "\r\n" }.joined()]
    }

    /// FFprobe codec names → the strings Digby's codec families understand.
    static func codecTag(_ s: [String: Any]?) -> String? {
        guard let name = s?["codec_name"] as? String else { return nil }
        switch name {
        case "h264": return "avc1"
        case "hevc": return "hvc1"
        case "av1": return "av01"
        case "vp9": return "vp9"
        case "aac": return "mp4a.40.2"
        default: return name
        }
    }
}
