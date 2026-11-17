import Foundation

public struct DownloadRequest: Sendable {
    public var media: MediaInfo
    public var plan: DownloadPlan
    public var folder: URL
    public var fileName: String            // without extension
    public var embedMetadata = true
    public var embedChapters = true
    public var recordSource = true         // Finder's "Where from"
    /// Stable work-folder name so a paused download continues where it stopped.
    public var workID: String? = nil
    /// Most bytes per second this download may use (nil: as fast as the site allows).
    public var rateLimit: Int64? = nil
    /// Translates an .srt file on this Mac (supplied by the app; macOS's own translation).
    public var translator: SubtitleTranslator? = nil
    public init(media: MediaInfo, plan: DownloadPlan, folder: URL, fileName: String) {
        self.media = media; self.plan = plan; self.folder = folder; self.fileName = fileName
    }
}

/// (srt file, from language, to language) → translated .srt file.
public typealias SubtitleTranslator = @Sendable (_ srt: URL, _ from: String, _ to: String) async throws -> URL

public enum DownloadEvent: Sendable {
    case phase(String)
    case progress(downloaded: Int64, total: Int64?, speed: Double?, eta: Double?)
    case processing(fraction: Double?)
}

public struct DownloadOutcome: Sendable {
    public var file: URL
    public var subtitleFiles: [URL]
    public var bytes: Int64
    public var report: VerificationReport
    /// Anything that didn't go as planned but didn't stop the download (said plainly).
    public var warnings: [String] = []
}

/// Runs one download: yt-dlp fetches (and joins) the chosen streams into a hidden work folder next to
/// the destination; FFmpeg copies them into the chosen file type (converting only what the plan says);
/// FFprobe checks the result; then it's moved into place under a name that doesn't overwrite anything.
public struct Downloader: Sendable {
    public var tools: EngineTools
    public init(tools: EngineTools = .managed) { self.tools = tools }

