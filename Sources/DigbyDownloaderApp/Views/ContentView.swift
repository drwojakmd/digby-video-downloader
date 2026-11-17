import SwiftUI
import DigbyDesign
import DigbyDownloadCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            DetailRoot(dropTargeted: dropTargeted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let web = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            guard !web.isEmpty else { return false }
            model.urlText = web.map(\.absoluteString).joined(separator: "\n"); model.analyse(); return true
        } isTargeted: { dropTargeted = $0 }
        .sheet(item: $model.signInRequest) { r in SignInSheet(site: r.site, retry: r.retry).environment(model) }
        .sheet(item: $model.detailsShown) { d in DetailsView(details: d).environment(model) }
        .sheet(item: $model.newProjectRequest) { r in ProjectSheet(request: r).environment(model) }
        .sheet(item: $model.watchRequest) { d in WatchSheet(draft: d).environment(model) }
        // How many are downloading, on the Dock icon (like Safari's downloads).
        .onChange(of: model.activeCount, initial: true) { _, n in NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil }
    }
}

struct DetailRoot: View {
    @Environment(AppModel.self) private var model
    var dropTargeted: Bool
    var body: some View {
        VStack(spacing: 0) {
            if let banner = model.engineBanner { EngineBanner(text: banner) }
            if !model.resumeOffer.isEmpty { ResumeBanner() }
            // The link bar: always there (except on the welcome screen, which has its own big field).
            if !(model.section == .download && model.drafts.isEmpty) {
                LinkBar()
            }
            Group {
                switch model.section {
                case .download: ComposerView(dropTargeted: dropTargeted)
                case .queue: QueueView()
                case .history: HistoryView(project: model.project(model.selectedProjectID))
                case .watching: WatchingView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            List(selection: Binding<SidebarTag?>(
                get: { model.section == .history && model.selectedProjectID != nil ? .project(model.selectedProjectID!) : .section(model.section) },
                set: { tag in
                    switch tag {
                    case .section(let s)?: model.section = s; model.selectedProjectID = nil
                    case .project(let id)?: if let p = model.project(id) { model.openProject(p) }
                    case nil: break
                    }
                })) {
                sectionRow(.download)
                if model.linksAsList {
                    ForEach(model.drafts) { d in
                        DraftRow(draft: d).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)).selectionDisabled()
                    }
                }
                sectionRow(.queue)
                let showing = model.sidebarDownloads
                ForEach(showing.prefix(4)) { i in
                    SidebarDownloadRow(item: i).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)).selectionDisabled()
                }
                if showing.count > 4 {
                    Button { model.section = .queue } label: {
                        Text("and \(showing.count - 4) more").font(.caption).foregroundStyle(.secondary).padding(.leading, 26)
                    }
                    .buttonStyle(.plain).selectionDisabled()
                }
                sectionRow(.history)
                sectionRow(.watching)
                Section("Projects") {
                    ForEach(model.projects) { p in ProjectRow(project: p).tag(SidebarTag.project(p.id)) }
                    Button { model.newProjectRequest = NewProjectRequest() } label: {
                        Label("New Project…", systemImage: "plus").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).selectionDisabled()
                    .help("A folder of its own for downloads that belong together, such as kids’ cartoons or research for a project")
                }
            }
            .listStyle(.sidebar)
            EngineFooter()
        }
    }

    @ViewBuilder func sectionRow(_ s: SidebarSection) -> some View {
                    HStack {
                        Label(s.title, systemImage: s.symbol)
                        Spacer()
                        if s == .history, model.unseenDownloaded > 0 {
                            Text("\(model.unseenDownloaded) new").font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Brand.dawn.opacity(0.2))).foregroundStyle(Brand.dawn)
                        }
                        if s == .watching, !model.watches.isEmpty {
                            Text("\(model.watches.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        if s == .queue, model.activeCount > 0 {
                            Text("\(model.activeCount)").font(.caption.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Brand.accent.opacity(0.15))).foregroundStyle(Brand.accent)
                        }
                    }
                    .tag(SidebarTag.section(s))
    }
}

