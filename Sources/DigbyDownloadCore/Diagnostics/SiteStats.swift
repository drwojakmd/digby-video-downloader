import Foundation

/// One try at a site, as kept on this Mac: the site's domain, never the link, the title or anything about you.
public struct SiteAttempt: Codable, Sendable, Hashable {
    public var site: String              // "youtube.com"
    public var date: Date
    public var succeeded: Bool
    public var failure: Failure.Kind?
    public var engine: String?           // the yt-dlp version that ran
    public init(site: String, date: Date = Date(), succeeded: Bool, failure: Failure.Kind? = nil, engine: String?) {
        self.site = site; self.date = date; self.succeeded = succeeded; self.failure = succeeded ? nil : failure; self.engine = engine
    }
}

/// One line of the per-site table.
public struct SiteStatsRow: Sendable, Hashable, Identifiable {
    public var site: String
    public var attempts: Int
    public var successes: Int
    public var failures: [Failure.Kind: Int]
    public var lastAttempt: Date
    public var lastWorkingEngine: String?
    public var lastFailingEngine: String?
    public var id: String { site }
    public var successRate: Double { attempts == 0 ? 0 : Double(successes) / Double(attempts) }
    /// The most frequent problem (ties go to the one named first alphabetically, so it's stable).
    public var commonFailure: Failure.Kind? {
        failures.max { a, b in a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue }?.key
    }
}

public enum SiteStats {
    /// The site key used for counting (the domain, e.g. "bbc.co.uk"); nil for links without one.
    public static func site(for url: URL) -> String? { SiteKey.of(url) }

    /// Rows, busiest site first.
    public static func summarise(_ events: [SiteAttempt]) -> [SiteStatsRow] {
        var rows: [String: SiteStatsRow] = [:]
        for e in events.sorted(by: { $0.date < $1.date }) {
            var r = rows[e.site] ?? SiteStatsRow(site: e.site, attempts: 0, successes: 0, failures: [:], lastAttempt: e.date)
            r.attempts += 1
            r.lastAttempt = e.date
            if e.succeeded { r.successes += 1; r.lastWorkingEngine = e.engine ?? r.lastWorkingEngine }
            else { r.failures[e.failure ?? .unknown, default: 0] += 1; r.lastFailingEngine = e.engine ?? r.lastFailingEngine }
            rows[e.site] = r
        }
        return rows.values.sorted { $0.attempts != $1.attempts ? $0.attempts > $1.attempts : $0.site < $1.site }
    }

    /// A plain-text summary for you to share if you choose. Sites and counts only: no links, titles, dates of
    /// individual downloads, file names or account details. Nothing is sent anywhere by Digby.
    public static func report(_ rows: [SiteStatsRow], appVersion: String, engines: [ToolID: String],
                              channel: UpdateChannel, lastEngineUpdate: UpdateRecord?) -> String {
        var lines = ["Digby Video Downloader \(appVersion) — site success summary",
                     "Counts per site from this Mac. No links, titles or account details are included.",
                     "yt-dlp \(engines[.ytdlp] ?? "not installed") (\(channel.label) channel)"]
        if let u = lastEngineUpdate {
            lines.append("Last engine update: \(u.tool.displayName) \(u.from.map { "\($0) → " } ?? "")\(u.to), \(u.date.formatted(.iso8601.year().month().day()))")
        }
        lines.append("")
        lines.append("site | tries | worked | rate | usual problem | last worked with | last failed with")
        for r in rows {
            lines.append([r.site, "\(r.attempts)", "\(r.successes)", "\(Int((r.successRate * 100).rounded()))%",
                          r.commonFailure?.rawValue ?? "-", r.lastWorkingEngine ?? "-", r.lastFailingEngine ?? "-"].joined(separator: " | "))
        }
        if rows.isEmpty { lines.append("(nothing downloaded yet)") }
        return Redactor.redact(lines.joined(separator: "\n"))
    }
}

/// The attempts, in a small JSON file beside the history. Capped (newest 5,000, last 365 days).
public final class SiteStatsStore: @unchecked Sendable {
    public static let maxEvents = 5000
    public static let maxAge: TimeInterval = 365 * 24 * 3600
    let file: URL
    private let lock = NSLock()
    private var events: [SiteAttempt]

    public init(file: URL = Paths.home.appendingPathComponent("site-stats.json")) {
        self.file = file
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        events = (try? Data(contentsOf: file)).flatMap { try? dec.decode([SiteAttempt].self, from: $0) } ?? []
    }

    public func record(_ a: SiteAttempt, now: Date = Date()) {
        guard a.failure != .cancelled else { return }
        lock.lock(); defer { lock.unlock() }
        events.append(a)
        events.removeAll { now.timeIntervalSince($0.date) > Self.maxAge }
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
        save()
    }
    public func all() -> [SiteAttempt] { lock.lock(); defer { lock.unlock() }; return events }
    public func clear() { lock.lock(); defer { lock.unlock() }; events = []; save() }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(events).write(to: file, options: .atomic)
    }
}
