import Foundation

/// What happened to each job in the session before the app was last closed (quit, force quit,
/// crash or restart), shown once on reopening.
public enum LastSessionOutcome: String, Codable, Sendable { case finished, stopped, failed, cancelled }

public struct LastSessionItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var outcome: LastSessionOutcome
    /// The plain reason (failed), or what it was doing (stopped).
    public var reason: String?
    /// Stopped or failed jobs whose file is still there can be started again.
    public var canResume: Bool
    public init(id: String, name: String, outcome: LastSessionOutcome, reason: String? = nil, canResume: Bool = false) {
        self.id = id; self.name = name; self.outcome = outcome; self.reason = reason; self.canResume = canResume
    }
}

public struct LastSessionReport: Sendable, Equatable {
    public var items: [LastSessionItem]
    public var noun: String          // "video", "download"
    public init(items: [LastSessionItem], noun: String) { self.items = items; self.noun = noun }

    public func count(_ o: LastSessionOutcome) -> Int { items.filter { $0.outcome == o }.count }
    /// Shown only when something was left undone.
    public var worthShowing: Bool { count(.stopped) + count(.failed) > 0 }
    public var resumable: [LastSessionItem] { items.filter { $0.outcome == .stopped && $0.canResume } }

    func plural(_ n: Int) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// "Digby closed before 2 videos were done." / "1 download didn’t finish last time."
    public var headline: String {
        let s = count(.stopped)
        if s > 0 { return "Digby closed before \(plural(s)) \(s == 1 ? "was" : "were") done." }
        let f = count(.failed)
        return "\(plural(f)) didn’t finish last time."
    }
    /// "3 finished · 2 stopped · 1 failed" (empty kinds left out).
    public var tally: String {
        [(LastSessionOutcome.finished, "finished"), (.stopped, "stopped"), (.failed, "failed"), (.cancelled, "cancelled")]
            .compactMap { count($0.0) > 0 ? "\(count($0.0)) \($0.1)" : nil }
            .joined(separator: " · ")
    }
}

/// Engines left running by a run that was force quit or crashed.
public enum Leftovers {
    /// Stops processes started from Digby's own engines folder whose parent is gone (adopted by launchd),
    /// with their process groups (each engine run is its own group). Returns how many.
    @discardableResult
    public static func stopOrphans(under folder: URL) -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,comm="]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return 0 }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        let pids = orphanPIDs(psOutput: out, under: folder.standardizedFileURL.path)
        for pid in pids { kill(-pid, SIGKILL); kill(pid, SIGKILL) }
        return pids.count
    }

    /// Parses `ps -axo pid=,ppid=,comm=` for orphans whose executable is inside `folder`.
    public static func orphanPIDs(psOutput: String, under folder: String) -> [pid_t] {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return psOutput.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = pid_t(parts[0]), parts[1] == "1",
                  parts[2].trimmingCharacters(in: .whitespaces).hasPrefix(prefix) else { return nil }
            return pid
        }
    }

    /// Removes the kept partial data (".digby-download-<id>" folders) of exactly these downloads, in these
    /// folders and the folders one level down (downloads sorted by month, site or channel). Others are untouched.
    @discardableResult
    public static func removeWork(ids: Set<String>, in folders: [URL]) -> Int {
        guard !ids.isEmpty else { return 0 }
        let fm = FileManager.default
        var dirs = folders
        for f in folders {
            for sub in (try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !sub.lastPathComponent.hasPrefix(".") { dirs.append(sub) }
        }
        var n = 0
        for d in dirs { for id in ids {
            let w = d.appendingPathComponent(".digby-download-\(id)", isDirectory: true)
            if fm.fileExists(atPath: w.path), (try? fm.removeItem(at: w)) != nil { n += 1 }
        } }
        return n
    }
}
