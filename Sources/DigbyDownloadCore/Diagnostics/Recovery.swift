import Foundation

/// Compares engine versions: yt-dlp dates ("2026.10.26", nightly "2026.11.04.232659"), Deno ("2.9.8"), FFmpeg ("9.0.2").
public enum Version {
    public static func components(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
    /// True when `a` is newer than `b`.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

/// When to look for engine updates. The extraction engine (yt-dlp, the part that breaks when a site changes) is
/// asked every few hours with one small request; all engines get a full check daily on Stable. A check that
/// fails (offline, server trouble) is retried sooner but backs off: 15 min, 30 min, 1 h … up to the usual interval.
public enum UpdateSchedule {
    /// The full check of every engine.
    public static func interval(_ c: UpdateChannel) -> TimeInterval { c == .stable ? 24 * 3600 : 6 * 3600 }
    public static func isDue(lastCheck: Date?, channel: UpdateChannel, now: Date = Date()) -> Bool {
        guard let last = lastCheck else { return true }
        return now.timeIntervalSince(last) >= interval(channel)
    }

    /// The quick yt-dlp check (one request for the newest release's name).
    public static func extractorInterval(_ c: UpdateChannel) -> TimeInterval { c == .stable ? 4 * 3600 : 2 * 3600 }
    public static let firstBackoff: TimeInterval = 15 * 60
    /// How long to wait after `failures` failed checks in a row (0 when none have failed).
    public static func backoff(failures: Int, cap: TimeInterval) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(firstBackoff * pow(2, Double(min(failures - 1, 20))), cap)
    }
    /// When the next quick check should run.
    public static func nextExtractorCheck(_ s: CheckState, channel: UpdateChannel) -> Date {
        let every = extractorInterval(channel)
        if s.failures > 0, let a = s.lastAttempt { return a.addingTimeInterval(backoff(failures: s.failures, cap: every)) }
        guard let ok = s.lastSuccess else { return .distantPast }
        return ok.addingTimeInterval(every)
    }
    public static func isExtractorDue(_ s: CheckState, channel: UpdateChannel, now: Date = Date()) -> Bool {
        now >= nextExtractorCheck(s, channel: channel)
    }
    /// How often the app wakes to see whether a check is due (a check itself only runs when due).
    public static let tick: TimeInterval = 15 * 60
}

/// The record behind the quick check's schedule and backoff.
public struct CheckState: Codable, Sendable, Hashable {
    public var lastSuccess: Date?
    public var lastAttempt: Date?
    public var failures: Int
    public init(lastSuccess: Date? = nil, lastAttempt: Date? = nil, failures: Int = 0) {
        self.lastSuccess = lastSuccess; self.lastAttempt = lastAttempt; self.failures = failures
    }
    public mutating func succeeded(at d: Date) { lastSuccess = d; lastAttempt = d; failures = 0 }
    public mutating func failed(at d: Date) { lastAttempt = d; failures += 1 }
}

/// Whether a yt-dlp build is worth installing over the one in place.
public enum EngineChoice {
    static func isNightlyBuild(_ v: String) -> Bool { Version.components(v).count > 3 }   // nightlies carry a time part
    /// `recoveryNightly`: the installed nightly was fetched to fix a broken site while on Stable. It stays until
    /// a Stable release at least as new arrives, so the fix isn't undone by the next routine check.
    public static func shouldInstall(_ candidate: String, over installed: String?, channel: UpdateChannel, recoveryNightly: Bool) -> Bool {
        guard let installed else { return true }
        if channel == .stable, isNightlyBuild(installed) {
            guard recoveryNightly else { return true }        // you switched back to Stable: go back to a tested build
            let day = Version.components(installed).prefix(3).map(String.init).joined(separator: ".")
            return !Version.isNewer(day, than: candidate)
        }
        return Version.isNewer(candidate, than: installed)
    }
}

/// How far to go when a site seems to have changed: the newest build on your channel straight away; on
/// Stable, if that doesn't fix it, the Nightly build is offered (it's less tested, so you choose).
public enum EngineEscalation {
    public enum Step: Equatable, Sendable { case update(UpdateChannel), offerNightly, none }
    public static let siteChanged: Set<Failure.Kind> = [.outdatedExtractor, .jsRuntime]
    public static func next(after kind: Failure.Kind, userChannel: UpdateChannel, tried: Set<UpdateChannel>) -> Step {
        if !tried.contains(userChannel) { return .update(userChannel) }
        if siteChanged.contains(kind), userChannel == .stable, !tried.contains(.nightly) { return .offerNightly }
        return .none
    }
}

/// What to do after a failure. Pure and deterministic, so it's tested directly. Never retries forever,
/// never re-downloads finished files (resume continues partial data), never claims a fix it hasn't seen work.
public enum RecoveryPolicy {
    public enum Action: Equatable, Sendable {
        case retry(after: TimeInterval, reason: String)
        case updateEngineThenRetry
        case giveUp
    }
    public static let maxAttempts = 3

