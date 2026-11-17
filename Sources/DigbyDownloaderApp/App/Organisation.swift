import SwiftUI
import AppKit
import DigbyDownloadCore

struct NewProjectRequest: Identifiable {
    let id = UUID()
    /// When set: after creating it, save this link's download into the new project.
    var forAnalysis: Analysis? = nil
    var forCollection: CollectionDraft? = nil
    var editing: Project? = nil
}

// MARK: - Projects

extension AppModel {
    var projects: [Project] { settings.projects ?? [] }
    func project(_ id: String?) -> Project? { id.flatMap { id in projects.first { $0.id == id } } }
    var currentProject: Project? { project(currentProjectID) }

    /// A new project: a folder of that name next to your usual videos (or wherever you pick).
    @discardableResult
    func createProject(name: String, symbol: String, folder: URL? = nil) -> Project {
        let clean = FileNamer.sanitize(name.trimmingCharacters(in: .whitespaces)).isEmpty ? "New Project" : name.trimmingCharacters(in: .whitespaces)
        let dir = folder ?? videoFolder.appendingPathComponent(FileNamer.sanitize(clean), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Project(name: clean, folder: dir.path, symbol: symbol)
        settings.projects = projects + [p]
        return p
    }
    func updateProject(_ p: Project) {
        settings.projects = projects.map { $0.id == p.id ? p : $0 }
    }
    /// Removes the project from Digby. Its folder and files stay exactly where they are.
    func removeProject(_ p: Project) {
        settings.projects = projects.filter { $0.id != p.id }
        if currentProjectID == p.id { currentProjectID = nil }
        if selectedProjectID == p.id { selectedProjectID = nil; section = .history }
        for i in watches.indices where watches[i].projectID == p.id { watches[i].projectID = nil }
    }
    /// Open a project: its downloads, and new links go into it until you switch back.
    func openProject(_ p: Project) {
        selectedProjectID = p.id
        currentProjectID = p.id
        section = .history
    }
    func historyCount(in p: Project) -> Int { history.filter { $0.succeeded && p.contains($0.file) }.count }
}

// MARK: - Overnight hours, speed, staying awake

extension AppModel {
    var overnightStart: Int { settings.overnightStart ?? 60 }
    var overnightEnd: Int { settings.overnightEnd ?? 7 * 60 }
    var alwaysOvernight: Bool { settings.alwaysOvernight ?? false }

