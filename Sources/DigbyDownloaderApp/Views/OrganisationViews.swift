import SwiftUI
import AppKit
import DigbyDesign
import DigbyDownloadCore

// MARK: - Projects

/// "Saving into Kids' Cartoons ✕": shown wherever you paste links while a project is open.
struct ProjectChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let p = model.currentProject {
            HStack(spacing: 6) {
                Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold))
                Text("Saving into ").foregroundStyle(.secondary) + Text(p.name).fontWeight(.semibold)
                Button { model.currentProjectID = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 14)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Back to your usual folders for new links (this project stays in the sidebar)")
                .accessibilityLabel("Stop saving into \(p.name)")
            }
            .font(.callout).lineLimit(1).fixedSize()
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
            .background(Capsule().fill(Brand.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Brand.accent.opacity(0.35), lineWidth: 0.5))
            .foregroundStyle(Brand.accent)
            .help("New links are saved into \(p.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        }
    }
}

/// Where this download goes: your usual folder, or one of your projects (or a new one).
struct SaveToMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var projectID: String?
    var audio: Bool
    var onNewProject: () -> Void

    var body: some View {
        let p = model.project(projectID)
        Menu {
            Button { projectID = nil } label: {
                Label("\(audio ? "Music" : "Videos") (your usual folder)", systemImage: projectID == nil ? "checkmark" : "folder")
            }
            if !model.projects.isEmpty {
                Section("Projects") {
                    ForEach(model.projects) { pr in
                        Button { projectID = pr.id } label: { Label(pr.name, systemImage: projectID == pr.id ? "checkmark" : pr.symbol) }
                    }
                }
            }
            Divider()
            Button("New Project…", action: onNewProject)
        } label: {
            Label(p?.name ?? FileManager.default.displayName(atPath: (audio ? model.audioFolder : model.videoFolder).path),
                  systemImage: p?.symbol ?? "folder")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(p == nil ? Color.secondary : Brand.accent)
        .help(p.map { "Saved into the project “\($0.name)” (\($0.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")))" }
              ?? "Saved into your usual folder. Choose a project to keep this with other downloads that belong together.")
    }
}

/// Create or edit a project: a name, a symbol, and where its folder lives.
struct ProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: NewProjectRequest
    @State private var name = ""
    @State private var symbol = "folder.fill"
    @State private var folder: URL?

    var editing: Project? { request.editing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "New Project" : "Edit Project").font(TypeStyle.title)
            Text("A project is a folder of its own for downloads that belong together, such as cartoons for the kids or research for a talk. Open it in the sidebar to see just those, and links you paste while it’s open go straight into it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name, e.g. Kids’ Cartoons", text: $name).textFieldStyle(.roundedBorder).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("Symbol").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Project.symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s).frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7).fill(symbol == s ? Brand.accent.opacity(0.2) : Color.secondary.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(symbol == s ? Brand.accent : .clear, lineWidth: 1))
                                .foregroundStyle(symbol == s ? Brand.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(folderPath).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                    p.prompt = "Use This Folder"; p.directoryURL = folder ?? model.videoFolder
                    if p.runModal() == .OK { folder = p.url }
                }
            }
            if editing != nil {
                InfoRow("Renaming the project doesn’t rename its folder. Removing a project never deletes its folder or files.", systemImage: "info.circle")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Project" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if let e = editing { name = e.name; symbol = e.symbol; folder = e.folderURL }
        }
    }

    var folderPath: String {
        let f = folder ?? editing?.folderURL
            ?? model.videoFolder.appendingPathComponent(FileNamer.sanitize(name.isEmpty ? "New Project" : name))
        return f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    func save() {
        if var e = editing {
            e.name = name.trimmingCharacters(in: .whitespaces); e.symbol = symbol
            if let f = folder { e.folder = f.path; try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true) }
            model.updateProject(e)
        } else {
            let p = model.createProject(name: name, symbol: symbol, folder: folder)
            if let a = request.forAnalysis { a.projectID = p.id }
            else if let c = request.forCollection { c.projectID = p.id }
            else { model.openProject(p) }
        }
        dismiss()
    }
}

/// At the top of an open project: what it is, where its folder is, and that new links go into it.
struct ProjectHeader: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: project.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Brand.accent)
                .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 12).fill(Brand.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(TypeStyle.title).lineLimit(1)
                Text("\(count) download\(count == 1 ? "" : "s") · \(project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if model.currentProjectID != project.id {
                Button("Save New Links Here") { model.currentProjectID = project.id }.buttonStyle(QuietButtonStyle())
            } else {
                Label("New links go here", systemImage: "checkmark").font(.callout).foregroundStyle(Brand.good).fixedSize()
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.folderURL]) }.buttonStyle(QuietButtonStyle(tint: .secondary))
            Menu {
                Button("Edit Project…") { model.newProjectRequest = NewProjectRequest(editing: project) }
                Divider()
                Button("Remove from Digby (keeps the folder)") { model.removeProject(project) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }
}

// MARK: - Watching