    /// Removes work folders left by a crash or a paused download abandoned for two weeks.
    public static func sweep(_ folder: URL, keeping ids: Set<String>, olderThan age: TimeInterval = 14 * 86_400) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(".digby-download-") {
            let id = String(name.dropFirst(".digby-download-".count))
            let url = folder.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            if !ids.contains(id) && (Date().timeIntervalSince(modified) > age || ids.isEmpty && age == 0) { try? fm.removeItem(at: url) }
        }
    }

    public func download(_ req: DownloadRequest, cancel: CancelToken, events: @escaping @Sendable (DownloadEvent) -> Void) async throws -> DownloadOutcome {
        let fm = FileManager.default
        guard tools.available else { throw ErrorClassifier.classify(stderr: "ERROR: engines missing") }
        try Paths.ensure(req.folder)
        try checkSpace(req)
        let work = req.folder.appendingPathComponent(".digby-download-\(req.workID ?? String(UUID().uuidString.prefix(8)))", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        // Kept when paused, or after a failure worth retrying (the retry continues the partial files);
        // removed after success, cancel, or a failure that retrying can't fix.
        var keepWork = false
        defer { if !(cancel.isPaused || keepWork) { try? fm.removeItem(at: work) } }
        do { return try await perform(req, work: work, cancel: cancel, events: events) }
        catch let f as Failure { keepWork = f.retryable && f.kind != .cancelled && req.workID != nil; throw f }
    }

    /// Removes a job's kept work folder (after the last retry gives up).
    public static func discardWork(in folder: URL, id: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(".digby-download-\(id)", isDirectory: true))
    }

    func perform(_ req: DownloadRequest, work: URL, cancel: CancelToken, events: @escaping @Sendable (DownloadEvent) -> Void) async throws -> DownloadOutcome {
        let fm = FileManager.default
        Log.write("download \(req.media.webpageURL.absoluteString) -f \(req.plan.formatExpression)")

        // 1. Fetch
        events(.phase("Downloading"))
        let fetched = try await fetch(req, into: work, cancel: cancel, events: events)
        if cancel.isCancelled { throw ErrorClassifier.cancelled() }
        var subtitles = fetched.subtitles
        var warnings: [String] = []

        // 1b. Translate the subtitles on this Mac, when asked
        if let to = req.plan.translateTo, let first = subtitles.first {
            if let translate = req.translator {
                events(.phase("Translating the subtitles into \(Languages.name(to))"))
                do {
                    let srt = try await PostProcessor(ffmpeg: tools.ffmpeg).subtitleToSRT(first.file, cancel: cancel)
                    let out = try await translate(srt, first.language, to)
                    let translated = (file: out, language: to, automatic: false)
                    subtitles = req.plan.burnsSubtitles ? [translated] : [translated] + subtitles
                } catch {
                    if cancel.isCancelled { throw ErrorClassifier.cancelled() }
                    warnings.append("The subtitles couldn’t be translated (\(error.localizedDescription)), so the \(Languages.name(first.language)) ones were kept.")
                }
            } else {
                warnings.append("Translating subtitles needs macOS 15 or later, so the \(Languages.name(first.language)) ones were kept.")
            }
        }

        // 2. Into the chosen file type
        events(.phase(req.plan.videoConverted ? "Converting the picture to H.264" : req.plan.convertsAnything ? "Converting the sound" : "Preparing the file"))
        let output = work.appendingPathComponent("output.\(req.plan.outputExtension)")
        var burn: URL? = nil
        if req.plan.burnsSubtitles, let first = subtitles.first {
            events(.phase("Drawing the subtitles onto the picture"))
            let srt = try await PostProcessor(ffmpeg: tools.ffmpeg).subtitleToSRT(first.file, cancel: cancel)
            let dest = work.appendingPathComponent("burn.\(srt.pathExtension)")
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: srt, to: dest)
            burn = dest
        }
        try await PostProcessor(ffmpeg: tools.ffmpeg).make(output, from: fetched.media, subtitles: req.plan.subtitleMode == .embed ? subtitles : [],
                                                          burn: burn, request: req, cancel: cancel) { events(.processing(fraction: $0)) }
        if cancel.isCancelled { throw ErrorClassifier.cancelled() }

        // 3. Check it before calling it done
        events(.phase("Checking the file"))
        let clip = req.plan.clip
        // A quick cut starts on the key frame before the chosen moment: allow for it.
        let report = try await Verifier(ffprobe: tools.ffprobe).verify(output, plan: req.plan, expectedDuration: clip?.length ?? req.media.duration,
                                                                       slack: clip.map { $0.exact ? 1.5 : 15 } ?? 0)
        guard report.passed else {
            Log.write("verification failed: \(report.problems.joined(separator: "; "))")
            throw Failure(kind: .verificationFailed, title: "The finished file didn’t pass Digby’s check",
                          explanation: report.problems.joined(separator: " "), retryable: true, suggestsEngineUpdate: false, detail: report.problems.joined(separator: "\n"))
        }

        // 4. Into place, never overwriting
        let final = FileNamer.unique(req.fileName, ext: req.plan.outputExtension, in: req.folder)
        try fm.moveItem(at: output, to: final)
        var subs: [URL] = []
        if req.plan.subtitleMode == .files {
            for s in subtitles {
                let srt = try await PostProcessor(ffmpeg: tools.ffmpeg).subtitleToSRT(s.file, cancel: cancel)
                // The language code comes from the website: keep letters, digits and "-" only, so it can never form a path.
                let lang = String(s.language.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(20))
                let name = final.deletingPathExtension().lastPathComponent + ".\(lang.isEmpty ? "sub" : lang)" + (s.automatic ? ".auto" : "")
                let dest = FileNamer.unique(name, ext: "srt", in: req.folder)
                try fm.moveItem(at: srt, to: dest); subs.append(dest)
            }
        }
        if req.recordSource { FinderMetadata.mark(final, source: req.media.webpageURL, summary: report.summary) }
        let bytes = ((try? fm.attributesOfItem(atPath: final.path)[.size]) as? Int64) ?? 0
        Log.write("done → \(final.path) (\(bytes) bytes): \(report.summary)")
        return DownloadOutcome(file: final, subtitleFiles: subs, bytes: bytes, report: report, warnings: warnings)
    }

    struct Fetched { var media: URL; var subtitles: [(file: URL, language: String, automatic: Bool)] }

    func fetch(_ req: DownloadRequest, into work: URL, cancel: CancelToken, events: @escaping @Sendable (DownloadEvent) -> Void) async throws -> Fetched {
        let p = req.plan
        var args = YtDlpEngine(tools: tools).baseArguments
        args += ["--newline", "--progress", "--progress-template", "download:CDLP %(progress)j",
                 "--print", "after_move:CDLF %(filepath)j", "--no-simulate", "--no-mtime", "--no-playlist",
                 // Streamed videos arrive in hundreds of small pieces: fetch four at a time (polite, and several times faster).
                 "--concurrent-fragments", req.rateLimit == nil ? "4" : "1",
                 "-f", p.formatExpression, "-o", work.appendingPathComponent("media.%(ext)s").path]
        if p.video != nil && p.audio != nil { args += ["--merge-output-format", "mkv"] }   // lossless holder for anything
        if req.embedMetadata { args += ["--embed-metadata"] }
        if let limit = req.rateLimit, limit > 0 { args += ["--limit-rate", String(limit)] }
        if let clip = p.clip {
            args += ["--download-sections", String(format: "*%.3f-%.3f", clip.start, clip.end)]
            // A part is fetched by FFmpeg, which doesn't read the Mac's proxy or certificates by itself.
            let quoted = SystemNetwork.ffmpegNetworkOptions.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            if !quoted.isEmpty { args += ["--downloader-args", "ffmpeg_i:" + quoted.joined(separator: " ")] }
            if clip.exact { args += ["--force-keyframes-at-cuts", "--downloader-args", "ffmpeg_o:-crf 18 -preset faster"] }
        }
        if req.embedChapters && req.media.chapterCount > 0 && p.kind != .audioOnly { args += ["--embed-chapters"] }
        if !p.subtitles.isEmpty {
            args += ["--write-subs", "--sub-langs", p.subtitles.map(\.key).joined(separator: ","), "--sub-format", "vtt/srt/best"]
            if p.subtitles.contains(where: \.isAutomatic) { args += ["--write-auto-subs"] }
        }
        // A caught stream goes to the engine directly, with the page's headers and cookies; otherwise the page.
        let engine = YtDlpEngine(tools: tools), url = req.media.engineURL ?? req.media.webpageURL
        var refresh = false
        while true {
        let access = req.media.engineArguments.isEmpty ? engine.signInArguments(for: url, refresh: refresh) : req.media.engineArguments
        let runArgs = args + access + ["--", url.absoluteString]
        let tracker = ProgressTracker(expectedTotal: p.size?.bytes)
        let finalPath = LockedBox<String?>(nil)
        let r = try await ProcessRunner.run(tools.ytdlp, runArgs, started: { cancel.attach($0) }) { line, isError in
            if line.hasPrefix("CDLP "), let d = line.dropFirst(5).data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                if let e = tracker.update(j) { events(e) }
            } else if line.hasPrefix("CDLF "), let d = line.dropFirst(5).data(using: .utf8), let s = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String {
                finalPath.value = s
            } else if line.contains("[Merger]") { events(.phase("Joining picture and sound")) }
            else if line.contains("[Metadata]") { events(.phase("Adding title and details")) }
        }
        engine.afterRun(url)
        if r.cancelled || cancel.isCancelled { throw ErrorClassifier.cancelled() }
        guard r.succeeded, let path = finalPath.value, FileManager.default.fileExists(atPath: path) else {
            let f = ErrorClassifier.classify(stderr: r.stderr, exitCode: r.status)
            if !refresh, YtDlpEngine.needsSignIn(f), engine.canRefreshSignIn(url) { refresh = true; continue }
            Log.write("download failed (\(f.kind.rawValue)): \(f.detail)")
            throw f
        }
        // Subtitles land beside the media as media.<key>.<ext>.
        let files = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? []
        let subs: [(URL, String, Bool)] = p.subtitles.compactMap { t in
            files.first { $0.lastPathComponent.hasPrefix("media.\(t.key).") }.map { ($0, Languages.base(t.language), t.isAutomatic) }
        }
        return Fetched(media: URL(fileURLWithPath: path), subtitles: subs.map { (file: $0.0, language: $0.1, automatic: $0.2) })
        }
    }

    func checkSpace(_ req: DownloadRequest) throws {
        guard let need = req.plan.size?.bytes,
              let free = try? req.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        else { return }
        // Fetching, then copying into the final file type, briefly needs about twice the size.
        if Int64(free) < need * 2 + 200_000_000 {
            throw Failure(kind: .diskFull, title: "Not enough free space",
                          explanation: "This download needs about \(Fmt.bytes(need * 2)) while it’s being prepared, but only \(Fmt.bytes(Int64(free))) is free.",
                          retryable: false, suggestsEngineUpdate: false, detail: "")
        }
    }
}

