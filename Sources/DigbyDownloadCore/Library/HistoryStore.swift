import Foundation
import SQLite3

/// One finished (or failed) download, as remembered in History.
public struct HistoryEntry: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var site: String
    public var url: URL
    public var date: Date
    public var file: URL?
    public var kind: DownloadKind
    public var detail: String          // "1080p · H.264 · AAC · MP4", or the failure title
    public var bytes: Int64
    public var succeeded: Bool
    public var thumbnail: URL?
    public var choices: Choices?       // to download again the same way
    public var details: DownloadDetails?   // the original, the choices and the verified result
    public init(id: String = UUID().uuidString, title: String, site: String, url: URL, date: Date = Date(), file: URL?, kind: DownloadKind,
                detail: String, bytes: Int64, succeeded: Bool, thumbnail: URL? = nil, choices: Choices? = nil, details: DownloadDetails? = nil) {
        self.id = id; self.title = title; self.site = site; self.url = url; self.date = date; self.file = file; self.kind = kind
        self.detail = detail; self.bytes = bytes; self.succeeded = succeeded; self.thumbnail = thumbnail; self.choices = choices; self.details = details
    }
}

/// Persistent, searchable download history in SQLite (Application Support/History.sqlite).
/// Removing a record never touches the downloaded file.
public final class HistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public static let schemaVersion = 2

    public init(file: URL = Paths.home.appendingPathComponent("History.sqlite")) throws {
        try Paths.ensure(file.deletingLastPathComponent())
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Failure(kind: .permissions, title: "History couldn’t be opened", explanation: "Digby can’t write to its Application Support folder.",
                          retryable: false, suggestsEngineUpdate: false, detail: String(cString: sqlite3_errmsg(db)))
        }
        try migrate()
    }
    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "?"; sqlite3_free(err)
            throw Failure(kind: .unknown, title: "History error", explanation: msg, retryable: false, suggestsEngineUpdate: false, detail: msg)
        }
    }

    private func migrate() throws {
        try exec("PRAGMA journal_mode=WAL;")
        var version: Int32 = 0
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW { version = sqlite3_column_int(st, 0) }
        sqlite3_finalize(st)
        if version < 1 {
            try exec("""
            CREATE TABLE IF NOT EXISTS downloads (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, site TEXT NOT NULL, url TEXT NOT NULL, date REAL NOT NULL,
              file TEXT, kind TEXT NOT NULL, detail TEXT NOT NULL, bytes INTEGER NOT NULL, succeeded INTEGER NOT NULL,
              thumbnail TEXT, choices TEXT);
            CREATE INDEX IF NOT EXISTS downloads_date ON downloads(date DESC);
            PRAGMA user_version = 1;
            """)
            version = 1
        }
        if version < 2 {
            try exec("ALTER TABLE downloads ADD COLUMN details TEXT; PRAGMA user_version = 2;")
        }
    }

    public func add(_ e: HistoryEntry) {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO downloads (id,title,site,url,date,file,kind,detail,bytes,succeeded,thumbnail,choices,details) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)    // SQLITE_TRANSIENT
        func text(_ i: Int32, _ s: String?) { if let s { sqlite3_bind_text(st, i, s, -1, T) } else { sqlite3_bind_null(st, i) } }
        text(1, e.id); text(2, e.title); text(3, e.site); text(4, e.url.absoluteString)
        sqlite3_bind_double(st, 5, e.date.timeIntervalSince1970)
        text(6, e.file?.path); text(7, e.kind.rawValue); text(8, e.detail)
        sqlite3_bind_int64(st, 9, e.bytes); sqlite3_bind_int(st, 10, e.succeeded ? 1 : 0)
        text(11, e.thumbnail?.absoluteString)
        text(12, e.choices.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) })
        text(13, e.details.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) })
        sqlite3_step(st)
    }

    /// Newest first. `search` matches title, site and link; `kind`/`succeeded` filter.
    public func entries(search: String = "", kind: DownloadKind? = nil, audioOnly: Bool? = nil, succeeded: Bool? = nil, limit: Int = 500) -> [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        var clauses: [String] = [], binds: [String] = []
        if !search.isEmpty { clauses.append("(title LIKE ? ESCAPE '\\' OR site LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\')")
            let q = "%" + search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
            binds += [q, q, q] }
        if let kind { clauses.append("kind = ?"); binds.append(kind.rawValue) }
        if let audioOnly { clauses.append(audioOnly ? "kind = 'audioOnly'" : "kind != 'audioOnly'") }
        if let succeeded { clauses.append("succeeded = \(succeeded ? 1 : 0)") }
        let sql = "SELECT id,title,site,url,date,file,kind,detail,bytes,succeeded,thumbnail,choices,details FROM downloads"
            + (clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")) + " ORDER BY date DESC LIMIT \(limit)"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in binds.enumerated() { sqlite3_bind_text(st, Int32(i + 1), b, -1, T) }
        var out: [HistoryEntry] = []
        func col(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
        while sqlite3_step(st) == SQLITE_ROW {
            guard let id = col(0), let title = col(1), let site = col(2), let u = col(3).flatMap(URL.init(string:)) else { continue }
            out.append(HistoryEntry(id: id, title: title, site: site, url: u, date: Date(timeIntervalSince1970: sqlite3_column_double(st, 4)),
                                    file: col(5).map { URL(fileURLWithPath: $0) }, kind: col(6).flatMap(DownloadKind.init(rawValue:)) ?? .videoAndAudio,
                                    detail: col(7) ?? "", bytes: sqlite3_column_int64(st, 8), succeeded: sqlite3_column_int(st, 9) == 1,
                                    thumbnail: col(10).flatMap(URL.init(string:)),
                                    choices: col(11).flatMap { try? JSONDecoder().decode(Choices.self, from: Data($0.utf8)) },
                                    details: col(12).flatMap { try? JSONDecoder().decode(DownloadDetails.self, from: Data($0.utf8)) }))
        }
        return out
    }

    /// Removes the record only; the file stays where it is.
    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM downloads WHERE id = ?", -1, &st, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(st, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(st); sqlite3_finalize(st)
    }

    public var count: Int { entries(limit: 1_000_000).count }
}