    /// `attempt` is how many times this job has already failed (1 after the first failure).
    /// `engineUpdateTried` is true once an engine update has been attempted for this job.
    public static func next(after f: Failure, attempt: Int, engineUpdateTried: Bool) -> Action {
        guard attempt < maxAttempts else { return .giveUp }
        switch f.kind {
        case .network:
            return .retry(after: attempt == 1 ? 5 : 30, reason: "The connection dropped")
        case .rateLimited:
            return .retry(after: attempt == 1 ? 60 : 300, reason: "The site asked Digby to slow down")
        case .outdatedExtractor, .jsRuntime:
            return engineUpdateTried ? .giveUp : .updateEngineThenRetry
        case .blocked, .unknown:
            // Sometimes a newer engine helps; otherwise one plain retry, then stop.
            if !engineUpdateTried { return .updateEngineThenRetry }
            return attempt == 1 ? .retry(after: 10, reason: "Trying once more") : .giveUp
        case .verificationFailed, .unsupportedFormat:
            return attempt == 1 ? .retry(after: 2, reason: "Trying once more") : .giveUp
        case .botCheck, .loginRequired, .privateMedia, .unavailable, .geoRestricted, .unsupportedSite, .drm,
             .diskFull, .permissions, .missingEngine, .cancelled:
            return .giveUp      // retrying can't help; the explanation says what can
        }
    }
}

/// Fetches a newer extraction engine when a site seems to have changed: the newest build on one channel,
/// installed only if it's newer and passes the signature check and test-run (`DependencyManager.install`).
/// `EngineEscalation` decides which channel to try.
public struct EngineRecovery: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var updated: Bool
        public var from: String?
        public var to: String?
        public var channel: UpdateChannel?
        public var message: String
    }
    /// The parts that reach the network or the disk; tests replace them.
    public struct Engine: Sendable {
        public var current: @Sendable () async -> String?
        public var recoveryNightly: @Sendable () async -> Bool
        public var latest: @Sendable (UpdateChannel) async throws -> ToolRelease
        public var install: @Sendable (ToolRelease, @escaping @Sendable (InstallProgress) -> Void) async throws -> Void
        public var markRecoveryNightly: @Sendable (Bool) async -> Void
        public init(current: @escaping @Sendable () async -> String?, recoveryNightly: @escaping @Sendable () async -> Bool,
                    latest: @escaping @Sendable (UpdateChannel) async throws -> ToolRelease,
                    install: @escaping @Sendable (ToolRelease, @escaping @Sendable (InstallProgress) -> Void) async throws -> Void,
                    markRecoveryNightly: @escaping @Sendable (Bool) async -> Void) {
            self.current = current; self.recoveryNightly = recoveryNightly; self.latest = latest; self.install = install; self.markRecoveryNightly = markRecoveryNightly
        }
        public static let live = Engine(
            current: { await DependencyManager.shared.installed()[.ytdlp]?.version },
            recoveryNightly: { await DependencyManager.shared.recoveryNightly },
            latest: { try await DependencyManager.shared.latest(.ytdlp, channel: $0) },
            install: { try await DependencyManager.shared.install($0, progress: $1) },
            markRecoveryNightly: { await DependencyManager.shared.setRecoveryNightly($0) })
    }
    let engine: Engine
    public init(engine: Engine = .live) { self.engine = engine }

    /// `userChannel` is the channel chosen in Settings; `channel` the one tried now (Nightly when escalating).
    public func updateExtractor(on channel: UpdateChannel, userChannel: UpdateChannel,
                                progress: @escaping @Sendable (InstallProgress) -> Void) async -> Outcome {
        let current = await engine.current()
        let label = channel == .stable ? "" : " \(channel.label.lowercased())"
        progress(InstallProgress(tool: .ytdlp, step: "Looking for the newest\(label) extraction engine", fraction: nil))
        let latest: ToolRelease
        do { latest = try await engine.latest(channel) }
        catch {
            return Outcome(updated: false, from: current, to: nil, channel: channel,
                           message: "Couldn’t reach the update server to look for a newer\(label) engine.")
        }
        let escalating = channel != userChannel
        let wanted = escalating ? (current.map { Version.isNewer(latest.version, than: $0) } ?? true)
                                : EngineChoice.shouldInstall(latest.version, over: current, channel: channel, recoveryNightly: await engine.recoveryNightly())
        guard wanted else {
            return Outcome(updated: false, from: current, to: nil, channel: channel,
                           message: "No newer\(label) extraction engine yet (yours is \(current ?? "unknown")).")
        }
        do {
            try await engine.install(latest, progress)
            await engine.markRecoveryNightly(escalating && channel != .stable)
            return Outcome(updated: true, from: current, to: latest.version, channel: channel,
                           message: "Updated the extraction engine from \(current ?? "none") to \(latest.version)" + (channel == .stable ? "." : " (a \(channel.label.lowercased()) build)."))
        } catch {
            return Outcome(updated: false, from: current, to: latest.version, channel: channel,
                           message: "Found a newer engine (\(latest.version)) but it didn’t pass its checks, so it wasn’t installed.")
        }
    }
}

/// A plain-text report for sharing when something goes wrong. Everything personal is removed first.
public enum DiagnosticReport {
    public static func make(failure: Failure, link: URL?, engines: [ToolID: InstalledTool], appVersion: String, extra: [String] = []) -> String {
        var lines = ["Digby Video Downloader \(appVersion) — diagnostic report",
                     "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(ProcessInfo.processInfo.machineArchitecture)",
                     "Problem: \(failure.kind.rawValue) — \(failure.title)"]
        if let link { lines.append("Site: \(link.host ?? "?")") }       // the site, never the full link
        for t in ToolID.allCases { lines.append("\(t.displayName): \(engines[t]?.version ?? "not installed")") }
        lines += extra
        lines.append("")
        lines.append("Engine said:")
        lines.append(failure.detail)
        lines.append("")
        lines.append("Recent log:")
        lines.append(recentLog())
        return Redactor.redact(lines.joined(separator: "\n"))
    }

    static func recentLog(lines n: Int = 40) -> String {
        let file = Paths.logs.appendingPathComponent("engine.log")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "(no log)" }
        return text.split(separator: "\n").suffix(n).joined(separator: "\n")
    }
}

extension ProcessInfo {
    var machineArchitecture: String {
        var u = utsname(); uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
    }
}
