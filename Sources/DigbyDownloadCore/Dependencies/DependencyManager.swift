import Foundation

public struct InstalledTool: Codable, Sendable, Hashable {
    public var tool: ToolID
    public var version: String
    public var installedAt: Date
    public var sha256: String
    public var source: String
    public var previousVersion: String?
    public var previousSource: String? = nil
}

public struct UpdateRecord: Codable, Sendable, Hashable {
    public var date: Date
    public var tool: ToolID
    public var from: String?
    public var to: String
    public var outcome: String       // "installed", "rolled back", "failed: …"
    public init(date: Date, tool: ToolID, from: String?, to: String, outcome: String) {
        self.date = date; self.tool = tool; self.from = from; self.to = to; self.outcome = outcome
    }
}

public struct InstallProgress: Sendable {
    public var tool: ToolID
    public var step: String
    public var fraction: Double?
}

/// Installs, verifies, updates and rolls back the engines in Application Support.
/// An install either completes fully (verified, test-run, switched in atomically) or leaves the
/// previous version active.
public actor DependencyManager {
    public static let shared = DependencyManager()

    struct Manifest: Codable {
        var tools: [ToolID: InstalledTool] = [:]
        var history: [UpdateRecord] = []
        var lastCheck: Date? = nil
        var latestKnown: [ToolID: String]? = nil
        /// The quick, frequent yt-dlp check (schedule and backoff).
        var extractorCheck: CheckState? = nil
        /// The installed yt-dlp is a nightly fetched to fix a broken site while on Stable.
        var recoveryNightly: Bool? = nil
    }
    private var manifest = Manifest()

    public init() { manifest = Self.loadManifest() }

    // MARK: Paths (safe to use from anywhere)

    /// A folder of links to the active engines: what yt-dlp is pointed at.
    public nonisolated static var binDirectory: URL { Paths.tools.appendingPathComponent("bin", isDirectory: true) }
    public nonisolated static func executable(_ t: ToolID) -> URL { binDirectory.appendingPathComponent(t.rawValue) }
    nonisolated static var manifestURL: URL { Paths.tools.appendingPathComponent("manifest.json") }

    static func loadManifest() -> Manifest {
        guard let d = try? Data(contentsOf: manifestURL) else { return Manifest() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Manifest.self, from: d)) ?? Manifest()
    }
    func saveManifest() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Paths.ensure(Paths.tools)
        try enc.encode(manifest).write(to: Self.manifestURL, options: .atomic)
    }

    // MARK: State

    public func installed() -> [ToolID: InstalledTool] {
        manifest.tools.filter { FileManager.default.isExecutableFile(atPath: Self.executable($0.key).path) }
    }
    public func history() -> [UpdateRecord] { manifest.history }
    public var isReady: Bool { ToolID.allCases.allSatisfy { installed()[$0] != nil } }
    public func missing() -> [ToolID] { ToolID.allCases.filter { installed()[$0] == nil } }

    public var lastCheck: Date? { manifest.lastCheck }
    public var latestKnown: [ToolID: String] { manifest.latestKnown ?? [:] }

    /// Asks each official source for its newest version. Returns the releases newer than what's installed.
    public func checkForUpdates(channel: UpdateChannel) async -> [ToolRelease] {
        var newer: [ToolRelease] = [], known = manifest.latestKnown ?? [:]
        for t in ToolID.allCases {
            guard let r = try? await ReleaseSources.latest(t, channel: channel) else { continue }
            known[t] = r.version
            if let have = manifest.tools[t]?.version {
                let wanted = t == .ytdlp ? EngineChoice.shouldInstall(r.version, over: have, channel: channel, recoveryNightly: recoveryNightly)
                                         : Version.isNewer(r.version, than: have)
                if !wanted { continue }
            }
            newer.append(r)
        }
        manifest.lastCheck = Date(); manifest.latestKnown = known
        if known[.ytdlp] != nil { var c = manifest.extractorCheck ?? CheckState(); c.succeeded(at: Date()); manifest.extractorCheck = c }
        try? saveManifest()
        Log.write("update check (\(channel.rawValue)): \(newer.isEmpty ? "all current" : newer.map { "\($0.tool.rawValue) \($0.version)" }.joined(separator: ", "))")
        return newer
    }

    public var extractorCheck: CheckState { manifest.extractorCheck ?? CheckState() }
    public var recoveryNightly: Bool { manifest.recoveryNightly ?? false }
    public func setRecoveryNightly(_ on: Bool) { manifest.recoveryNightly = on; try? saveManifest() }

    /// The quick check, every few hours: one request for yt-dlp's newest release name. Only when that's worth
    /// installing are the signed checksums fetched (the full, verified release is returned).
    public func checkExtractor(channel: UpdateChannel, now: Date = Date()) async -> ToolRelease? {
        var c = manifest.extractorCheck ?? CheckState()
        do {
            let tag = try await ReleaseSources.latestTag(.ytdlp, channel: channel)
            c.succeeded(at: now)
            var known = manifest.latestKnown ?? [:]; known[.ytdlp] = tag; manifest.latestKnown = known
            manifest.extractorCheck = c; try? saveManifest()
            guard EngineChoice.shouldInstall(tag, over: manifest.tools[.ytdlp]?.version, channel: channel, recoveryNightly: recoveryNightly) else { return nil }
            Log.write("quick check (\(channel.rawValue)): yt-dlp \(tag) available")
            return try await ReleaseSources.latest(.ytdlp, channel: channel)
        } catch {
            c.failed(at: now); manifest.extractorCheck = c; try? saveManifest()
            Log.write("quick check failed (\(c.failures) in a row): \(error)")
            return nil
        }
    }

    public func latest(_ tool: ToolID, channel: UpdateChannel) async throws -> ToolRelease {
        try await ReleaseSources.latest(tool, channel: channel)
    }

    /// Installs anything missing. Engines install one after another, each fully verified.
    public func ensureInstalled(channel: UpdateChannel = .stable, progress: @escaping @Sendable (InstallProgress) -> Void) async throws {
        for tool in missing() {
            progress(InstallProgress(tool: tool, step: "Finding the latest \(tool.displayName)", fraction: nil))
            let release = try await latest(tool, channel: channel)
            try await install(release, progress: progress)
        }
    }

    /// Download → verify checksum (and signature/Developer ID) → unpack → test-run → switch in.
    public func install(_ r: ToolRelease, progress: @escaping @Sendable (InstallProgress) -> Void) async throws {
        let fm = FileManager.default
        // Two callers (a background update and a recovery) can ask for the same release; the actor runs them
        // one after the other, so the second finds it already in place and does nothing.
        if manifest.tools[r.tool]?.version == r.version, manifest.tools[r.tool]?.sha256 == r.sha256.lowercased(),
           fm.isExecutableFile(atPath: Self.executable(r.tool).path) { return }
        let staging = try Paths.ensure(Paths.tools.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true))
        defer { try? fm.removeItem(at: staging) }
        let previous = manifest.tools[r.tool]
        do {
            // 1. Download
            let archive = staging.appendingPathComponent(r.archive.lastPathComponent)
            // A connection can stall without ever timing out; the watchdog cancels it and we try again (twice).
            var attempt = 0
            while true {
                do {
                    try await FileDownloader.download(r.archive, to: archive) { f in
                        progress(InstallProgress(tool: r.tool, step: "Downloading \(r.tool.displayName) \(r.version)", fraction: f))
                    }
                    break
                } catch {
                    attempt += 1
                    Log.write("download of \(r.tool.rawValue) failed (attempt \(attempt)): \(error)")
                    if attempt >= 3 { throw error }
                    progress(InstallProgress(tool: r.tool, step: "The connection stalled; trying \(r.tool.displayName) again", fraction: nil))
                }
            }
            // 2. Checksum from the verified source
            progress(InstallProgress(tool: r.tool, step: "Checking \(r.tool.displayName) is genuine", fraction: nil))
            let actual = try Verify.sha256(of: archive)
            guard actual == r.sha256.lowercased() else {
                throw DependencyError.verification("\(r.tool.displayName) checksum doesn’t match (expected \(r.sha256.prefix(12))…, got \(actual.prefix(12))…)")
            }
            // 3. Unpack (ditto keeps signatures and permissions intact)
            let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
            let unzip = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, unpacked.path])
            guard unzip.succeeded else { throw DependencyError.install("couldn’t unpack \(archive.lastPathComponent)") }
            let exe = unpacked.appendingPathComponent(r.tool.executable)
            guard fm.isExecutableFile(atPath: exe.path) else { throw DependencyError.install("\(r.tool.executable) missing from the archive") }
            // 4. Developer ID (where the publisher signs their binaries)
            if let team = r.tool.pinnedTeam { try Verify.developerID(exe, team: team) }
            // 5. Test-run before it's trusted with anything
            progress(InstallProgress(tool: r.tool, step: "Testing \(r.tool.displayName)" + (r.tool == .ytdlp ? " (the first start takes a moment)" : ""), fraction: nil))
            let smoke = try await Self.runWithTimeout(exe, r.tool.versionArguments, timeout: r.tool.smokeTimeout)
            guard smoke.succeeded, !smoke.stdout.isEmpty else { throw DependencyError.install("\(r.tool.displayName) didn’t run: \(smoke.stderr.prefix(200))") }
            // 6. Move into place and switch the active link atomically
            let toolDir = try Paths.ensure(Paths.tools.appendingPathComponent(r.tool.rawValue, isDirectory: true))
            let versionDir = toolDir.appendingPathComponent(r.version, isDirectory: true)
            if fm.fileExists(atPath: versionDir.path) { try fm.removeItem(at: versionDir) }
            try fm.moveItem(at: unpacked, to: versionDir)
            try Self.switchLink(toolDir.appendingPathComponent("current"), to: versionDir)
            try Self.switchLink(Self.executable(r.tool), to: toolDir.appendingPathComponent("current/\(r.tool.executable)"))
            // 7. Record; keep only the active and previous versions
            let prevVersion = previous?.version == r.version ? previous?.previousVersion : previous?.version
            manifest.tools[r.tool] = InstalledTool(tool: r.tool, version: r.version, installedAt: Date(), sha256: actual, source: r.source,
                                                   previousVersion: prevVersion,
                                                   previousSource: previous?.version == r.version ? previous?.previousSource : previous?.source)
            manifest.history.append(UpdateRecord(date: Date(), tool: r.tool, from: previous?.version, to: r.version, outcome: "installed"))
            if r.tool == .ytdlp { manifest.recoveryNightly = false }    // a recovery marks its nightly afterwards
            try saveManifest()
            Self.prune(toolDir, keep: [r.version, prevVersion].compactMap { $0 })
            Log.write("installed \(r.tool.rawValue) \(r.version) from \(r.source)")
        } catch {
            manifest.history.append(UpdateRecord(date: Date(), tool: r.tool, from: previous?.version, to: r.version, outcome: "failed: \(error)"))
            try? saveManifest()
            Log.write("install \(r.tool.rawValue) \(r.version) failed: \(error)")
            throw error
        }
    }

    /// Switches back to the previously installed version.
    public func rollback(_ tool: ToolID) throws {
        guard var cur = manifest.tools[tool], let prev = cur.previousVersion else { throw DependencyError.install("no earlier \(tool.displayName) to go back to") }
        let toolDir = Paths.tools.appendingPathComponent(tool.rawValue, isDirectory: true)
        let prevDir = toolDir.appendingPathComponent(prev, isDirectory: true)
        guard FileManager.default.fileExists(atPath: prevDir.path) else { throw DependencyError.install("the earlier version’s files are missing") }
        try Self.switchLink(toolDir.appendingPathComponent("current"), to: prevDir)
        manifest.history.append(UpdateRecord(date: Date(), tool: tool, from: cur.version, to: prev, outcome: "rolled back"))
        let from = cur.version, fromSource = cur.source
        cur.version = prev; cur.previousVersion = from; cur.installedAt = Date()
        cur.source = cur.previousSource ?? "earlier install"; cur.previousSource = fromSource
        manifest.tools[tool] = cur
        try saveManifest()
        Log.write("rolled back \(tool.rawValue) \(from) → \(prev)")
    }

    // MARK: Helpers

    /// Replace a symbolic link atomically (create beside it, then rename over it).
    static func switchLink(_ link: URL, to target: URL) throws {
        try Paths.ensure(link.deletingLastPathComponent())
        let tmp = link.deletingLastPathComponent().appendingPathComponent(".\(link.lastPathComponent).\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: tmp, withDestinationURL: target)
        guard rename(tmp.path, link.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw DependencyError.install("couldn’t switch \(link.lastPathComponent)")
        }
    }

    static func prune(_ toolDir: URL, keep: [String]) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: toolDir.path)) ?? [] where name != "current" && !name.hasPrefix(".") && !keep.contains(name) {
            try? fm.removeItem(at: toolDir.appendingPathComponent(name))
        }
    }

    static func runWithTimeout(_ exe: URL, _ args: [String], timeout: TimeInterval) async throws -> ProcessResult {
        var handle: RunningProcess?
        let timer = DispatchWorkItem { handle?.cancel(grace: 1) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }
        return try await ProcessRunner.run(exe, args, started: { handle = $0 })
    }
}

