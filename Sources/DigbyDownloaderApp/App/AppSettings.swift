import Foundation
import DigbyDownloadCore

/// Everything in Settings, saved as one versioned record. Queued downloads keep their own copy of the
/// choices they were added with, so changing these never alters them.
struct AppSettings: Codable, Equatable {
    // Off until asked for: Digby stays out of the way (new installs; saved settings keep your choice).
    var watchClipboard = false
    var showMenuBarIcon = false
    var notifyWhenDone = false
    var maxConcurrent = 2
    var perSite = 1
    var channel = "Stable"
    var nameTemplate = "{title} ({resolution})"
    var defaultProfileID = DownloadProfile.maximumQuality.id
    var videoFolder: String? = nil          // nil → ~/Movies/Digby
    var audioFolder: String? = nil          // nil → ~/Music/Digby
    var playlistSubfolders = true
    var customProfiles: [DownloadProfile] = []
    var installEngineUpdates: Bool? = true     // optional: older saved settings lack it
    var linksAsList: Bool? = false             // open links shown as a sidebar list instead of tabs
    /// 1.1 turned clipboard, menu bar and notifications off by default. Settings saved before that (only
    /// pre-release test installs) are switched off once, then left alone.
    var quietDefaults: Bool? = true
    /// Your own folders for downloads that belong together ("Kids' cartoons", "Research").
    var projects: [Project]? = nil
    /// Most bytes per second for all downloads together (nil: no limit).
    var speedLimit: Int? = nil
    /// Overnight hours, in minutes after midnight (default 1:00–7:00).
    var overnightStart: Int? = nil
    var overnightEnd: Int? = nil
    /// Every new download waits for the overnight hours.
    var alwaysOvernight: Bool? = nil
    /// Subfolders of the usual folders: by month, day, website or channel (nil: none).
    var folderSorting: FolderSorting? = nil
    /// Playing a page out of sight to catch its video, answered once per site (`SiteKey`): true = allowed,
    /// false = don't offer again. A site not listed hasn't been asked.
    var pageCatchSites: [String: Bool]? = nil
    /// Hand each finished video to Digby Video Compressor (nil: never chosen, so off).
    var compressAfter: CompressAfter? = nil

    static let key = "DigbyDownloader.settings.v1"
    static var persistent: Bool { ProcessInfo.processInfo.environment["DIGBY_DL_RENDER"] == nil }

    static func load() -> AppSettings {
        guard persistent, let d = UserDefaults.standard.data(forKey: key), var s = try? JSONDecoder().decode(AppSettings.self, from: d) else { return AppSettings() }
        if s.quietDefaults == nil {
            s.watchClipboard = false; s.showMenuBarIcon = false; s.notifyWhenDone = false; s.quietDefaults = true
            s.save()
        }
        return s
    }
    func save() {
        guard Self.persistent, let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(d, forKey: Self.key)
    }
}

/// A download that hadn't finished when Digby quit, to offer again next time.
struct PendingDownload: Codable {
    var url: URL
    var title: String
    var choices: Choices
    var playlist: String?
    var index: Int
    var workID: String
    var paused: Bool
    var folder: String? = nil       // a project's folder, when it had one
    // Added 2026-11 (absent in older files), for the summary shown on reopening:
    var stoppedNote: String? = nil  // "Was downloading" / "Was waiting its turn"; nil = paused by the user
    var failure: String? = nil      // the plain reason, when it had failed
    var compressAfter: CompressAfter? = nil

    static var file: URL { Paths.home.appendingPathComponent("Unfinished downloads.json") }
    static func load() -> [PendingDownload] {
        guard AppSettings.persistent, let d = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([PendingDownload].self, from: d)) ?? []
    }
    static func save(_ list: [PendingDownload]) {
        guard AppSettings.persistent else { return }
        if list.isEmpty { try? FileManager.default.removeItem(at: file); return }
        try? Paths.ensure(Paths.home)
        try? JSONEncoder().encode(list).write(to: file, options: .atomic)
    }
}

/// Downloads that finished or were cancelled in the same session as unfinished ones, so the reopen
/// summary can list them too. Written with "Unfinished downloads.json" and removed with it.
enum LastSessionLog {
    static var file: URL { Paths.home.appendingPathComponent("Last session.json") }
    static func load() -> [LastSessionItem] {
        guard AppSettings.persistent, let d = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([LastSessionItem].self, from: d)) ?? []
    }
    static func save(_ list: [LastSessionItem], unfinished: Bool) {
        guard AppSettings.persistent else { return }
        if !unfinished || list.isEmpty { try? FileManager.default.removeItem(at: file); return }
        try? Paths.ensure(Paths.home)
        try? JSONEncoder().encode(list).write(to: file, options: .atomic)
    }
}

/// A folder of your own for downloads that belong together. Everything saved into it is listed under the
/// project; the files are ordinary files in an ordinary folder.
struct Project: Codable, Identifiable, Hashable {
    var id = "project-" + UUID().uuidString.prefix(8)
    var name: String
    var folder: String
    var symbol: String = "folder.fill"
    var folderURL: URL { URL(fileURLWithPath: folder, isDirectory: true) }
    func contains(_ file: URL?) -> Bool {
        guard let f = file?.standardizedFileURL.path else { return false }
        return f.hasPrefix(folderURL.standardizedFileURL.path + "/")
    }
    static let symbols = ["folder.fill", "star.fill", "heart.fill", "graduationcap.fill", "music.note", "film.fill", "gamecontroller.fill",
                          "figure.and.child.holdinghands", "airplane", "book.fill", "briefcase.fill", "sparkles"]
}

/// A channel or playlist Digby checks for new videos while it's open.
struct Watch: Codable, Identifiable, Hashable {
    var id = "watch-" + UUID().uuidString.prefix(8)
    var url: URL
    var title: String
    var site: String
    var choices: Choices
    var projectID: String?
    var known: [String]
    var lastChecked: Date?
    var lastError: String?
    var downloadedCount = 0
    var created = Date()
    var paused = false

    static var file: URL { Paths.home.appendingPathComponent("Watching.json") }
    static func load() -> [Watch] {
        guard AppSettings.persistent, let d = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Watch].self, from: d)) ?? []
    }
    static func save(_ list: [Watch]) {
        guard AppSettings.persistent else { return }
        try? Paths.ensure(Paths.home)
        try? JSONEncoder().encode(list).write(to: file, options: .atomic)
    }

    /// A YouTube channel's address without a tab lists its tabs, not its videos: point it at Videos.
    static func normalise(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), host.hasSuffix("youtube.com") else { return url }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return url }
        let isChannel = first.hasPrefix("@") ? parts.count == 1 : (["channel", "c", "user"].contains(first) && parts.count == 2)
        return isChannel ? url.appendingPathComponent("videos") : url
    }
}
