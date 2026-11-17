import SwiftUI
import AppKit
import VideoToolbox
import DigbyDownloadCore

enum SidebarSection: String, Hashable, CaseIterable {
    case download, queue, history, watching
    // Each video lives in one place at a time: being prepared → downloading → downloaded.
    var title: String { switch self { case .download: "New Download"; case .queue: "Downloading"; case .history: "Downloaded"; case .watching: "Watching" } }
    var symbol: String { switch self { case .download: "plus.circle"; case .queue: "arrow.down.circle"; case .history: "checkmark.circle"; case .watching: "bell" } }
}

/// One analysed link, with the person's current choices. Changing choices never re-analyses.
@Observable final class Analysis {
    let catalogue: FormatCatalogue
    var choices: Choices
    var profileID: String?
    var advanced = false
    /// When the usual settings didn't fit this video and Digby picked the closest workable choice.
    var autoNote: String?
    /// Saved into this project's folder (nil: the usual folder).
    var projectID: String?
    /// Waits for the overnight hours.
    var overnight = false
    init(catalogue: FormatCatalogue, choices: Choices = Choices(), profileID: String? = nil) {
        self.catalogue = catalogue; self.choices = choices; self.profileID = profileID
    }
    func result(_ env: PlaybackEnvironment) -> SelectionResult { FormatSelector.select(catalogue, choices, playback: env) }
}

/// A playlist or channel being prepared: which entries are included, and the shared choices.
@Observable final class CollectionDraft: Identifiable {
    let id = UUID()
    let collection: MediaCollection
    var included: Set<String>
    var choices = Choices()
    var projectID: String?
    var overnight = false
    /// The page it came from (what Watching checks again).
    var pageURL: URL?
    init(_ c: MediaCollection) { collection = c; included = Set(c.entries.map(\.id)) }
}

struct Diagnosis: Hashable {
    static let tryNightly = "Try the Nightly Engine"
    enum Kind: Hashable { case outdatedExtractor, privateMedia, rateLimited, network, loginRequired, unavailable, diskFull, other }
    var kind: Kind
    var title: String
    var explanation: String
    var whatDigbyDid: [(String, Bool)]   // (step, done)
    var inProgress: Bool
    var actions: [String]
    var report: String = ""
    var failure: Failure? = nil
    static func == (a: Diagnosis, b: Diagnosis) -> Bool { a.title == b.title && a.inProgress == b.inProgress }
    func hash(into h: inout Hasher) { h.combine(title); h.combine(inProgress) }

    init(kind: Kind, title: String, explanation: String, whatDigbyDid: [(String, Bool)], inProgress: Bool, actions: [String], report: String = "") {
        self.kind = kind; self.title = title; self.explanation = explanation; self.whatDigbyDid = whatDigbyDid
        self.inProgress = inProgress; self.actions = actions; self.report = report
    }

    /// A classified engine failure, explained.
    init(_ f: Failure, engineVersion: String?) {
        let k: Kind = switch f.kind {
            case .outdatedExtractor, .jsRuntime: .outdatedExtractor
            case .privateMedia: .privateMedia
            case .rateLimited: .rateLimited
            case .network, .blocked: .network
            case .loginRequired, .botCheck: .loginRequired
            case .unavailable: .unavailable
            case .diskFull: .diskFull
            default: .other
        }
        var steps: [(String, Bool)] = [("Read the site’s answer and recognised the problem", true)]
        if let v = engineVersion { steps.append(("Using the current extraction engine (yt-dlp \(v))", true)) }
        var actions = ["Try Again", "Copy Report"]
        // When the engine can't read a page that plays fine in a browser, let a browser find the video.
        let catchable: Set<Failure.Kind> = [.blocked, .unsupportedSite, .outdatedExtractor, .unknown, .unsupportedFormat, .jsRuntime, .botCheck, .loginRequired, .unavailable]
        if catchable.contains(f.kind), !f.noPageRoutes { actions.insert("Find the Video on the Page", at: 0) }
        if [.botCheck, .loginRequired, .privateMedia, .blocked].contains(f.kind) { actions.insert("Use My Browser’s Sign-in", at: f.kind == .blocked ? 1 : 0) }
        self.init(kind: k, title: f.title, explanation: f.explanation, whatDigbyDid: steps, inProgress: false, actions: actions)
        self.failure = f
    }
}

/// A failure already explained (after recovery attempts), shown as is.
struct DiagnosedFailure: Error { var diagnosis: Diagnosis }

enum ComposerState {
    var url: URL? {
        switch self {
        case .empty: nil
        case .analysing(let u, _), .failed(let u, _): u
        case .ready(let a): a.catalogue.media.webpageURL
        case .collection(let d): d.collection.entries.first?.url ?? URL(string: "https://example.invalid")
        case .downloading(let i), .completed(let i): i.media?.webpageURL ?? URL(string: "https://example.invalid")
        }
    }
    case empty
    case analysing(URL, step: Int)
    case ready(Analysis)
    case collection(CollectionDraft)
    case downloading(QueueItem)
    case completed(QueueItem)
    case failed(URL, Diagnosis)
}

struct EngineStatus: Identifiable, Hashable {
    enum State: Hashable { case upToDate, updateAvailable, updating(Double), checking, missing, installing(String) }
    var id: String { name }
    var name: String
    var role: String
    var installed: String?
    var latest: String?
    var state: State
    var lastChecked: Date?
    var tool: ToolID? = nil
    var previous: String? = nil
}

@MainActor @Observable final class AppModel {
    static weak var shared: AppModel?