/// Channels and playlists Digby checks for new videos.
struct WatchingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watching").font(TypeStyle.title)
                    Text("Channels and playlists Digby checks every 3 hours while it’s open. New videos download by themselves, with the choices you saved.")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                Button("Check All Now") { Task { for w in model.watches { await model.check(w) } } }
                    .buttonStyle(QuietButtonStyle()).disabled(model.watches.isEmpty || !model.checkingWatchIDs.isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            if model.watches.isEmpty {
                ContentUnavailableView {
                    Label("Not watching anything yet", systemImage: "bell")
                } description: {
                    Text("Paste a channel or playlist link, then choose “Watch for New Videos”. Digby downloads each new video as it appears.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) { ForEach(model.watches) { WatchRow(watch: $0) } }
                        .padding(20).frame(maxWidth: Metrics.contentMaxWidth + 80).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct WatchRow: View {
    @Environment(AppModel.self) private var model
    var watch: Watch
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: watch.paused ? "bell.slash" : "bell.badge").font(.system(size: 18)).foregroundStyle(watch.paused ? Color.secondary : Brand.accent)
                .frame(width: 40, height: 40).background(Circle().fill(Brand.accent.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(watch.title).font(TypeStyle.headline).lineLimit(1)
                HStack(spacing: 4) {
                    SourceLink(site: watch.site, url: watch.url)
                    Text("· " + summary).foregroundStyle(watch.lastError == nil ? Color.secondary : Brand.warn).lineLimit(1)
                }
                .font(.caption)
                Text(choiceLine).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.checkingWatchIDs.contains(watch.id) { ProgressView().controlSize(.small) }
            Button("Check Now") { Task { await model.check(watch) } }.buttonStyle(QuietButtonStyle(tint: .secondary))
                .disabled(model.checkingWatchIDs.contains(watch.id))
            Menu {
                Button(watch.paused ? "Resume Watching" : "Pause Watching") {
                    if let i = model.watches.firstIndex(where: { $0.id == watch.id }) { model.watches[i].paused.toggle() }
                }
                Menu("Save Into") {
                    Button { setProject(nil) } label: { Label("Your usual folder", systemImage: watch.projectID == nil ? "checkmark" : "folder") }
                    ForEach(model.projects) { p in
                        Button { setProject(p.id) } label: { Label(p.name, systemImage: watch.projectID == p.id ? "checkmark" : p.symbol) }
                    }
                }
                Button("Open Page") { NSWorkspace.shared.open(watch.url) }
                Divider()
                Button("Stop Watching") { model.stopWatching(watch) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    func setProject(_ id: String?) { if let i = model.watches.firstIndex(where: { $0.id == watch.id }) { model.watches[i].projectID = id } }

    var summary: String {
        if watch.paused { return "Paused" }
        if let e = watch.lastError { return "Last check didn’t work: \(e)" }
        let checked = watch.lastChecked.map { "checked " + $0.formatted(.relative(presentation: .named)) } ?? "not checked yet"
        return "\(checked) · \(watch.downloadedCount) downloaded since you started"
    }
    var choiceLine: String {
        var parts = [watch.choices.kind.label]
        if watch.choices.kind != .audioOnly {
            if case .tier(let t) = watch.choices.resolution { parts.append("up to \(t.name)") } else { parts.append("best quality") }
            parts.append(watch.choices.container.name)
        }
        parts.append("into " + (model.project(watch.projectID)?.name ?? "your usual folder"))
        return parts.joined(separator: " · ")
    }
}

/// Start watching a channel or playlist.
struct WatchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var draft: CollectionDraft
    @State private var latest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge").font(.system(size: 22)).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch for New Videos").font(TypeStyle.title)
                    Text(draft.collection.title).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text("Every 3 hours while Digby is open (and when it opens), it looks for videos that weren’t there before and downloads them with the choices below. The \(draft.collection.entries.count) videos there now count as already seen.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Also download the newest now").font(.callout.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach([0, 1, 3, 5, 10], id: \.self) { n in
                        PillButton(n == 0 ? "None" : "\(n)", selected: latest == n, enabled: n <= draft.collection.entries.count) { latest = n }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("Save into").font(.callout.weight(.semibold))
                SaveToMenu(projectID: Binding(get: { draft.projectID }, set: { draft.projectID = $0 }), audio: draft.choices.kind == .audioOnly) {
                    model.newProjectRequest = NewProjectRequest(forCollection: draft)
                }
            }
            InfoRow("Uses: \(draft.choices.kind.label), \({ if case .tier(let t) = draft.choices.resolution { return "up to \(t.name)" }; return "best quality" }()), \(draft.choices.container.name). Change these on the playlist page before you start.",
                    systemImage: "slider.horizontal.3")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start Watching") { model.watch(draft, alsoLatest: latest); dismiss(); model.section = .watching }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// MARK: - Overnight

/// A moon you switch on to make this download wait for the overnight hours.
struct OvernightToggle: View {
    @Environment(AppModel.self) private var model
    @Binding var on: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { on.toggle() } } label: {
            Image(systemName: on ? "moon.stars.fill" : "moon").font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Brand.accent.opacity(0.18) : Color.secondary.opacity(0.09)))
                .foregroundStyle(on ? Brand.accent : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Waits for the overnight hours (\(model.overnightLabel)). Click to download now instead."
                 : "Download overnight (\(model.overnightLabel)): handy for big files or limited daytime internet. Set the hours in Settings → Downloads.")
        .accessibilityLabel(on ? "Download overnight, on" : "Download overnight, off")
    }
}