/// URLSession download with progress, into a chosen file.
enum FileDownloader {
    static func download(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let dest: URL; let progress: @Sendable (Double?) -> Void
            var cont: CheckedContinuation<Void, Error>?
            var moveError: Error?
            var lastActivity = Date()
            init(dest: URL, progress: @escaping @Sendable (Double?) -> Void) { self.dest = dest; self.progress = progress }
            func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
                lastActivity = Date()
                progress(t > 0 ? Double(w) / Double(t) : nil)
            }
            func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                if let h = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    moveError = DependencyError.network("HTTP \(h.statusCode) downloading \(dest.lastPathComponent)"); return
                }
                do { try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: location, to: dest) }
                catch { moveError = error }
            }
            func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error { cont?.resume(throwing: DependencyError.network(error.localizedDescription)) }
                else if let moveError { cont?.resume(throwing: moveError) }
                else { cont?.resume() }
                cont = nil
                s.finishTasksAndInvalidate()
            }
        }
        let d = Delegate(dest: dest, progress: progress)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpAdditionalHeaders = ["User-Agent": "DigbyVideoDownloader"]
        cfg.timeoutIntervalForRequest = 45
        cfg.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: cfg, delegate: d, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        // Watchdog: no new bytes for 45 s → cancel (didCompleteWithError then reports it).
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 15, repeating: 15)
        watchdog.setEventHandler { if Date().timeIntervalSince(d.lastActivity) > 45 { task.cancel() } }
        watchdog.resume()
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            d.cont = c
            task.resume()
        }
    }
}