    var section: SidebarSection = .download
    /// Every link pasted into New Download, each with its own state; the tray switches between them.
    var drafts: [Draft] = []
    var selectedDraftID: UUID? = nil
    var selectedDraft: Draft? { drafts.first { $0.id == selectedDraftID } }
    /// The selected draft's state (`.empty` when composing a new link).
    var composer: ComposerState {
        get { selectedDraft?.state ?? .empty }
        set {
            if let d = selectedDraft { d.state = newValue; return }
            guard let url = newValue.url else { return }
            let d = Draft(url: url, state: newValue); drafts.append(d); selectedDraftID = d.id
        }
    }
    /// The draft showing a given download (to move it on to "done" or "failed").
    func draft(showing item: QueueItem) -> Draft? {
        drafts.first { if case .downloading(let i) = $0.state { return i === item }; return false }
    }
    func select(_ d: Draft?) { selectedDraftID = d?.id; section = .download }
    func close(_ d: Draft) {
        if case .analysing = d.state { d.token.cancel() }
        let i = drafts.firstIndex { $0 === d }
        drafts.removeAll { $0 === d }
        if selectedDraftID == d.id { selectedDraftID = i.flatMap { drafts.indices.contains($0) ? drafts[$0].id : drafts.last?.id } }
    }
    var urlText = ""
    var queue: [QueueItem] = []
    var history: [HistoryEntry] = []
    let historyStore: HistoryStore? = AppSettings.persistent ? (try? HistoryStore()) : nil
    /// Downloads that hadn't finished when Digby last quit.
    var resumeOffer: [PendingDownload] = []
    var engines: [EngineStatus] = []
    var engineBanner: String? = nil
    var enginesReady = false
    var clipboardSuggestion: URL? = nil
    /// Sign-in sheet request: which site, and the link to retry afterwards.
    struct SignInRequest: Identifiable { var site: SignInSite; var retry: URL?; var id: String { site.rawValue } }
    var signInRequest: SignInRequest? = nil
    /// "“Title” is downloading" confirmation after pressing Download.
    var justStarted: QueueItem? = nil
    /// The Details sheet: original, choices, result.
    var detailsShown: DownloadDetails? = nil
    /// Downloading rows opened to show their details (also opened from the sidebar).
    var expandedQueueIDs: Set<UUID> = []
    /// Bumped by ⌘L: the link field takes the keyboard focus.
    var focusLinkRequest = 0
    /// The project shown in the sidebar (Downloaded, filtered to its folder).
    var selectedProjectID: String? = nil
    /// New links are saved into this project (shown on the link bar; ✕ goes back to the usual folders).
    var currentProjectID: String? = nil
    var watches: [Watch] = Watch.load() { didSet { Watch.save(watches) } }
    var checkingWatchIDs: Set<String> = []
    var newProjectRequest: NewProjectRequest? = nil
    var watchRequest: CollectionDraft? = nil
    var keepAwake: NSObjectProtocol? = nil
    var now = Date()
    var signIns: [SignInSite: SignInSettings.Source] = SignInSettings.load().sites
    let playback = PlaybackEnvironment(decodesAV1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
    private var lastPasteboardChange = NSPasteboard.general.changeCount

    // Settings, saved on every change. Setters ignore unchanged values: any write to an observed property
    // re-renders its readers, and the menu-bar switch writes back on every scene update (that looped forever).
    var settings = AppSettings.load() { didSet { if settings != oldValue { settings.save() } } }
    var watchClipboard: Bool { get { settings.watchClipboard } set { guard settings.watchClipboard != newValue else { return }; settings.watchClipboard = newValue } }
    var showMenuBarIcon: Bool { get { settings.showMenuBarIcon } set { guard settings.showMenuBarIcon != newValue else { return }; settings.showMenuBarIcon = newValue } }
    var notifyWhenDone: Bool { get { settings.notifyWhenDone } set { guard settings.notifyWhenDone != newValue else { return }; settings.notifyWhenDone = newValue; if newValue { Notifier.requestPermission() } } }
    var maxConcurrent: Int { get { settings.maxConcurrent } set { guard settings.maxConcurrent != newValue else { return }; settings.maxConcurrent = newValue; pump() } }
    var perSite: Int { get { settings.perSite } set { guard settings.perSite != newValue else { return }; settings.perSite = newValue; pump() } }
    var channel: String {
        get { settings.channel }
        set {
            guard settings.channel != newValue else { return }
            settings.channel = newValue
            // A channel chosen by hand replaces any nightly a recovery fetched.
            Task { await DependencyManager.shared.setRecoveryNightly(false) }
        }
    }
    var nameTemplate: String { get { settings.nameTemplate } set { guard settings.nameTemplate != newValue else { return }; settings.nameTemplate = newValue } }
    var defaultProfileID: String { get { settings.defaultProfileID } set { guard settings.defaultProfileID != newValue else { return }; settings.defaultProfileID = newValue } }
    var profiles: [DownloadProfile] { DownloadProfile.builtIns + settings.customProfiles }
    var linksAsList: Bool {
        get { settings.linksAsList ?? false }
        set { guard linksAsList != newValue else { return }; settings.linksAsList = newValue }
    }
    var videoFolder: URL { settings.videoFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Paths.defaultVideoFolder }
    var audioFolder: URL { settings.audioFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Paths.defaultAudioFolder }

    init() {
        AppModel.shared = self
        if ProcessInfo.processInfo.environment["DIGBY_DL_RENDER"] != nil { MockData.populate(self); return }
        history = historyStore?.entries() ?? []
        resumeOffer = PendingDownload.load()
        // Work folders from a crash, or from pauses abandoned for two weeks, are removed.
        let keep = Set(resumeOffer.map(\.workID))
        // (one level down too: downloads sorted into month, day, site or channel folders)
        for f in [videoFolder, audioFolder] {
            Downloader.sweep(f, keeping: keep)
            for sub in (try? FileManager.default.contentsOfDirectory(at: f, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !sub.lastPathComponent.hasPrefix(".") {
                Downloader.sweep(sub, keeping: keep)
            }
        }
        // Per-download cookie copies from Digby's browser are short-lived.
        let signIn = Paths.home.appendingPathComponent("Sign-in")
        for n in (try? FileManager.default.contentsOfDirectory(atPath: signIn.path)) ?? [] where n.hasPrefix("page-") {
            let f = signIn.appendingPathComponent(n)
            if let d = try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate] as? Date, Date().timeIntervalSince(d) > 86_400 {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    // MARK: History

    func addHistory(_ e: HistoryEntry) {
        historyStore?.add(e)
        history.insert(e, at: 0)
    }
    func removeHistory(_ e: HistoryEntry) {
        historyStore?.remove(id: e.id)
        history.removeAll { $0.id == e.id }
    }
    /// Search runs in the database (all of history), not just what's loaded.
    func searchHistory(_ text: String, audio: Bool?, failed: Bool) -> [HistoryEntry] {
        if let store = historyStore {
            return store.entries(search: text, audioOnly: audio, succeeded: failed ? false : (audio == nil ? nil : true))
        }
        return history.filter { r in
            (text.isEmpty || r.title.localizedCaseInsensitiveContains(text) || r.site.localizedCaseInsensitiveContains(text))
                && (failed ? !r.succeeded : (audio == nil || (r.succeeded && (r.kind == .audioOnly) == audio!)))
        }
    }

    // MARK: Unfinished downloads

    /// Remember every download that hasn't finished: on quit, and every few seconds while running (so a crash,
    /// force quit or restart loses nothing). Downloads still waiting for a Continue/Discard answer are kept too.
    func saveQueue() {
        let list = pendingList()
        lastSavedQueue = try? JSONEncoder().encode(list)
        PendingDownload.save(list)
    }
    private var lastSavedQueue: Data?
    /// The periodic save: writes only when something changed.
    func autosaveQueue() {
        let list = pendingList()
        guard let d = try? JSONEncoder().encode(list), d != lastSavedQueue else { return }
        lastSavedQueue = d
        PendingDownload.save(list)
    }
    private func pendingList() -> [PendingDownload] {
        let current: [PendingDownload] = leaves.compactMap { item in
            switch item.state { case .done, .cancelled: return nil; default: break }
            guard let url = workURL(item) else { return nil }
            let (choices, playlist, index): (Choices, String?, Int) = {
                switch item.work {
                case .unplanned(_, let c, let p, let i)?: return (c, p, i)
                default: return (item.choices ?? profileChoices(), nil, 1)
                }
            }()
            var paused = false
            if case .paused = item.state { paused = true }
            if item.isActive { paused = true }        // stopped by quitting: its partial data is kept
            return PendingDownload(url: url, title: item.title, choices: choices, playlist: playlist, index: index, workID: item.workID, paused: paused,
                                   folder: item.destination?.path)
        }
        let ids = Set(current.map(\.workID))
        return current + resumeOffer.filter { !ids.contains($0.workID) }
    }
    func resumeUnfinished() {
        for p in resumeOffer {
            let item = QueueItem(title: p.title, site: p.url.host?.replacingOccurrences(of: "www.", with: "") ?? "", summary: "Continuing")
            item.workID = p.workID
            item.destination = p.folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            item.work = .unplanned(url: p.url, choices: p.choices, playlist: p.playlist, index: p.index)
            queue.append(item)
        }
        resumeOffer = []; PendingDownload.save([])
        section = .queue
        pump()
    }
    func discardUnfinished() {
        resumeOffer = []; PendingDownload.save([])
        for f in [videoFolder, audioFolder] { Downloader.sweep(f, keeping: [], olderThan: 0) }
    }

    // MARK: Profiles

    func saveProfile(named name: String, choices: Choices) {
        let p = DownloadProfile(id: "custom-\(UUID().uuidString.prefix(8))", name: name, summary: "Your profile", symbol: "person.crop.circle",
                                choices: choices, embedMetadata: true, embedChapters: true, isBuiltIn: false)
        settings.customProfiles.append(p)
    }
    func deleteProfile(_ p: DownloadProfile) {
        settings.customProfiles.removeAll { $0.id == p.id }
        if defaultProfileID == p.id { defaultProfileID = DownloadProfile.maximumQuality.id }
    }

    var activeCount: Int { leaves.filter(\.isActive).count }
    /// What the sidebar previews under Downloading: running first, then waiting, paused and failed.
    var sidebarDownloads: [QueueItem] {
        func rank(_ i: QueueItem) -> Int? {
            switch i.state {
            case .downloading, .processing, .verifying, .analysing: 0
            case .waiting: 1
            case .paused: 2
            case .failed: 3
            case .done, .cancelled: nil
            }
        }
        return leaves.compactMap { i in rank(i).map { (i, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
    }
    /// Every individual download (playlist children included).
    var leaves: [QueueItem] { queue.flatMap { $0.isPlaylist ? $0.children : [$0] } }

    // MARK: Engines

    /// At launch: show what's installed; install whatever is missing (first run).
    func start() async {
        guard ProcessInfo.processInfo.environment["DIGBY_DL_RENDER"] == nil else { return }
        startHousekeeping()
        Task { @MainActor [weak self] in
            while let self {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self.autosaveQueue()
            }
        }
        await refreshEngines()
        let deps = DependencyManager.shared
        if await deps.isReady { enginesReady = true; scheduleUpdateChecks(); return }
        engineBanner = "Setting up the download engines (first run only, about 150 MB)…"
        do {
            try await deps.ensureInstalled(channel: UpdateChannel(rawValue: channel.lowercased()) ?? .stable) { p in
                Task { @MainActor in
                    self.engineBanner = p.step + (p.fraction.map { String(format: " — %.0f%%", $0 * 100) } ?? "…")
                }
            }
            engineBanner = nil
            enginesReady = true
            scheduleUpdateChecks()
        } catch {
            engineBanner = "Couldn’t set up the download engines: \(error). Digby will try again next time it opens."
        }
        await refreshEngines()
    }

    func refreshEngines() async {
        let deps = DependencyManager.shared
        let installed = await deps.installed(), latest = await deps.latestKnown, checked = await deps.lastCheck
        engineHistory = await deps.history()
        engines = ToolID.allCases.map { t in
            let i = installed[t]
            let l = latest[t] ?? i?.version
            let newer = i != nil && l != nil && Version.isNewer(l!, than: i!.version)
            return EngineStatus(name: t.displayName, role: t.role, installed: i?.version, latest: l,
                                state: updatingTool == t ? .updating(0) : i == nil ? .missing : newer ? .updateAvailable : .upToDate,
                                lastChecked: checked, tool: t, previous: i?.previousVersion)
        }
    }

    // MARK: Engine updates

    var engineHistory: [UpdateRecord] = []
    var updatingTool: ToolID? = nil
    var installEngineUpdates: Bool {
        get { settings.installEngineUpdates ?? true }
        set { guard installEngineUpdates != newValue else { return }; settings.installEngineUpdates = newValue }
    }
    var updateChannel: UpdateChannel { UpdateChannel(rawValue: channel.lowercased()) ?? .stable }
    private var updateTimerStarted = false

    /// Checks at launch, then wakes every 15 minutes to see whether a check is due: the quick yt-dlp check
    /// every few hours (sooner, with backoff, after a failed one), the full check daily (`UpdateSchedule`).
    func scheduleUpdateChecks() {
        guard !updateTimerStarted, AppSettings.persistent else { return }
        updateTimerStarted = true
        Task { @MainActor in
            while true {
                await checkEngineUpdates(force: false)
                try? await Task.sleep(nanoseconds: UInt64(UpdateSchedule.tick * 1e9))
            }
        }
    }

    /// Asks the official sources for newer engines; installs them quietly when nothing is downloading.
    func checkEngineUpdates(force: Bool) async {
        let deps = DependencyManager.shared
        var newer: [ToolRelease] = []
        let last = await deps.lastCheck, quick = await deps.extractorCheck
        if force || UpdateSchedule.isDue(lastCheck: last, channel: updateChannel) {
            newer = await deps.checkForUpdates(channel: updateChannel)
        } else if UpdateSchedule.isExtractorDue(quick, channel: updateChannel) {
            newer = await deps.checkExtractor(channel: updateChannel).map { [$0] } ?? []
        } else { return }
        await refreshEngines()
        guard !newer.isEmpty, installEngineUpdates || force else { return }
        pendingUpdates.removeAll { p in newer.contains { $0.tool == p.tool } }
        pendingUpdates += newer
        installPendingUpdatesIfIdle()
    }
    private var pendingUpdates: [ToolRelease] = []

    /// Engines are swapped only between downloads, never under a running one.
    func installPendingUpdatesIfIdle() {
        guard activeCount == 0, updatingTool == nil, let next = pendingUpdates.first else { return }
        pendingUpdates.removeFirst()
        Task { @MainActor in
            await install(next)
            installPendingUpdatesIfIdle()
        }
    }

    func install(_ r: ToolRelease) async {
        updatingTool = r.tool
        await refreshEngines()
        engineBanner = "Updating \(r.tool.displayName) to \(r.version)…"
        do {
            try await DependencyManager.shared.install(r) { p in
                Task { @MainActor in self.engineBanner = p.step + (p.fraction.map { String(format: " — %.0f%%", $0 * 100) } ?? "…") }
            }
            engineBanner = nil
        } catch {
            engineBanner = "\(r.tool.displayName) \(r.version) wasn’t installed: \(error). The current version keeps working."
            Task { @MainActor in try? await Task.sleep(nanoseconds: 8_000_000_000); if self.engineBanner?.contains("wasn’t installed") == true { self.engineBanner = nil } }
        }
        updatingTool = nil
        await refreshEngines()
    }

    func updateNow(_ t: ToolID) async {
        guard let r = try? await DependencyManager.shared.latest(t, channel: updateChannel) else { return }
        await install(r)
    }

    func rollback(_ t: ToolID) async {
        do { try await DependencyManager.shared.rollback(t) }
        catch { engineBanner = "Couldn’t go back: \(error)" }
        await refreshEngines()
    }

    func copyReport(_ d: Diagnosis, link: URL?) {
        guard let f = d.failure else { return }
        Task { @MainActor in
            let text = DiagnosticReport.make(failure: f, link: link, engines: await DependencyManager.shared.installed(),
                                             appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        }
    }
    // MARK: Site success (kept on this Mac only)

    let siteStats: SiteStatsStore? = AppSettings.persistent ? SiteStatsStore() : nil
    /// Bumped on each record so the Settings table refreshes.
    var siteStatsVersion = 0
    func recordAttempt(_ url: URL, failure: Failure?) {
        guard let site = SiteStats.site(for: url), failure?.kind != .cancelled else { return }
        siteStats?.record(SiteAttempt(site: site, succeeded: failure == nil, failure: failure?.kind, engine: ytdlpVersion))
        siteStatsVersion += 1
    }
    var siteStatsRows: [SiteStatsRow] { _ = siteStatsVersion; return SiteStats.summarise(siteStats?.all() ?? mockSiteAttempts) }
    var mockSiteAttempts: [SiteAttempt] = []
    var lastEngineUpdate: UpdateRecord? { engineHistory.last { $0.tool == .ytdlp && $0.outcome == "installed" } }
    func copySiteReport() {
        let engines = Dictionary(uniqueKeysWithValues: engines.compactMap { e in e.tool.flatMap { t in e.installed.map { (t, $0) } } })
        let text = SiteStats.report(siteStatsRows, appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                                    engines: engines, channel: updateChannel, lastEngineUpdate: lastEngineUpdate)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func clearSiteStats() { siteStats?.clear(); siteStatsVersion += 1 }

    var ytdlpVersion: String? { engines.first { $0.name == ToolID.ytdlp.displayName }?.installed }

    // MARK: Composer

    /// Analyse the typed or pasted text. Several links at once go straight to the queue as a batch.
    func analyse() {
        let links = Self.links(in: urlText)
        guard let first = links.first else { return }
        section = .download
        clipboardSuggestion = nil
        if links.count > 1 {
            let ch = profileChoices()
            for (i, l) in links.enumerated() where !alreadyQueued(l) {
                let item = QueueItem(title: l.absoluteString, site: l.host?.replacingOccurrences(of: "www.", with: "") ?? "", summary: "Waiting to be read")
                item.work = .unplanned(url: l, choices: ch, playlist: nil, index: i + 1)
                queue.append(item)
            }
            urlText = ""; section = .queue
            pump(); return
        }
        guard enginesReady else {
            select(nil)
            composer = .failed(first, Diagnosis(kind: .other, title: "The download engines are still being set up",
                                                explanation: "This happens once, the first time Digby opens. Try again when the banner at the top disappears.",
                                                whatDigbyDid: [("Downloading and checking the engines", false)], inProgress: true, actions: []))
            return
        }
        // Already open? Just show it. Otherwise a new draft: earlier ones keep going in the background.
        urlText = ""
        // A link that didn't work is read again (Try Again), replacing its old tab.
        if let existing = drafts.first(where: { $0.url == first }) {
            guard case .failed = existing.state else { select(existing); return }
            close(existing)
        }
        let draft = Draft(url: first, state: .analysing(first, step: 0))
        drafts.append(draft); select(draft)
        let token = draft.token
        let choices = nextChoices; nextChoices = nil
        Task { @MainActor in
            // Steps advance on a timer while the engine reads the page; the real result replaces them.
            Task { @MainActor in
                for step in 1...2 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if case .analysing = draft.state { draft.state = .analysing(first, step: step) }
                }
            }
            do {
                let result = try await analyseWithRecovery(first, token: token, draft: draft)
                guard !token.isCancelled else { return }
                switch result {
                case .single(let m):
                    // The engine found sound but no picture on a page that may well show a video: look on the page.
                    if FormatCatalogue(m).tiers.isEmpty, await catchOnPage(first, draft: draft, token: token, choices: choices) { return }
                    nextChoices = choices
                    draft.state = .ready(makeAnalysis(m)); draft.title = m.title
                case .collection(let c):
                    let d = CollectionDraft(c); d.choices = choices ?? profileChoices(); d.pageURL = first
                    d.projectID = currentProjectID; d.overnight = alwaysOvernight
                    draft.state = .collection(d); draft.title = c.title
                }
            } catch let d as DiagnosedFailure {
                if let f = d.diagnosis.failure, Self.pageCatchable.contains(f.kind), !f.noPageRoutes, await catchOnPage(first, draft: draft, token: token, choices: choices) { return }
                draft.state = .failed(first, d.diagnosis)
                if let f = d.diagnosis.failure { recordAttempt(first, failure: f) }
            } catch let f as Failure {
                if f.kind != .cancelled, Self.pageCatchable.contains(f.kind), !f.noPageRoutes, await catchOnPage(first, draft: draft, token: token, choices: choices) { return }
                if f.kind != .cancelled { draft.state = .failed(first, Diagnosis(f, engineVersion: ytdlpVersion)); recordAttempt(first, failure: f) }
                // A site asking "are you a person?" or for a login: offer the sign-in straight away.
                if YtDlpEngine.needsSignIn(f), let site = SignInSite.site(for: first), signIns[site] == nil {
                    signInRequest = SignInRequest(site: site, retry: first)
                }
            } catch {
                draft.state = .failed(first, Diagnosis(ErrorClassifier.classify(stderr: "\(error)"), engineVersion: ytdlpVersion))
            }
        }
    }

    /// Analysis, with recovery: a changed site gets an engine update and one more try; a dropped
    /// connection gets one quiet retry. The diagnosing card shows each step as it happens.
    func analyseWithRecovery(_ url: URL, token: CancelToken, draft: Draft? = nil) async throws -> AnalysisResult {
        do { return try await YtDlpEngine().analyse(url, cancel: token) }
        catch let f as Failure {
            switch RecoveryPolicy.next(after: f, attempt: 1, engineUpdateTried: false) {
            case .retry(let delay, _) where delay <= 10:
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                return try await YtDlpEngine().analyse(url, cancel: token)
            case .updateEngineThenRetry:
                var d = Diagnosis(kind: .outdatedExtractor, title: f.title,
                                  explanation: "\(f.explanation) Digby is checking for an updated extraction engine.",
                                  whatDigbyDid: [("Recognised the problem", true), ("Looking for an updated extraction engine", false), ("Trying again", false)],
                                  inProgress: true, actions: [])
                draft?.state = .failed(url, d)
                let outcome = await EngineRecovery().updateExtractor(on: updateChannel, userChannel: updateChannel) { _ in }
                await refreshEngines()
                guard outcome.updated, !token.isCancelled else {
                    var final = Diagnosis(f, engineVersion: ytdlpVersion)
                    final.whatDigbyDid.append((outcome.message, true))
                    offerNightlyIfUseful(&final, f)
                    throw DiagnosedFailure(diagnosis: final)
                }
                d.whatDigbyDid = [("Recognised the problem", true), (outcome.message, true), ("Trying again", false)]
                draft?.state = .failed(url, d)
                do {
                    var r = try await YtDlpEngine().analyse(url, cancel: token)
                    if case .single(var m) = r { m.notice = [m.notice, "Fixed: \(outcome.message)"].compactMap { $0 }.joined(separator: " "); r = .single(m) }
                    return r
                } catch let f2 as Failure {
                    var final = Diagnosis(f2, engineVersion: ytdlpVersion)
                    final.whatDigbyDid.append((outcome.message + " It didn’t fix this page yet.", true))
                    offerNightlyIfUseful(&final, f2)
                    throw DiagnosedFailure(diagnosis: final)
                }
            default:
                throw f
            }
        }
    }

    /// On Stable, once the newest Stable engine hasn't fixed a changed site, offer the Nightly build.
    func offerNightlyIfUseful(_ d: inout Diagnosis, _ f: Failure) {
        guard EngineEscalation.next(after: f.kind, userChannel: updateChannel, tried: [updateChannel]) == .offerNightly,
              !d.actions.contains(Diagnosis.tryNightly) else { return }
        d.actions.insert(Diagnosis.tryNightly, at: 0)
    }

    /// "Try the Nightly Engine": fetch and verify the nightly yt-dlp (same checks as any install), then read the
    /// page again. Each step shows on the diagnosing card. It waits while downloads are running.
    func tryNightly(_ url: URL) {
        let owner = drafts.first { if case .failed(let u, _) = $0.state { return u == url }; return false }
        func show(_ steps: [(String, Bool)]) {
            owner?.state = .failed(url, Diagnosis(kind: .outdatedExtractor, title: "Trying the nightly extraction engine",
                                                  explanation: "Fixes for changed sites usually reach the nightly build within a day. Digby checks it’s genuine and test-runs it before using it.",
                                                  whatDigbyDid: steps, inProgress: true, actions: []))
        }
        Task { @MainActor in
            while activeCount > 0 || updatingTool != nil {
                show([("Waiting for the current downloads to finish", false)])
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            show([("Looking for the newest nightly engine", false), ("Checking it’s genuine and test-running it", false), ("Reading the page again", false)])
            updatingTool = .ytdlp
            let outcome = await EngineRecovery().updateExtractor(on: .nightly, userChannel: updateChannel) { p in
                Task { @MainActor in if p.step.hasPrefix("Checking") || p.step.hasPrefix("Testing") { show([("Found it", true), (p.step, false), ("Reading the page again", false)]) } }
            }
            updatingTool = nil
            await refreshEngines()
            guard outcome.updated else {
                var d = Diagnosis(kind: .outdatedExtractor, title: "No nightly fix yet", explanation: outcome.message + " Fixes usually appear within a day or two; try again later, or find the video on the page.",
                                  whatDigbyDid: [(outcome.message, true)], inProgress: false, actions: ["Find the Video on the Page", "Try Again", "Copy Report"])
                d.failure = Failure(kind: .outdatedExtractor, title: d.title, explanation: d.explanation, retryable: true, suggestsEngineUpdate: false, detail: "")
                owner?.state = .failed(url, d)
                return
            }
            show([(outcome.message, true), ("Checked it’s genuine and test-ran it", true), ("Reading the page again", false)])
            urlText = url.absoluteString
            analyse()
        }
    }

    func profileChoices() -> Choices {
        let p = profiles.first { $0.id == defaultProfileID } ?? .maximumQuality
        var ch = p.choices
        // Maximum Quality in the window defaults to MP4 that plays on this Mac; MKV is one click away.
        if p.id == DownloadProfile.maximumQuality.id { ch.container = .mp4; ch.preferPlayableOnThisMac = true }
        return ch
    }

    /// Choices to apply to the next analysis (History → Download Again).
    var nextChoices: Choices?
    /// A finished download of the same video whose file is still there (same link, or the site's video id in it).
    func alreadyDownloaded(_ m: MediaInfo) -> HistoryEntry? {
        history.first { e in
            guard e.succeeded, let f = e.file, FileManager.default.fileExists(atPath: f.path) else { return false }
            if e.url == m.webpageURL { return true }
            // The same video under another form of link on the same site: the video id appears in both.
            return m.id.count >= 8 && SiteKey.of(e.url) == SiteKey.of(m.webpageURL) && e.url.absoluteString.contains(m.id)
        }
    }

    func makeAnalysis(_ m: MediaInfo) -> Analysis {
        defer { nextChoices = nil }
        let chosenByYou = nextChoices != nil
        let a = Analysis(catalogue: FormatCatalogue(m), choices: nextChoices ?? profileChoices(), profileID: nil)
        a.projectID = currentProjectID
        a.overnight = alwaysOvernight
        // Your usual settings don't fit this video: start from the closest choice that works without converting
        // (said plainly; your own explicit choices, e.g. Download Again, are never changed).
        if !chosenByYou, case .unsatisfiable(let reason, let alts) = a.result(playback) {
            let works = alts.filter { FormatSelector.select(a.catalogue, $0.choices, playback: playback).plan != nil }
            if let pick = works.first(where: { !$0.choices.convertPicture }) ?? works.first {
                a.choices = pick.choices
                a.autoNote = "Your usual settings don’t fit this video (\(reason.prefix(1).lowercased() + reason.dropFirst().replacingOccurrences(of: ".", with: ""))), so Digby chose “\(pick.label)”. You can change it below."
            }
        }
        return a
    }

    func folder(for plan: DownloadPlan, playlist: String? = nil, destination: URL? = nil, media: MediaInfo? = nil) -> URL {
        var base = destination ?? (plan.kind == .audioOnly ? audioFolder : videoFolder)
        // Sorting applies to the usual folders; a project keeps its folder as you made it.
        if destination == nil, let m = media, let sub = (settings.folderSorting ?? .none).subfolder(media: m) {
            base.appendPathComponent(sub, isDirectory: true)
        }
        guard let playlist, settings.playlistSubfolders else { return base }
        return base.appendingPathComponent(FileNamer.sanitize(playlist), isDirectory: true)
    }

    func startDownload(_ a: Analysis) {
        guard let plan = a.result(playback).plan else { return }
        let m = a.catalogue.media
        let item = QueueItem(title: m.title, site: m.site, summary: plan.chips(catalogue: a.catalogue).joined(separator: " · "), size: plan.size)
        item.media = m
        item.notes = plan.notes
        item.choices = a.choices
        item.details = DownloadDetails.make(catalogue: a.catalogue, choices: a.choices, plan: plan)
        item.destination = project(a.projectID)?.folderURL
        item.overnight = a.overnight
        var name = FileNamer.render(nameTemplate, media: m, plan: plan)
        if let clip = plan.clip { name += " (part \(clip.fileLabel))" }
        var req = DownloadRequest(media: m, plan: plan, folder: folder(for: plan, destination: item.destination, media: m), fileName: name)
        req.workID = item.workID
        item.work = .planned(req)
        queue.insert(item, at: 0)
        // The video moves on to Downloading; this page closes so the next link is ready for you.
        if let owner = drafts.first(where: { if case .ready(let x) = $0.state { return x === a }; return false }) { close(owner) }
        justStarted = item
        Task { @MainActor in try? await Task.sleep(nanoseconds: 7_000_000_000); if justStarted === item { justStarted = nil } }
        pump()
    }

    func startCollection(_ d: CollectionDraft) {
        let entries = d.collection.entries.filter { d.included.contains($0.id) }
        guard !entries.isEmpty else { return }
        let group = QueueItem(title: d.collection.title, site: d.collection.site, summary: "Playlist · \(entries.count) videos")
        group.children = entries.enumerated().map { i, e in
            let c = QueueItem(title: e.title, site: d.collection.site, summary: "Waiting")
            c.entryThumbnail = e.thumbnail
            c.work = .unplanned(url: e.url, choices: d.choices, playlist: d.collection.title, index: i + 1)
            c.destination = project(d.projectID)?.folderURL
            c.overnight = d.overnight
            return c
        }
        queue.insert(group, at: 0)
        if let owner = drafts.first(where: { if case .collection(let x) = $0.state { return x === d }; return false }) { close(owner) }
        section = .queue
        pump()
    }

    /// A stream caught on a page: analysed with the page's headers and cookies, then the usual choices.
    /// - replacing: close an earlier tab for the same page (false when several videos from one page are opened together).
    /// - label: added to the tab's name so videos caught on the same page can be told apart ("Video stream, up to 1080p").
    func analyse(caught s: CaughtStream, on page: CaughtPage, replacing: Bool = true, label: String? = nil, focus: Bool = true) {
        section = .download
        if replacing { for old in drafts where old.url == page.pageURL { close(old) } }
        let draft = Draft(url: page.pageURL, state: .analysing(page.pageURL, step: 1))
        func named(_ t: String?) -> String? { label.map { "\(t ?? page.pageURL.host ?? "Video") · \($0)" } ?? t }
        draft.title = named(page.title)
        drafts.append(draft)
        if focus { select(draft) }
        Task { @MainActor in
            do {
                let m = try await YtDlpEngine().analyse(caught: s, on: page, cancel: draft.token)
                draft.state = .ready(makeAnalysis(m)); draft.title = named(m.title)
            } catch let f as Failure {
                if f.kind != .cancelled { draft.state = .failed(page.pageURL, Diagnosis(f, engineVersion: ytdlpVersion)) }
            } catch {
                draft.state = .failed(page.pageURL, Diagnosis(ErrorClassifier.classify(stderr: "\(error)"), engineVersion: ytdlpVersion))
            }
        }
    }
    func findOnPage(_ url: URL) { PageCatcherWindow.show(url, model: self) }

    /// "Download from This Page": the engine reads the page with the Digby browser's session; if that can't
    /// find a video, the streams the player loaded are tried in order.
    func analyse(pageWithSession page: CaughtPage, fallback: [(CaughtStream, CaughtPage)]) {
        section = .download
        if let old = drafts.first(where: { $0.url == page.pageURL }) { close(old) }
        let draft = Draft(url: page.pageURL, state: .analysing(page.pageURL, step: 1))
        draft.title = page.title
        drafts.append(draft); select(draft)
        let token = draft.token
        Task { @MainActor in
            var firstFailure: Failure?
            do {
                switch try await YtDlpEngine().analyse(pageWithSession: page, cancel: token) {
                case .single(var m) where !FormatCatalogue(m).tiers.isEmpty || fallback.isEmpty:
                    // Some sites give signed-in visitors a generic name ("Video"): the page's own title is better.
                    if let t = page.title, m.title.count < 12 || m.title.lowercased() == "video" {
                        m.title = CaughtPage.cleanTitle(t, host: page.pageURL.host)
                    }
                    draft.state = .ready(makeAnalysis(m)); draft.title = m.title; return
                case .collection(let c):
                    let d = CollectionDraft(c); d.choices = profileChoices(); d.pageURL = draft.url; d.projectID = currentProjectID; draft.state = .collection(d); draft.title = c.title; return
                default: break
                }
            } catch let f as Failure { firstFailure = f } catch {}
            for (s, p) in fallback where !token.isCancelled {
                if var m = try? await YtDlpEngine().analyse(caught: s, on: p, cancel: token), !FormatCatalogue(m).tiers.isEmpty || s == fallback.last?.0 {
                    m.notice = "Caught from the page while it played."
                    draft.state = .ready(makeAnalysis(m)); draft.title = m.title; return
                }
            }
            if !token.isCancelled {
                draft.state = .failed(page.pageURL, Diagnosis(firstFailure ?? ErrorClassifier.classify(stderr: "ERROR: no video found"), engineVersion: ytdlpVersion))
            }
        }
    }

    /// Failures where playing the page in a browser can still find the video.
    static let pageCatchable: Set<Failure.Kind> = [.blocked, .unsupportedSite, .outdatedExtractor, .unknown, .unsupportedFormat,
                                                  .jsRuntime, .botCheck, .loginRequired, .unavailable]

    /// Playing a page out of sight for this link's site: true allowed, false "don't offer", nil not asked yet.
    func pageCatchAnswer(_ url: URL) -> Bool? {
        if ProcessInfo.processInfo.environment["DIGBY_DL_E2E"] != nil { return true }   // test runs: no one to ask
        return SiteKey.of(url).flatMap { settings.pageCatchSites?[$0] }
    }
    func setPageCatch(_ url: URL, allowed: Bool?) {
        guard let site = SiteKey.of(url) else { return }
        var sites = settings.pageCatchSites ?? [:]
        sites[site] = allowed
        settings.pageCatchSites = sites.isEmpty ? nil : sites
    }
    /// "Play the Page Out of Sight" on a failure card: remember the yes for this site, then read the link again.
    func allowPageCatch(andRetry url: URL) {
        setPageCatch(url, allowed: true)
        urlText = url.absoluteString
        analyse()
    }

    /// The automatic last resort: play the page invisibly and catch its video. True if it worked.
    /// Only for sites you've allowed; the first time, the failure card asks instead.
    func catchOnPage(_ url: URL, draft: Draft, token: CancelToken, choices: Choices?) async -> Bool {
        guard !token.isCancelled, AppSettings.persistent || ProcessInfo.processInfo.environment["DIGBY_DL_E2E"] != nil else { return false }
        // Signed in (or past a site check) in Digby's browser before? Read the page with that session first.
        if let session = await PageCatcher.rememberedSession(for: url),
           case .single(var m)? = try? await YtDlpEngine().analyse(pageWithSession: session, cancel: token), !FormatCatalogue(m).tiers.isEmpty {
            m.notice = "Read with your session from Digby’s browser."
            nextChoices = choices
            draft.state = .ready(makeAnalysis(m)); draft.title = m.title
            return true
        }
        guard pageCatchAnswer(url) == true, !token.isCancelled else { return false }
        draft.state = .analysing(url, step: 3)
        guard let (streams, page) = await HiddenCatch.run(url), !token.isCancelled else { return false }
        // The first candidate that has a picture wins; a sound-only one is kept as a last resort.
        var soundOnly: MediaInfo?
        for stream in streams.prefix(4) where !token.isCancelled {
            guard var m = try? await YtDlpEngine().analyse(caught: stream, on: page, cancel: token) else { continue }
            m.notice = "Digby couldn’t read this page directly, so it played the page and caught the video."
            if FormatCatalogue(m).tiers.isEmpty { if soundOnly == nil { soundOnly = m }; continue }
            nextChoices = choices
            draft.state = .ready(makeAnalysis(m)); draft.title = m.title
            return true
        }
        guard var m = soundOnly else { return false }
        m.notice = "Digby played the page but could only find its sound. Find the Video on the Page lets you try with the player yourself."
        nextChoices = choices
        draft.state = .ready(makeAnalysis(m)); draft.title = m.title
        return true
    }

    /// "Download Another" / clear: close the shown draft (other drafts carry on).
    func reset() { if let d = selectedDraft { close(d) }; urlText = "" }

    func refreshSignIns() { signIns = SignInSettings.load().sites }
    func requestSignIn(for url: URL) {
        signInRequest = SignInRequest(site: SignInSite.site(for: url) ?? .youtube, retry: url)
    }
    func signOut(_ site: SignInSite) { SignInStore.forget(site); refreshSignIns() }

    func pasteFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string) { urlText = s; if !Self.links(in: s).isEmpty { analyse() } }
    }

    /// When the app becomes active: offer a newly copied link (never downloads by itself).
    func checkClipboard() {
        guard watchClipboard else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChange else { return }
        lastPasteboardChange = pb.changeCount
        if let s = pb.string(forType: .string), let u = Self.links(in: s).first, s.count < 2000 { clipboardSuggestion = u }
    }

    /// http(s) links in free text, de-duplicated in order.
    static func links(in text: String) -> [URL] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { part -> URL? in
            var s = String(part)
            if !s.contains("://"), s.contains("."), !s.contains(" ") { s = "https://" + s }
            guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme), u.host != nil else { return nil }
            return seen.insert(u.absoluteString).inserted ? u : nil
        }
    }
    func alreadyQueued(_ url: URL) -> Bool {
        leaves.contains { item in
            switch item.work {
            case .planned(let r)?: r.media.webpageURL == url
            case .unplanned(let u, _, _, _)?: u == url
            default: false
            }
        }
    }

    // MARK: Queue

    /// Starts waiting downloads while fewer than `maxConcurrent` are running, oldest first.
    func pump() {
        let overnightNow = isOvernight()
        let waiting = leaves.filter { $0.state == .waiting && $0.work != nil && (!$0.overnight || overnightNow) }.reversed()   // queue is newest-first
        var running = activeCount
        var perHost: [String: Int] = [:]
        for a in leaves where a.isActive { perHost[host(a), default: 0] += 1 }
        for item in waiting where running < maxConcurrent {
            // Polite to each site: at most `perSite` downloads from the same website at once.
            guard perHost[host(item), default: 0] < perSite else { continue }
            running += 1; perHost[host(item), default: 0] += 1
            item.state = .analysing
            Task { @MainActor in await self.run(item) }
        }
    }

    private func run(_ item: QueueItem) async {
        item.startedAt = Date()
        while true {
            do { try await attempt(item); break }
            catch let f as Failure where f.kind != .cancelled {
                item.attempts += 1
                switch RecoveryPolicy.next(after: f, attempt: item.attempts, engineUpdateTried: item.engineUpdateTried) {
                case .retry(let delay, let reason):
                    item.state = .processing("\(reason) — trying again in \(Int(delay)) s")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                    if item.token.isCancelled { item.state = item.token.isPaused ? .paused(item.fraction ?? 0) : .cancelled; break }
                    continue
                case .updateEngineThenRetry:
                    item.engineUpdateTried = true
                    item.state = .processing("The site seems to have changed — updating the extraction engine")
                    let outcome = await EngineRecovery().updateExtractor(on: updateChannel, userChannel: updateChannel) { _ in }
                    await refreshEngines()
                    item.notes.append(outcome.message)
                    if outcome.updated && !item.token.isCancelled { continue }
                    fail(item, f)
                case .giveUp:
                    fail(item, f)
                }
                break
            } catch {
                break
            }
        }
        pump()
        installPendingUpdatesIfIdle()
    }

    private func fail(_ item: QueueItem, _ f: Failure) {
        item.failure = f
        if let url = workURL(item) { recordAttempt(url, failure: f) }
        item.state = .failed(f.title)
        if case .planned(let r)? = item.work { Downloader.discardWork(in: r.folder, id: item.workID) }
        if let url = workURL(item) {
            addHistory(HistoryEntry(title: item.title, site: item.site, url: url, file: nil, kind: item.choices?.kind ?? .videoAndAudio,
                                    detail: f.title, bytes: 0, succeeded: false, choices: item.choices, details: item.details))
            if let owner = draft(showing: item) {
                var d = Diagnosis(f, engineVersion: ytdlpVersion)
                for n in item.notes { d.whatDigbyDid.append((n, true)) }
                if item.engineUpdateTried { offerNightlyIfUseful(&d, f) }
                owner.state = .failed(url, d)
            }
        }
        Notifier.finished(item.title, ok: false)
    }

    /// One try at a download. Failures (other than cancel/pause) are thrown to `run` for recovery.
    private func attempt(_ item: QueueItem) async throws {
        do {
            var req = try await request(for: item)
            req.rateLimit = rateLimitForNewDownload()
            if req.plan.translateTo != nil { req.translator = SubtitleTranslation.translator() }
            item.state = .downloading(fraction: 0, speed: 0, remaining: nil)
            updateKeepAwake()
            let out = try await Downloader().download(req, cancel: item.token) { e in
                Task { @MainActor in self.apply(e, to: item) }
            }
            item.size = SizeEstimate(bytes: out.bytes, isExact: true)
            item.notes += out.warnings
            item.details?.finish(out)
            item.state = .done(out.file)
            addHistory(HistoryEntry(title: item.title, site: item.site, url: req.media.webpageURL, file: out.file, kind: req.plan.kind,
                                    detail: item.summary, bytes: out.bytes, succeeded: true, thumbnail: req.media.thumbnailURL, choices: item.choices,
                                    details: item.details))
            draft(showing: item)?.state = .completed(item)
            recordAttempt(req.media.webpageURL, failure: nil)
            Notifier.finished(item.title, ok: true)
            finished(item)
        } catch let f as Failure {
            if f.kind == .cancelled { item.state = item.token.isPaused ? .paused(item.fraction ?? 0) : .cancelled; return }
            throw f
        } catch {
            item.state = .failed("\(error)")
        }
    }

    /// Planned work as is; playlist entries are analysed and planned now, with the shared choices.
    private func request(for item: QueueItem) async throws -> DownloadRequest {
        switch item.work {
        case .planned(let r)?: return r
        case .unplanned(let url, let choices, let playlist, let index)?:
            item.phase = "Reading the page"
            guard case .single(let m) = try await YtDlpEngine().analyse(url, cancel: item.token) else {
                throw Failure(kind: .unsupportedFormat, title: "This entry is itself a playlist", explanation: "Open it on its own to choose its videos.",
                              retryable: false, suggestsEngineUpdate: false, detail: "")
            }
            let cat = FormatCatalogue(m)
            var plan = FormatSelector.select(cat, choices, playback: playback).plan
            // "Highest resolution" for a playlist: this tier, or the video's best below it — said in the notes.
            if plan == nil, case .tier(let t) = choices.resolution, let lower = cat.tiers.first(where: { $0 < t }) {
                var c = choices; c.resolution = .tier(lower)
                plan = FormatSelector.select(cat, c, playback: playback).plan
                plan?.notes.insert("This video’s highest resolution is \(lower.name), so it was downloaded at \(lower.name).", at: 0)
            }
            if plan == nil { var c = choices; c.container = .mkv; plan = FormatSelector.select(cat, c, playback: playback).plan
                plan?.notes.insert("Saved as MKV, because this video’s streams don’t fit the chosen file type without re-encoding.", at: 0) }
            guard let p = plan else {
                throw Failure(kind: .unsupportedFormat, title: "None of this video’s formats match your choices", explanation: "Open it on its own to choose.",
                              retryable: false, suggestsEngineUpdate: false, detail: "")
            }
            item.title = m.title; item.media = m; item.notes = p.notes; item.choices = choices
            item.details = DownloadDetails.make(catalogue: cat, choices: choices, plan: p)
            item.summary = p.chips(catalogue: cat).joined(separator: " · "); item.size = p.size
            var req = DownloadRequest(media: m, plan: p, folder: folder(for: p, playlist: playlist, destination: item.destination, media: m),
                                      fileName: FileNamer.render(playlist == nil ? nameTemplate : "{index} {title}", media: m, plan: p, playlist: playlist, index: index))
            req.workID = item.workID
            item.work = .planned(req)
            return req
        case nil:
            throw ErrorClassifier.cancelled()
        }
    }

    private func apply(_ e: DownloadEvent, to item: QueueItem) {
        guard item.isActive else { return }
        switch e {
        case .phase(let s):
            item.phase = s
            if s != "Downloading" { item.state = s == "Checking the file" ? .verifying : .processing(s) }
        case .progress(let d, let total, let speed, let eta):
            if let total, total > 0, item.size?.bytes != total { item.size = SizeEstimate(bytes: total, isExact: item.size?.isExact ?? false) }
            item.state = .downloading(fraction: total.map { Double(d) / Double(max(1, $0)) }, speed: speed ?? 0, remaining: eta)
        case .processing:
            break
        }
    }

    func workURL(_ item: QueueItem) -> URL? {
        switch item.work {
        case .planned(let r)?: r.media.webpageURL
        case .unplanned(let u, _, _, _)?: u
        default: nil
        }
    }

    func host(_ item: QueueItem) -> String { workURL(item)?.host?.replacingOccurrences(of: "www.", with: "") ?? item.site }

    /// Stops a download but keeps what has arrived; Resume continues from there.
    func pause(_ item: QueueItem) {
        if item.isPlaylist { item.children.filter(\.isActive).forEach(pause); item.children.filter { $0.state == .waiting }.forEach { $0.state = .paused(0) }; return }
        if item.isActive { item.token.pause() } else if item.state == .waiting { item.state = .paused(0) }
    }
    func resume(_ item: QueueItem) {
        if item.isPlaylist { item.children.filter { if case .paused = $0.state { true } else { false } }.forEach(resume); return }
        item.token = CancelToken(); item.state = .waiting
        pump()
    }

    func cancel(_ item: QueueItem) {
        item.token.cancel()
        if !item.isActive { item.state = .cancelled }
        for c in item.children { cancel(c) }
    }
    func retry(_ item: QueueItem) {
        item.token = CancelToken(); item.failure = nil; item.state = .waiting; item.attempts = 0; item.engineUpdateTried = false
        for c in item.children where { if case .failed = c.state { true } else if case .cancelled = c.state { true } else { false } }() { retry(c) }
        pump()
    }
    func remove(_ item: QueueItem) { cancel(item); queue.removeAll { $0 === item } }
    /// A finished download moves from Downloading to Downloaded (its playlist group once every video is done).
    func finished(_ item: QueueItem) {
        newlyDownloaded.insert(item.id.uuidString)
        if let entry = history.first { freshHistoryIDs.insert(entry.id) }
        func isDone(_ i: QueueItem) -> Bool { if case .done = i.state { return true }; return false }
        if let group = queue.first(where: { $0.children.contains { $0 === item } }) {
            if group.children.allSatisfy(isDone) { queue.removeAll { $0 === group } }
        } else {
            queue.removeAll { $0 === item }
        }
    }
    /// Downloaded entries finished this session (marked "New" until you've looked).
    var freshHistoryIDs: Set<String> = []
    var newlyDownloaded: Set<String> = []
    var unseenDownloaded: Int { freshHistoryIDs.count }
    func clearCompleted() {
        queue.removeAll { if case .done = $0.state { return true }; return $0.isPlaylist && $0.children.allSatisfy { if case .done = $0.state { true } else { false } } }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }


    /// Hands a finished video to Digby Video Compressor through its existing "open document" support.
    func compressWithDigby(_ file: URL) {
        let ws = NSWorkspace.shared
        // When it isn't installed the button explains that instead (no website link until the
        // Digby family has a neutral product domain: the current one carries a personal account name).
        guard let app = ws.urlForApplication(withBundleIdentifier: "app.digbyvideo.compressor") else { return }
        ws.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    var compressorInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.digbyvideo.compressor") != nil }
}

import UserNotifications
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    @MainActor static func post(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil, AppModel.shared?.notifyWhenDone == true, !NSApp.isActive else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    @MainActor static func finished(_ title: String, ok: Bool) {
        guard Bundle.main.bundleIdentifier != nil, AppModel.shared?.notifyWhenDone == true, !NSApp.isActive else { return }
        let c = UNMutableNotificationContent()
        c.title = ok ? "Downloaded" : "Download didn’t finish"
        c.body = title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
