import SwiftUI
import DigbyDesign
import DigbyDownloadCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            DownloadSettings().tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            BrowserSettings().tabItem { Label("Browser", systemImage: "safari") }
            EngineSettings().tabItem { Label("Engines", systemImage: "shippingbox") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            DiagnosticsSettings().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 680, height: 600)
    }
}

/// A settings row: a control with a plain-English line under it.
struct SettingRow<Control: View>: View {
    var title: String
    var help: String
    @ViewBuilder var control: Control
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            control
            Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            SettingRow(title: "Clipboard", help: "When you copy a link, Digby offers to download it. It never downloads anything by itself, and nothing you copy leaves your Mac.") {
                Toggle("Notice links I copy", isOn: $model.watchClipboard)
            }
            SettingRow(title: "Menu bar", help: "A small icon in the menu bar shows progress and lets you paste a link without opening the window.") {
                Toggle("Show Digby in the menu bar", isOn: $model.showMenuBarIcon)
            }
            SettingRow(title: "Shortcut", help: "Press this anywhere to download the link on your clipboard.") {
                LabeledContent("Download copied link") { Text("⌃⌥⌘D").font(.body.monospaced()).foregroundStyle(.secondary) }
            }
            SettingRow(title: "Notifications", help: "A notification when a download finishes or needs your attention.") {
                Toggle("Notify me when downloads finish", isOn: $model.notifyWhenDone)
            }
        }
        .formStyle(.grouped)
    }
}

