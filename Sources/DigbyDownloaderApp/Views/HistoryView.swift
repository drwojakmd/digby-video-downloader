import SwiftUI
import QuickLook
import DigbyDesign
import DigbyDownloadCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    /// Shown as a project: only downloads saved in its folder.
    var project: Project? = nil
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var width: CGFloat = 900
    @State private var selectedID: String?
    @State private var quickLook: URL?
    @FocusState private var listFocused: Bool

    enum Filter: String, CaseIterable { case all = "All", video = "Video", audio = "Audio", failed = "Didn’t work" }

    var records: [HistoryEntry] {
        _ = model.history.count      // refresh when history changes
        let all: [HistoryEntry] = switch filter {
        case .all: model.searchHistory(search, audio: nil, failed: false)
        case .video: model.searchHistory(search, audio: false, failed: false)
        case .audio: model.searchHistory(search, audio: true, failed: false)
        case .failed: model.searchHistory(search, audio: nil, failed: true)
        }
        guard let project else { return all }
        return all.filter { project.contains($0.file) }
    }

    /// Today, Yesterday, Earlier This Week, Earlier This Month, then by month.
    static func groups(_ rs: [HistoryEntry], now: Date = Date()) -> [(title: String, items: [HistoryEntry])] {
        let cal = Calendar.current
        func title(_ d: Date) -> String {
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day, days < 7 { return "Earlier This Week" }
            if cal.isDate(d, equalTo: now, toGranularity: .month) { return "Earlier This Month" }
            return d.formatted(.dateTime.month(.wide).year())
        }
        var out: [(String, [HistoryEntry])] = []
        for r in rs {
            let t = title(r.date)
            if out.last?.0 == t { out[out.count - 1].1.append(r) } else { out.append((t, [r])) }
        }
        return out.map { (title: $0.0, items: $0.1) }
    }

    var body: some View {
        let rs = records
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let project {
                    ProjectHeader(project: project, count: rs.filter(\.succeeded).count)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloaded").font(TypeStyle.title)
                        Text("Everything you’ve downloaded, newest first. Select one and press Space to preview it.").font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)
            HStack(spacing: 7) {
                ForEach(Filter.allCases, id: \.self) { f in PillButton(f.rawValue, selected: filter == f) { filter = f } }
                Spacer(minLength: 12)
                SearchField(text: $search, prompt: project == nil ? "Search titles and sites" : "Search this project").frame(width: width < 700 ? 170 : 220)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            Divider()
            if rs.isEmpty {
                if let project, search.isEmpty, filter == .all {
                    ContentUnavailableView {
                        Label("Nothing in \(project.name) yet", systemImage: project.symbol)
                    } description: {
                        Text(model.currentProjectID == project.id
                             ? "Paste links in the bar above: they’re saved into this project’s folder and listed here."
                             : "Choose “Save New Links Here”, or pick this project under “Save into” when you download.")
                    }
                } else {
                    ContentUnavailableView.search(text: search)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                            ForEach(Self.groups(rs), id: \.title) { g in
                                Section {
                                    ForEach(g.items) { r in
                                        HistoryRow(record: r, layout: .init(width: width), selected: selectedID == r.id,
                                                   select: { selectedID = r.id; listFocused = true },
                                                   quickLook: { selectedID = r.id; preview(r) })
                                            .id(r.id)
                                    }
                                } header: {
                                    Text(g.title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 10)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.space) { if let r = rs.first(where: { $0.id == selectedID }) { preview(r) }; return .handled }
                    .onKeyPress(.downArrow) { move(1, in: rs, proxy: proxy); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: rs, proxy: proxy); return .handled }
                    .onKeyPress(.return) {
                        if let r = rs.first(where: { $0.id == selectedID }), let f = r.file, FileManager.default.fileExists(atPath: f.path) { NSWorkspace.shared.open(f) }
                        return .handled
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .quickLookPreview($quickLook, in: rs.compactMap { r in r.file.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } })
    }

    func preview(_ r: HistoryEntry) {
        guard let f = r.file, FileManager.default.fileExists(atPath: f.path) else { return }
        quickLook = quickLook == f ? nil : f
    }

    func move(_ by: Int, in rs: [HistoryEntry], proxy: ScrollViewProxy) {
        let i = rs.firstIndex { $0.id == selectedID }.map { $0 + by } ?? 0
        guard rs.indices.contains(i) else { return }
        selectedID = rs[i].id
        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(rs[i].id) }
        if quickLook != nil, let f = rs[i].file, FileManager.default.fileExists(atPath: f.path) { quickLook = f }
    }
}

/// How much room a row has for its buttons. Rows never squeeze words into broken lines: as the window
/// narrows, labelled buttons become icons, then move into the ⋯ menu (which always has everything).
enum RowLayout {
    case wide, medium, narrow
    init(width: CGFloat) { self = width >= 900 ? .wide : width >= 600 ? .medium : .narrow }
}

struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    var record: HistoryEntry
    var layout: RowLayout = .wide
    var selected = false
    var select: () -> Void = {}
    var quickLook: () -> Void = {}
    var fileExists: Bool { record.file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: record.thumbnail ?? record.details?.thumbnail, seed: record.title, file: fileExists ? record.file : nil).frame(width: 64, height: 36)
                .overlay { if record.kind == .audioOnly { Image(systemName: "waveform").foregroundStyle(.white).font(.system(size: 14, weight: .semibold)) } }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.title).lineLimit(1)
                    if model.freshHistoryIDs.contains(record.id) { Chip("New", tint: Brand.dawn) }
                }
                HStack(spacing: 4) {
                    SourceLink(site: record.site, url: record.url)
                    Text("· " + [record.date.formatted(.relative(presentation: .named)), record.detail,
                                 record.succeeded ? Fmt.bytes(record.bytes) : nil].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(record.succeeded ? Color.secondary : Brand.warn).lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if record.succeeded, record.file != nil, !fileExists, layout != .narrow {
                    Text("File moved or deleted").font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
                if record.succeeded, let f = record.file, fileExists {
                    Button("Open") { NSWorkspace.shared.open(f) }.buttonStyle(QuietButtonStyle(tint: .secondary))
                    switch layout {
                    case .wide: Button("Show in Finder") { model.reveal(f) }.buttonStyle(QuietButtonStyle(tint: .secondary))
                    case .medium: RoundIconButton("magnifyingglass", help: "Show in Finder") { model.reveal(f) }
                    case .narrow: EmptyView()
                    }
                }
                if let d = record.details, layout != .narrow {
                    if layout == .wide {
                        Button("Details") { model.detailsShown = d }.buttonStyle(QuietButtonStyle(tint: .secondary))
                            .help("The original video, what you chose, and what Digby checked")
                    } else {
                        RoundIconButton("info", help: "Details: the original video, what you chose, and what Digby checked") { model.detailsShown = d }
                    }
                }
                if layout != .narrow || !record.succeeded {
                    Button(record.succeeded ? "Download Again" : "Try Again") { downloadAgain() }
                        .help(record.choices == nil ? "" : "Uses the same choices as last time")
                        .buttonStyle(QuietButtonStyle())
                }
                Menu {
                    if record.succeeded, let f = record.file, fileExists {
                        Button("Open") { NSWorkspace.shared.open(f) }
                        Button("Quick Look  (Space)") { quickLook() }
                        Button("Show in Finder") { model.reveal(f) }
                    }
                    if let d = record.details { Button("Details") { model.detailsShown = d } }
                    Button(record.succeeded ? "Download Again" : "Try Again") { downloadAgain() }
                    Divider()
                    Button("Copy Link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.url.absoluteString, forType: .string) }
                    Button("Open Original Page") { NSWorkspace.shared.open(record.url) }
                    if record.succeeded, record.kind != .audioOnly, fileExists, let f = record.file, model.compressorInstalled {
                        Button("Compress with Digby") { model.compressWithDigby(f) }
                    }
                    Divider()
                    Button("Remove from History") { model.removeHistory(record) }
                    if fileExists, let f = record.file {
                        Button("Remove and Move File to Trash…") { trash(f) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("More: open, details, copy link, remove…")
            }
            .fixedSize()
            .opacity(hover || selected ? 1 : 0.55)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Brand.accent.opacity(0.13) : hover ? Color.secondary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { if let d = record.details { model.detailsShown = d } })
        .simultaneousGesture(TapGesture().onEnded { select() })
        // Drag a finished video straight into Finder, Mail, an editor…
        .onDrag { (fileExists ? record.file.flatMap { NSItemProvider(contentsOf: $0) } : nil) ?? NSItemProvider(object: record.url as NSURL) }
    }

    func downloadAgain() {
        model.nextChoices = record.choices
        model.urlText = record.url.absoluteString; model.analyse()
    }

    /// Deleting a downloaded file is never automatic: it's asked for explicitly, and goes to the Trash.
    func trash(_ f: URL) {
        let a = NSAlert()
        a.messageText = "Move “\(f.lastPathComponent)” to the Trash?"
        a.informativeText = "The record is removed from History too. You can restore the file from the Trash."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: f, resultingItemURL: nil)
        model.removeHistory(record)
    }
}