    static func clock(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let d = Calendar.current.date(from: c) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
    var overnightLabel: String { "\(Self.clock(overnightStart))–\(Self.clock(overnightEnd))" }

    func isOvernight(_ date: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return overnightStart <= overnightEnd ? (m >= overnightStart && m < overnightEnd) : (m >= overnightStart || m < overnightEnd)
    }

    var waitingForOvernight: [QueueItem] { leaves.filter { $0.overnight && $0.state == .waiting } }

    /// Start a download now, even though it was set to wait for the overnight hours.
    func startNow(_ item: QueueItem) { item.overnight = false; pump() }
    func startAllNow() { waitingForOvernight.forEach { $0.overnight = false }; pump() }

    /// The limit for one download starting now: your total limit shared by those running.
    func rateLimitForNewDownload() -> Int64? {
        guard let total = settings.speedLimit, total > 0 else { return nil }
        return Int64(total) / Int64(max(1, activeCount))
    }

    /// Every minute: start overnight downloads when the hours begin; check watched channels when due; keep the
    /// Mac awake (not the screen) while something is downloading or waiting for the night.
    func startHousekeeping() {
        Task { @MainActor in
            while true {
                now = Date()
                if !waitingForOvernight.isEmpty && isOvernight() { pump() }
                updateKeepAwake()
                await checkWatchesIfDue()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func updateKeepAwake() {
        let needed = activeCount > 0 || !waitingForOvernight.isEmpty
        if needed && keepAwake == nil {
            keepAwake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                                                             reason: "Downloading, or waiting for the overnight hours")
        } else if !needed, let k = keepAwake {
            ProcessInfo.processInfo.endActivity(k); keepAwake = nil
        }
    }
}

// MARK: - Watching channels and playlists

extension AppModel {
    static let watchInterval: TimeInterval = 3 * 3600

    /// Starts watching the playlist or channel on this page. Videos already there count as seen, except the
    /// newest `alsoLatest`, which download now.
    func watch(_ d: CollectionDraft, alsoLatest: Int) {
        let c = d.collection
        guard let url = d.pageURL ?? drafts.first(where: { if case .collection(let x) = $0.state { return x === d }; return false })?.url else { return }
        var choices = d.choices; choices.clip = nil
        let latest = Array(c.entries.prefix(max(0, alsoLatest)))
        let w = Watch(url: Watch.normalise(url), title: c.title, site: c.site, choices: choices, projectID: d.projectID,
                      known: c.entries.map(\.id), lastChecked: Date(), downloadedCount: latest.count)
        watches.removeAll { $0.url == w.url }
        watches.append(w)
        if !latest.isEmpty { enqueue(latest, from: w, label: "latest") }
    }

    func stopWatching(_ w: Watch) { watches.removeAll { $0.id == w.id } }

    func checkWatchesIfDue() async {
        guard enginesReady else { return }
        for w in watches where !w.paused && Date().timeIntervalSince(w.lastChecked ?? .distantPast) > Self.watchInterval {
            await check(w)
        }
    }

    /// Reads the channel or playlist again; anything new is downloaded with the choices saved for it.
    func check(_ w: Watch) async {
        guard !checkingWatchIDs.contains(w.id) else { return }
        checkingWatchIDs.insert(w.id); defer { checkingWatchIDs.remove(w.id) }
        do {
            // Only the newest 60 entries: new videos appear at the top, and big channels stay quick to read.
            let r = try await YtDlpEngine().analyse(w.url, extraArguments: ["--playlist-end", "60"])
            guard let i = watches.firstIndex(where: { $0.id == w.id }) else { return }
            guard case .collection(let c) = r else {
                watches[i].lastError = "This page is a single video now, not a channel or playlist."; watches[i].lastChecked = Date(); return
            }
            let known = Set(watches[i].known)
            let fresh = c.entries.filter { !known.contains($0.id) }
            watches[i].known += fresh.map(\.id)
            watches[i].lastChecked = Date(); watches[i].lastError = nil
            if !fresh.isEmpty {
                watches[i].downloadedCount += fresh.count
                enqueue(fresh, from: watches[i], label: "new")
                Notifier.post("New videos", "\(fresh.count) new from \(w.title), downloading now")
            }
        } catch let f as Failure {
            if let i = watches.firstIndex(where: { $0.id == w.id }) { watches[i].lastError = f.title; watches[i].lastChecked = Date() }
        } catch {
            if let i = watches.firstIndex(where: { $0.id == w.id }) { watches[i].lastError = "\(error)"; watches[i].lastChecked = Date() }
        }
    }

    private func enqueue(_ entries: [MediaCollection.Entry], from w: Watch, label: String) {
        let group = QueueItem(title: w.title, site: w.site, summary: "\(entries.count) \(label) video\(entries.count == 1 ? "" : "s") · watching")
        let dest = project(w.projectID)?.folderURL
        group.children = entries.enumerated().map { i, e in
            let c = QueueItem(title: e.title, site: w.site, summary: "Waiting")
            c.entryThumbnail = e.thumbnail
            c.destination = dest
            c.overnight = alwaysOvernight
            c.work = .unplanned(url: e.url, choices: w.choices, playlist: w.title, index: i + 1)
            return c
        }
        queue.insert(group, at: 0)
        pump()
    }
}

// MARK: - Links from the browser

extension AppModel {
    /// `digby-video://download?url=<page>` (the browser button and bookmarklet): opens the link for you to
    /// choose, exactly as if you'd pasted it. Nothing downloads by itself.
    func open(_ url: URL) {
        if url.scheme?.lowercased() == "digby-video" {
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            guard let page, let u = URL(string: page), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return }
            NSApp.activate(ignoringOtherApps: true)
            urlText = u.absoluteString; analyse()
        } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            urlText = url.absoluteString; analyse()
        }
    }
}