struct DownloadSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Folders") {
                folderRow("Videos", model.videoFolder) { model.settings.videoFolder = $0?.path }
                folderRow("Audio", model.audioFolder) { model.settings.audioFolder = $0?.path }
                SettingRow(title: "Sort into folders", help: sortingHelp) {
                    Picker("Sort into folders", selection: Binding(get: { model.settings.folderSorting ?? .none }, set: { model.settings.folderSorting = $0 == .none ? nil : $0 })) {
                        ForEach(FolderSorting.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                SettingRow(title: "Playlists", help: "Each playlist goes into a folder named after it, with its videos numbered in order.") {
                    Toggle("Put playlists in their own folder", isOn: $model.settings.playlistSubfolders)
                }
            }
            Section {
                Picker("Default profile", selection: $model.defaultProfileID) {
                    ForEach(model.profiles) { Text($0.name).tag($0.id) }
                }
            }
            Section("File names") {
                FileNameBuilder()
            }
            if !model.settings.customProfiles.isEmpty {
                Section("Your profiles") {
                    ForEach(model.settings.customProfiles) { p in
                        HStack {
                            Text(p.name)
                            Text(summary(p.choices)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete") { model.deleteProfile(p) }
                        }
                    }
                }
            }
            Section("Speed and timing") {
                SettingRow(title: "Speed limit", help: "Leaves room for video calls and everyone else on your network. Shared between downloads running at the same time.") {
                    Picker("Speed limit", selection: Binding(get: { model.settings.speedLimit ?? 0 }, set: { model.settings.speedLimit = $0 == 0 ? nil : $0 })) {
                        Text("No limit").tag(0)
                        ForEach([1, 2, 5, 10, 25, 50], id: \.self) { mb in Text("\(mb) MB/s  (about \(mb * 8) Mbit/s)").tag(mb * 1_000_000) }
                    }
                }
                SettingRow(title: "Overnight hours", help: "Downloads marked with the moon wait for these hours: handy for big files, or internet that’s cheaper or quieter at night. Digby keeps your Mac awake while they wait (the screen can still sleep).") {
                    HStack {
                        Text("Overnight hours")
                        Spacer()
                        DatePicker("From", selection: minutes(\.overnightStart, 60), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("to").foregroundStyle(.secondary)
                        DatePicker("To", selection: minutes(\.overnightEnd, 420), displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
                Toggle("Download everything overnight unless I say otherwise",
                       isOn: Binding(get: { model.settings.alwaysOvernight ?? false }, set: { model.settings.alwaysOvernight = $0 }))
            }
            Section {
                SettingRow(title: "At once", help: "Two at a time is fast and polite. More can make sites slow you down.") {
                    Stepper("Download \(model.maxConcurrent) at a time", value: $model.maxConcurrent, in: 1...6)
                }
                SettingRow(title: "Per site", help: "How many downloads may come from the same website at once.") {
                    Stepper("\(model.perSite) per website", value: $model.perSite, in: 1...3)
                }
            }
        }
        .formStyle(.grouped)
    }

    var sortingHelp: String {
        let s = model.settings.folderSorting ?? .none
        var text = s.help
        if let sub = s.subfolder(media: SampleMedia.video) {
            text += " For example, “" + model.videoFolder.appendingPathComponent(sub).appendingPathComponent("Video.mp4").path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + "”."
        }
        return text + " Projects keep their own folder as it is. Earlier downloads stay where they are."
    }

    /// A time of day stored as minutes after midnight.
    func minutes(_ k: WritableKeyPath<AppSettings, Int?>, _ fallback: Int) -> Binding<Date> {
        Binding(get: {
            let m = model.settings[keyPath: k] ?? fallback
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            model.settings[keyPath: k] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
    func summary(_ c: Choices) -> String {
        var parts = [c.kind.label]
        if c.kind != .audioOnly {
            if case .tier(let t) = c.resolution { parts.append(t.name) } else { parts.append("Best") }
            parts.append(c.container.name)
        } else { parts.append(c.audioOutput.name) }
        return parts.joined(separator: " · ")
    }

    func folderRow(_ title: String, _ url: URL, set: @escaping (URL?) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                    p.directoryURL = url; p.prompt = "Use This Folder"
                    if p.runModal() == .OK, let u = p.url { set(u) }
                }
            }
        }
    }
}

struct EngineSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false
    @State private var checking = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Text("Websites change often. Digby keeps the components that do the downloading up to date by itself, checks every update is genuine before installing it, and keeps the previous version in case something goes wrong.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Components") {
                ForEach(model.engines) { e in
                    HStack(alignment: .top, spacing: 10) {
                        icon(e)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.name).fontWeight(.semibold)
                                Text(e.installed ?? "Not installed").font(.callout.monospaced()).foregroundStyle(.secondary)
                                if case .updateAvailable = e.state, let l = e.latest {
                                    Text("→ \(l)").font(.callout.monospaced()).foregroundStyle(Brand.accent)
                                }
                            }
                            Text(e.role).font(.caption).foregroundStyle(.secondary)
                            if let p = e.previous { Text("Previous version kept: \(p)").font(.caption2).foregroundStyle(.tertiary) }
                        }
                        Spacer()
                        if let t = e.tool {
                            if case .updateAvailable = e.state {
                                Button("Update") { Task { await model.updateNow(t) } }.buttonStyle(QuietButtonStyle()).disabled(model.activeCount > 0)
                                    .help(model.activeCount > 0 ? "Waits until nothing is downloading" : "")
                            }
                            if case .updating = e.state { ProgressView().controlSize(.small) }
                            if e.previous != nil, model.updatingTool == nil {
                                Button("Roll Back") { Task { await model.rollback(t) } }.buttonStyle(QuietButtonStyle(tint: .secondary))
                                    .help("Switch back to \(e.previous ?? "the previous version") if the current one causes problems")
                            }
                        }
                    }
                }
            }
            Section {
                Picker("Update channel", selection: $model.channel) {
                    Text("Stable").tag("Stable"); Text("Nightly").tag("Nightly"); Text("Experimental").tag("Experimental")
                }
                .onChange(of: model.channel) { _, _ in Task { checking = true; await model.checkEngineUpdates(force: true); checking = false } }
                Text(channelHelp).font(.caption).foregroundStyle(.secondary)
                Toggle("Install engine updates automatically", isOn: $model.installEngineUpdates)
                Text("Updates install between downloads, never during one.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Last checked") { Text(model.engines.first?.lastChecked.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet").foregroundStyle(.secondary) }
                HStack {
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    Button("Check Now") { Task { checking = true; await model.checkEngineUpdates(force: true); checking = false } }.disabled(checking)
                    Button("Update History…") { showHistory = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showHistory) { UpdateHistoryView(records: model.engineHistory) }
    }

    func icon(_ e: EngineStatus) -> some View {
        switch e.state {
        case .upToDate: Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.good)
        case .missing: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.warn)
        default: Image(systemName: "arrow.down.circle.fill").foregroundStyle(Brand.accent)
        }
    }

    var channelHelp: String {
        switch model.channel {
        case "Nightly": "Fixes for site changes arrive within a day. Very occasionally a nightly has a new bug; use Roll Back if so."
        case "Experimental": "Every change as soon as it’s made. For testing only."
        default: "Tested releases. Digby looks for a new one every few hours and fetches it at once when a site breaks; if that isn’t enough, it offers the Nightly build."
        }
    }
}

/// How downloads have gone, per site, counted on this Mac only. No links or titles are kept; nothing is sent.
struct DiagnosticsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false
    @State private var confirmClear = false
    var body: some View {
        let rows = model.siteStatsRows
        Form {
            Section {
                LabeledContent("Extraction engine") {
                    Text("yt-dlp \(model.ytdlpVersion ?? "not installed") · \(model.updateChannel.label)").foregroundStyle(.secondary)
                }
                LabeledContent("Last engine update") {
                    Text(model.lastEngineUpdate.map { "\($0.to), \($0.date.formatted(.relative(presentation: .named)))" } ?? "None yet").foregroundStyle(.secondary)
                }
                LabeledContent("Last checked") {
                    Text(model.engines.first?.lastChecked.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Digby looks for a new extraction engine every few hours. When a site seems to have changed, it fetches the newest one straight away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if rows.isEmpty {
                    Text("Nothing yet. Each download adds to this table.").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Site"); Text("Tries").gridColumnAlignment(.trailing); Text("Worked").gridColumnAlignment(.trailing); Text("Rate"); Text("Usual problem")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Divider()
                        ForEach(rows.prefix(12)) { r in
                            GridRow {
                                Text(r.site).lineLimit(1)
                                Text("\(r.attempts)").monospacedDigit()
                                Text("\(r.successes)").monospacedDigit()
                                RateBar(rate: r.successRate)
                                Text(r.commonFailure.map(Self.label) ?? "—").foregroundStyle(.secondary).lineLimit(1)
                            }
                            .font(.callout)
                        }
                    }
                    if rows.count > 12 { Text("And \(rows.count - 12) more sites in the copied report.").font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("How each site has worked")
            } footer: {
                Text("Kept only on this Mac: each site’s name, whether it worked, the kind of problem and the engine version. No links, titles or account details, and Digby never sends it anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Clear…") { confirmClear = true }.buttonStyle(QuietButtonStyle(tint: .secondary)).disabled(rows.isEmpty)
                Spacer()
                if copied { Text("Copied").font(.caption).foregroundStyle(.secondary) }
                Button("Copy Report") { model.copySiteReport(); copied = true }
                    .help("Copies a summary (sites and counts only) for you to paste into a bug report if you want to. Nothing is sent automatically.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the site table?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.clearSiteStats() }
        } message: { Text("The counts start again from zero. Your downloads and history aren’t affected.") }
    }

    static func label(_ k: Failure.Kind) -> String {
        switch k {
        case .outdatedExtractor, .jsRuntime: "Site changed"
        case .botCheck: "Human check"
        case .loginRequired: "Sign-in needed"
        case .privateMedia: "Private"
        case .unavailable: "Unavailable"
        case .geoRestricted: "Region"
        case .network: "Connection"
        case .rateLimited: "Rate limited"
        case .blocked: "Blocked network"
        case .unsupportedSite: "Not supported"
        case .drm: "Copy-protected"
        default: "Other"
        }
    }
}

/// A success rate as a short bar and a percentage.
struct RateBar: View {
    var rate: Double
    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(rate >= 0.8 ? Brand.good : rate >= 0.5 ? Brand.accent : Brand.warn).frame(width: 60 * rate)
            }
            .frame(width: 60, height: 6)
            Text("\(Int((rate * 100).rounded()))%").monospacedDigit().frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(Int((rate * 100).rounded())) percent worked")
    }
}

struct UpdateHistoryView: View {
    var records: [UpdateRecord]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update history").font(TypeStyle.title)
            if records.isEmpty { Text("No updates yet.").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(records.reversed().enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .firstTextBaseline) {
                            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                            Text("\(r.tool.displayName) \(r.from.map { "\($0) → " } ?? "")\(r.to)").font(.callout.monospaced())
                            Spacer()
                            Text(r.outcome.hasPrefix("failed") ? "Not installed" : r.outcome.capitalized)
                                .font(.caption).foregroundStyle(r.outcome.hasPrefix("failed") ? Brand.warn : .secondary)
                                .help(r.outcome)
                        }
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22).frame(width: 560, height: 420)
    }
}

struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    func describe(_ s: SignInSettings.Source?) -> String {
        switch s {
        case .browser(let b)?: "Using your \(b.displayName) sign-in"
        case .digbyWindow?: "Signed in inside Digby"
        case nil: "Not signed in"
        }
    }
    var body: some View {
        Form {
            Section {
                InfoRow("Links, files and sign-in details never leave your Mac, except to the website you’re downloading from.", systemImage: "lock.shield", tint: Brand.good)
                InfoRow("Digby only contacts GitHub and the FFmpeg build server to check for engine updates.", systemImage: "network", tint: .secondary)
                InfoRow("Diagnostic reports remove links, cookies and your user name before you see or share them.", systemImage: "doc.text.magnifyingglass", tint: .secondary)
            }
            Section("Sign-ins") {
                ForEach(Array(Set(SignInSite.known + model.signIns.keys)).sorted { ($0.isYouTubeSite ? 0 : 1, $0.rawValue) < ($1.isYouTubeSite ? 0 : 1, $1.rawValue) }) { site in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.displayName)
                            Text(describe(model.signIns[site])).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.signIns[site] != nil { Button("Sign Out") { model.signOut(site) } }
                        Button(model.signIns[site] == nil ? "Set Up…" : "Change…") { model.signInRequest = .init(site: site, retry: nil) }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Any other site that turns Digby away")
                        Text(SignInSettings.load().anySite.map { "Tries your \($0.displayName) sign-in once, automatically" } ?? "Off")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if SignInSettings.load().anySite != nil {
                        Button("Turn Off") { var s = SignInSettings.load(); s.anySite = nil; try? s.save(); model.refreshSignIns() }
                    }
                }
                Text("Needed on VPNs and for videos only signed-in viewers can watch. A browser sign-in is read fresh each time and never stored; a sign-in made inside Digby keeps only that site’s cookies, readable only by you. Either way they’re sent only to that site.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Digby’s browser") {
                SettingRow(title: "Browser data", help: "“Find the Video on the Page” uses Digby’s own browser. It remembers sign-ins and site checks so you don’t repeat them, and shares nothing with your other browsers.") {
                    HStack {
                        Text("Remembered sign-ins and site checks")
                        Spacer()
                        Button("Forget All") { Task { await PageCatcher.forgetEverything() } }
                    }
                }
            }
            Section("Playing pages out of sight") {
                let sites = (model.settings.pageCatchSites ?? [:]).sorted { $0.key < $1.key }
                if sites.isEmpty {
                    Text("No sites yet. When Digby can’t read a page, it offers to play it in a hidden window and catch the video, and asks once for each site.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sites, id: \.key) { site, allowed in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site)
                                Text(allowed ? "Allowed: plays the page out of sight when needed" : "Not offered")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = URL(string: "https://\(site)") {
                                Button(allowed ? "Don’t Allow" : "Allow") { model.setPageCatch(url, allowed: !allowed) }
                                Button("Ask Again") { model.setPageCatch(url, allowed: nil) }
                                    .help("Forget this answer; Digby will ask the next time it’s needed")
                            }
                        }
                    }
                    Text("The page runs in Digby’s browser like a visit of your own, with the sound off. Anything the site saves stays there until you choose Forget All above.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One click from the browser to Digby: a button for Chrome-family browsers, and a bookmark for any browser
/// (Safari included). Both just open the page in Digby for you to choose; nothing downloads by itself.
struct BrowserSettings: View {
    static let bookmarklet = "javascript:location.href='digby-video://download?url='+encodeURIComponent(location.href)"
    @State private var copied = false

    struct Browser: Identifiable { let id: String; let name: String; let extensionsPage: String }
    static let chromeFamily = [
        Browser(id: "com.google.Chrome", name: "Chrome", extensionsPage: "chrome://extensions"),
        Browser(id: "com.brave.Browser", name: "Brave", extensionsPage: "brave://extensions"),
        Browser(id: "com.microsoft.edgemac", name: "Edge", extensionsPage: "edge://extensions"),
        Browser(id: "company.thebrowser.Browser", name: "Arc", extensionsPage: "arc://extensions"),
        Browser(id: "com.vivaldi.Vivaldi", name: "Vivaldi", extensionsPage: "vivaldi://extensions"),
    ]
    var installed: [Browser] { Self.chromeFamily.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil } }

    var body: some View {
        Form {
            Section {
                InfoRow("From the browser, send the page you’re watching to Digby in one click. Digby reads it and shows your choices, as if you’d pasted the link. Nothing downloads until you say so, and the button collects nothing.",
                        systemImage: "hand.tap", tint: Brand.accent)
            }
            Section("Any browser, including Safari: the Digby bookmark") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("⤓ Download with Digby")
                            .font(.callout.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Brand.accent.opacity(0.15))).foregroundStyle(Brand.accent)
                            .onDrag { NSItemProvider(object: (URL(string: Self.bookmarklet) ?? URL(string: "about:blank")!) as NSURL) }
                            .help("Drag me to your browser’s favourites or bookmarks bar")
                        Text("Drag this to your favourites bar").foregroundStyle(.secondary)
                        Spacer()
                        Button(copied ? "Copied" : "Copy Bookmark") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Self.bookmarklet, forType: .string)
                            copied = true
                        }
                    }
                    Text("Or add any bookmark and paste the copied text as its address. Click it on a video page; the first time, the browser asks to open Digby Video Downloader: choose Allow.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Chrome, Brave, Edge, Arc and Vivaldi: the Digby button") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Adds a Digby button to the toolbar, and “Download with Digby” when you right-click a page, video or link.")
                        .font(.callout)
                    Text("1. Click “Show Extension Folder” below.\n2. Open your browser’s Extensions page and switch on Developer mode.\n3. Click “Load unpacked” and choose the folder.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 8) {
                        Button("Show Extension Folder") { revealExtension() }.fixedSize()
                        ForEach(installed) { b in
                            Button("Open \(b.name)’s Extensions") { openExtensionsPage(b) }.fixedSize()
                        }
                    }
                    Text("A Safari button needs Apple’s developer tools to build and is planned; the bookmark above works in Safari today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Copies the extension somewhere stable (browsers keep loading it from there), then shows it.
    func revealExtension() {
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("Browser Extension") else { return }
        let dest = Paths.home.appendingPathComponent("Browser Extension", isDirectory: true)
        try? FileManager.default.createDirectory(at: Paths.home, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    func openExtensionsPage(_ b: Browser) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.id), let page = URL(string: b.extensionsPage) else { return }
        NSWorkspace.shared.open([page], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