/// The engines' state, always visible but quiet.
struct EngineFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        let pending = model.engines.filter { if case .updateAvailable = $0.state { true } else { false } }
        Button { openSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: pending.isEmpty ? "checkmark.seal" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(pending.isEmpty ? Brand.good : Brand.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.updatingTool != nil ? "Updating an engine…" : model.engines.contains { $0.state == .missing } ? "Setting up engines"
                         : pending.isEmpty ? "Engines up to date" : "Engine update ready").font(.caption.weight(.medium))
                    Text(pending.isEmpty ? (model.engines.first?.lastChecked.map { "Checked " + $0.formatted(.relative(presentation: .named)) } ?? "Not checked yet")
                         : pending.map(\.name).joined(separator: ", ") + (model.installEngineUpdates ? " · installs between downloads" : " · see Settings"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Digby keeps its download engines up to date by itself. Click for details.")
    }
}

struct ResumeBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let n = model.resumeOffer.count
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle").foregroundStyle(Brand.accent)
            Text("\(n) download\(n == 1 ? "" : "s") didn’t finish last time.").font(.callout)
            Spacer()
            Button("Discard") { model.discardUnfinished() }.buttonStyle(QuietButtonStyle(tint: .secondary))
            Button("Continue") { model.resumeUnfinished() }.buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Brand.accent.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct EngineBanner: View {
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Brand.accent.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Paste a link from anywhere in the app. Visually its own strip, above whatever you're looking at.
struct LinkBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        // A strip of its own, like a browser's address bar: a faint tint of the brand colour sets it apart from
        // the page below, and the field sits raised on it.
        HStack(spacing: 12) {
            URLBar(compact: true).frame(maxWidth: Metrics.contentMaxWidth + 40)
            ProjectChip()
        }
        .padding(.horizontal, 22).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.bar)
                LinearGradient(colors: [Brand.accent.opacity(0.07), Brand.accent.opacity(0.03)], startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A download in progress, shown under Downloading in the sidebar: its state at a glance from anywhere.
struct SidebarDownloadRow: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            ring.frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(failed ? Brand.warn : .secondary).lineLimit(1).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.secondary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.section = .queue
            withAnimation(.easeOut(duration: 0.18)) { _ = model.expandedQueueIDs.insert(item.id) }
        }
        .onHover { hover = $0 }
        .help("Show this download and its details")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    var failed: Bool { if case .failed = item.state { true } else { false } }

    @ViewBuilder var ring: some View {
        switch item.state {
        case .failed: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(Brand.warn)
        case .paused: Image(systemName: "pause.circle").font(.system(size: 12)).foregroundStyle(.secondary)
        case .waiting: Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.secondary)
        default:
            ZStack {
                Circle().stroke(Brand.accent.opacity(0.2), lineWidth: 2)
                Circle().trim(from: 0, to: max(item.fraction ?? 0.04, 0.04))
                    .stroke(Brand.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .padding(1)
            .animation(.linear(duration: 0.25), value: item.fraction)
        }
    }

    var subtitle: String {
        switch item.state {
        case .waiting: item.overnight ? "Overnight, from \(AppModel.clock(model.overnightStart))" : "Waiting"
        case .analysing: "Starting…"
        case .downloading(let f, _, let rem):
            [f.map { "\(Int($0 * 100))%" }, rem.map { Fmt.remaining($0) }].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Downloading…"
        case .processing: "Finishing…"
        case .verifying: "Checking the file…"
        case .paused(let f): "Paused at \(Int(f * 100))%"
        case .failed: "Didn’t work"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

enum SidebarTag: Hashable { case section(SidebarSection), project(String) }

/// A project in the sidebar: its symbol, name and how many downloads it holds.
struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var body: some View {
        HStack {
            Label(project.name, systemImage: project.symbol)
            Spacer()
            let n = model.historyCount(in: project)
            if n > 0 { Text("\(n)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.folderURL]) }
            Button("Edit Project…") { model.newProjectRequest = NewProjectRequest(editing: project) }
            Divider()
            Button("Remove from Digby") { model.removeProject(project) }
        }
        .help(project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }
}