/// Turns yt-dlp's per-stream progress into one overall figure (picture then sound count as one download).
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completed: Int64 = 0
    private var currentFile = ""
    private var currentTotal: Int64 = 0
    private let expectedTotal: Int64?
    private var lastEmit = Date.distantPast
    init(expectedTotal: Int64?) { self.expectedTotal = expectedTotal }

    func update(_ j: [String: Any]) -> DownloadEvent? {
        lock.lock(); defer { lock.unlock() }
        let file = j["filename"] as? String ?? ""
        let downloaded = (j["downloaded_bytes"] as? NSNumber)?.int64Value ?? 0
        let total = ((j["total_bytes"] as? NSNumber) ?? (j["total_bytes_estimate"] as? NSNumber))?.int64Value
        if file != currentFile {
            if !currentFile.isEmpty { completed += currentTotal }
            currentFile = file; currentTotal = 0
        }
        currentTotal = max(currentTotal, total ?? downloaded)
        // yt-dlp reports hundreds of times a second; four updates a second is plenty for people (and keeps the UI free).
        let finished = (j["status"] as? String) == "finished"
        guard finished || Date().timeIntervalSince(lastEmit) >= 0.25 else { return nil }
        lastEmit = Date()
        let overall = completed + downloaded
        let sum = expectedTotal.map { max($0, overall) }
        return .progress(downloaded: overall, total: sum ?? total.map { completed + $0 },
                         speed: (j["speed"] as? NSNumber)?.doubleValue, eta: (j["eta"] as? NSNumber)?.doubleValue)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

/// Finder metadata on finished files: the standard "Where from" (the page address) and a Digby note.
public enum FinderMetadata {
    public static func mark(_ file: URL, source: URL, summary: String) {
        if let plist = try? PropertyListSerialization.data(fromPropertyList: [source.absoluteString], format: .binary, options: 0) {
            setAttr(file, "com.apple.metadata:kMDItemWhereFroms", plist)
        }
        if let json = try? JSONSerialization.data(withJSONObject: ["app": "Digby Video Downloader", "summary": summary]) {
            setAttr(file, "app.digbyvideo.downloader", json)
        }
    }
    static func setAttr(_ file: URL, _ name: String, _ data: Data) {
        _ = file.withUnsafeFileSystemRepresentation { p in data.withUnsafeBytes { b in setxattr(p, name, b.baseAddress, data.count, 0, 0) } }
    }
}
