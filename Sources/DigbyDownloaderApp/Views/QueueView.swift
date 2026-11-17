import SwiftUI
import DigbyDesign
import DigbyDownloadCore

struct QueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.waitingForOvernight.isEmpty { OvernightBanner() }
            Divider()
            if model.queue.isEmpty {
                ContentUnavailableView("Nothing downloading", systemImage: "arrow.down.circle",
                                       description: Text("When you press Download, the video waits and downloads here. Finished videos are in Downloaded."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.queue) { item in
                            if item.isPlaylist { PlaylistGroup(item: item) } else { QueueRow(item: item) }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: Metrics.contentMaxWidth + 80)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    var header: some View {
        let all = model.queue.flatMap { $0.isPlaylist ? $0.children : [$0] }
        let done = all.filter { if case .done = $0.state { true } else { false } }.count
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading").font(TypeStyle.title)
                Text("\(model.activeCount) downloading · \(all.count - done - model.activeCount) waiting or stopped · finished ones move to Downloaded")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button("Pause All") { model.queue.forEach(model.pause) }.buttonStyle(QuietButtonStyle(tint: .secondary)).disabled(model.activeCount == 0)
            Button("Clear Cancelled") { model.queue.removeAll { if case .cancelled = $0.state { return true }; return false } }
                .buttonStyle(QuietButtonStyle(tint: .secondary))
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
}

struct QueueRow: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem
    var compact = false

    var expanded: Bool { model.expandedQueueIDs.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
            if expanded {
                LiveDetailsPanel(item: item)
                    .padding(.top, compact ? 6 : 12).padding(.leading, compact ? 68 : 92)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(compact ? 8 : 12)
        .background(compact ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(compact ? nil : RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(expanded ? Brand.accent.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: expanded ? 1 : 0.5))
    }

    func toggle() {
        withAnimation(.easeOut(duration: 0.18)) {
            if expanded { model.expandedQueueIDs.remove(item.id) } else { model.expandedQueueIDs.insert(item.id) }
        }
    }

    var summaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Thumbnail(url: item.thumbnail, seed: item.title, file: doneFile).frame(width: compact ? 56 : 80, height: compact ? 32 : 45)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title).font(compact ? .callout : TypeStyle.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    stateBadge
                }
                if !compact {
                    HStack(spacing: 4) {
                        SourceLink(site: item.site, url: model.workURL(item))
                        Text("· \(item.summary)").foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.caption)
                }
                if showsProgress { LandfallProgress(fraction: item.fraction, done: isDone) }
                if !detail.isEmpty {
                    Text(detail).font(.caption).monospacedDigit().foregroundStyle(isFailed ? Brand.warn : .secondary).lineLimit(1)
                }
            }
            actions.fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Hides the details" : "Shows the details: what the site offered, what you chose, where it goes")
    }

    var doneFile: URL? { if case .done(let u) = item.state { u } else { nil } }

    var isDone: Bool { if case .done = item.state { true } else { false } }
    var isFailed: Bool { if case .failed = item.state { true } else { false } }
    var showsProgress: Bool {
        switch item.state { case .downloading, .paused, .processing, .verifying: true; default: false }
    }

    @ViewBuilder var stateBadge: some View {
        switch item.state {
        case .waiting where item.overnight: Chip("Overnight", systemImage: "moon.stars.fill", tint: Brand.accent)
        case .waiting: Chip("Waiting", systemImage: "clock")
        case .paused: Chip("Paused", systemImage: "pause.fill")
        case .done: Chip("Done", systemImage: "checkmark", tint: Brand.good)
        case .failed: Chip("Didn’t work", systemImage: "exclamationmark.triangle", tint: Brand.warn)
        case .cancelled: Chip("Cancelled")
        case .verifying: Chip("Checking", systemImage: "checkmark.shield")
        default: EmptyView()
        }
    }

    var detail: String {
        switch item.state {
        case .waiting where item.overnight:
            return "Starts at \(AppModel.clock(model.overnightStart))" + (item.size.map { " · " + Fmt.size($0) } ?? "")
        case .waiting: return item.size.map { Fmt.size($0) } ?? ""   // the badge already says "Waiting"
        case .analysing: return item.phase.isEmpty ? "Starting…" : item.phase + "…"
        case .downloading(let f, let speed, let rem):
            var p: [String] = []
            if let f, let s = item.size { p.append("\(Int(f * 100))% · \(Fmt.bytes(Int64(Double(s.bytes) * f))) of \(Fmt.size(s))") }
            else { p.append("Size unknown") }
            if speed > 0 { p.append(Fmt.speed(speed)) }
            if let rem { p.append(Fmt.remaining(rem)) }
            return p.joined(separator: " · ")
        case .processing(let s): return s + "…"
        case .verifying: return "Checking the file plays correctly"
        case .paused(let f): return "\(Int(f * 100))% downloaded"
        case .done: return item.size.map { "Saved · \(Fmt.bytes($0.bytes))" } ?? "Saved"
        case .failed(let why): return why
        case .cancelled: return "Cancelled — nothing was kept"
        }
    }

    @ViewBuilder var actions: some View {
        HStack(spacing: 4) {
            iconButton(expanded ? "chevron.up" : "info", expanded ? "Hide details" : "Details: what the site offered, what you chose, where it goes") { toggle() }
            switch item.state {
            case .done(let url):
                iconButton("magnifyingglass", "Show in Finder") { model.reveal(url) }
            case .failed:
                iconButton("arrow.clockwise", "Try again") { model.retry(item) }
                iconButton("xmark", "Remove from the list") { model.remove(item) }
            case .paused:
                iconButton("play.fill", "Resume — continues where it stopped") { model.resume(item) }
                iconButton("xmark", "Remove from the list") { model.remove(item) }
            case .waiting:
                if item.overnight { iconButton("play.fill", "Start now instead of waiting for the night") { model.startNow(item) } }
                iconButton("pause", "Pause") { model.pause(item) }
                iconButton("xmark", "Remove from the list") { model.remove(item) }
            case .cancelled:
                iconButton("arrow.clockwise", "Try again") { model.retry(item) }
            default:
                iconButton("pause", "Pause — keeps what has downloaded") { model.pause(item) }
                iconButton("xmark", "Cancel this download") { model.cancel(item) }
            }
        }
    }

    func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        RoundIconButton(symbol, help: help, action: action)
    }
}

