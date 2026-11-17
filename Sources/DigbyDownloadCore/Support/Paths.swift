import Foundation

/// Where the app keeps things. `DIGBY_DL_HOME` relocates everything (tests and the CLI use it).
public enum Paths {
    public static var home: URL {
        if let h = ProcessInfo.processInfo.environment["DIGBY_DL_HOME"] { return URL(fileURLWithPath: h, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Digby Video Downloader", isDirectory: true)
    }
    /// Managed engines: Tools/<tool>/<version>/…, with Tools/<tool>/current → active version.
    public static var tools: URL { home.appendingPathComponent("Tools", isDirectory: true) }
    public static var logs: URL {
        if ProcessInfo.processInfo.environment["DIGBY_DL_HOME"] != nil { return home.appendingPathComponent("Logs", isDirectory: true) }
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Digby Video Downloader", isDirectory: true)
    }
    public static var downloadsTemp: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DigbyVideoDownloader", isDirectory: true)
    }
    /// `DIGBY_DL_DOWNLOADS` redirects downloads (tests).
    static var testDownloads: URL? { ProcessInfo.processInfo.environment["DIGBY_DL_DOWNLOADS"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
    public static var defaultVideoFolder: URL {
        if let t = testDownloads { return t.appendingPathComponent("Video", isDirectory: true) }
        return mediaFolder(.moviesDirectory)
    }
    public static var defaultAudioFolder: URL {
        if let t = testDownloads { return t.appendingPathComponent("Audio", isDirectory: true) }
        return mediaFolder(.musicDirectory)
    }
    /// ~/Movies/Digby (or ~/Music/Digby).
    static func mediaFolder(_ dir: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: dir, in: .userDomainMask)[0].appendingPathComponent("Digby", isDirectory: true)
    }
    @discardableResult
    public static func ensure(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Removes things that must never appear in logs or diagnostic reports.
public enum Redactor {
    public static func redact(_ s: String) -> String {
        var out = s
        // Home folder (contains the account name).
        out = out.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        // Query strings carry signatures, tokens and session ids.
        if let re = try? NSRegularExpression(pattern: #"(https?://[^\s"'?]+)\?[^\s"']*"#) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1?…")
        }
        // Cookie and authorisation headers or values.
        for pattern in [#"(?i)(cookie|authorization|set-cookie)\s*[:=]\s*[^\n]+"#, #"(?i)(SAPISID|__Secure-[A-Za-z0-9_-]+|SID|HSID|SSID)=[^;\s]+"#] {
            if let re = try? NSRegularExpression(pattern: pattern) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1=[removed]")
            }
        }
        return out
    }
}

/// Engine log: ~/Library/Logs/Digby Video Downloader/engine.log (redacted, rotated at 5 MB).
public enum Log {
    private static let queue = DispatchQueue(label: "digby.log")
    public static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(Redactor.redact(message))\n"
        queue.async {
            guard let dir = try? Paths.ensure(Paths.logs) else { return }
            let file = dir.appendingPathComponent("engine.log")
            if let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int, size > 5_000_000 {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("engine.1.log"))
                try? FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("engine.1.log"))
            }
            if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? Data(line.utf8).write(to: file) }
        }
    }
}