struct PlaylistGroup: View {
    var item: QueueItem
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Thumbnail(url: item.children.dropFirst().first?.thumbnail, seed: item.title + "2").frame(width: 70, height: 40).offset(x: 6, y: -5).opacity(0.5)
                        Thumbnail(url: item.thumbnail, seed: item.title).frame(width: 70, height: 40)
                    }
                    .frame(width: 80, height: 45, alignment: .bottomLeading)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                            Text(item.title).font(TypeStyle.headline)
                            Spacer()
                            if item.failedCount > 0 { Chip("\(item.failedCount) didn’t work", tint: Brand.warn) }
                        }
                        Text("\(item.site) · \(item.doneCount) of \(item.children.count) done · \(item.summary)").font(.caption).foregroundStyle(.secondary)
                        LandfallProgress(fraction: item.groupFraction)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
            if expanded {
                VStack(spacing: 0) {
                    ForEach(item.children) { c in
                        QueueRow(item: c, compact: true).padding(.leading, 92)
                    }
                }
                .padding(.bottom, 8).padding(.trailing, 4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

/// A download's details while it's still going: what the site offered, what you chose, and where it will be
/// saved, the same facts Downloaded shows afterwards.
struct LiveDetailsPanel: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = item.details {
                if !d.choices.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        ForEach(d.choices) { c in
                            GridRow {
                                Text(c.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(c.value).textSelection(.enabled)
                            }
                        }
                    }
                    .font(.callout)
                }
                FlowLayout(spacing: 6) {
                    ForEach(d.chips, id: \.self) { Chip($0, tint: Brand.accent) }
                    if let b = d.expectedBytes { Chip((d.expectedExact ? "" : "≈ ") + Fmt.bytes(b), systemImage: "internaldrive") }
                }
                InfoRow(offered(d), systemImage: "square.stack.3d.up")
                ForEach(d.notes, id: \.self) { InfoRow($0, systemImage: "info.circle", tint: .secondary) }
            } else {
                InfoRow("Digby reads this video when its turn comes; its details appear here then.", systemImage: "clock")
            }
            if let dest = destination {
                InfoRow("Saves to " + dest, systemImage: "folder")
            }
            HStack(spacing: 8) {
                if let d = item.details {
                    Button("All Details…") { model.detailsShown = d }.buttonStyle(QuietButtonStyle(tint: .secondary))
                        .help("Everything the site offered, your choices, and (once finished) what Digby checked")
                }
                if let u = model.workURL(item) {
                    Button("Open Original Page") { NSWorkspace.shared.open(u) }.buttonStyle(QuietButtonStyle(tint: .secondary))
                    Button("Copy Link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u.absoluteString, forType: .string) }
                        .buttonStyle(QuietButtonStyle(tint: .secondary))
                }
                Spacer(minLength: 0)
            }
        }
    }

    func offered(_ d: DownloadDetails) -> String {
        guard !d.offered.isEmpty else { return "The site offered sound only." }
        var parts = [d.offered.map(\.resolution).joined(separator: ", ")]
        if let fps = d.offered.compactMap(\.frameRate).max(), fps > 31 { parts.append("up to \(Fmt.fps(fps))") }
        if d.offered.contains(where: \.hdr) { parts.append("HDR") }
        if d.soundLanguages.count > 1 { parts.append("\(d.soundLanguages.count) sound languages") }
        if !d.subtitles.isEmpty { parts.append("subtitles") }
        return "The site offered " + parts.joined(separator: " · ")
    }

    var destination: String? {
        if case .done(let u) = item.state { return u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        guard case .planned(let r)? = item.work else { return nil }
        return r.folder.appendingPathComponent(r.fileName).path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + "." + r.plan.outputExtension
    }
}

/// Downloads waiting for the night: when they start, and that the Mac stays awake for them.
struct OvernightBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let n = model.waitingForOvernight.count
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill").foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(n) download\(n == 1 ? " waits" : "s wait") for the overnight hours (\(model.overnightLabel)).").font(.callout.weight(.medium))
                Text("Digby keeps your Mac awake until then (the screen can still sleep). Leave it plugged in with the lid open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Start All Now") { model.startAllNow() }.buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Brand.accent.opacity(0.07))
    }
}
