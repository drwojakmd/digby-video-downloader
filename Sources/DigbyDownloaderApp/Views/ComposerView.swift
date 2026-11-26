import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// The New Download page: paste → analyse → choose → download.
struct ComposerView: View {
    @Environment(AppModel.self) private var model
    var dropTargeted: Bool

    var body: some View {
        if model.drafts.isEmpty {
            EmptyComposer(dropTargeted: dropTargeted)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let item = model.justStarted { StartedStrip(item: item) }
                    if model.linksAsList {
                        HStack {
                            Text("\(model.drafts.count) link\(model.drafts.count == 1 ? "" : "s") open · listed in the sidebar")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            LinksLayoutSwitch()
                        }
                    } else {
                        DraftTray()
                    }
                    if model.selectedDraft == nil {
                        NewLinkHint(empty: model.drafts.isEmpty)
                    } else {
                        ComposerContent().id(model.selectedDraftID)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                .frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
    }

}

/// Everything below the link field, for the current state.
struct ComposerContent: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.composer {
        case .empty: EmptyView()
        case .analysing(let url, let step): AnalysingView(url: url, step: step)
        case .ready(let a): ReadyView(analysis: a)
        case .collection(let d): CollectionView(draft: d)
        case .downloading(let item): DownloadingCard(item: item)
        case .completed(let item): CompletedCard(item: item)
        case .failed(let url, let d): DiagnosisCard(url: url, diagnosis: d)
        }
    }
}

/// The hero: one field, one action.
struct EmptyComposer: View {
    @Environment(AppModel.self) private var model
    var dropTargeted: Bool

    var body: some View {
        // Minimal by design: the app icon, one headline, the link field. (`SkyPanel` and `LandfallView` in
        // DigbyDesign/Landfall.swift are kept, unused, and can be put back here.)
        VStack(spacing: 22) {
            AppIconMark(size: 76)
                .scaleEffect(dropTargeted ? 1.05 : 1)
                .animation(.easeInOut(duration: 0.3), value: dropTargeted)
            VStack(spacing: 8) {
                Text(dropTargeted ? "Drop to download" : "Paste a link to begin")
                    .font(TypeStyle.display).kerning(-0.3)
                Text("Videos, music, playlists and channels from thousands of sites.\nDigby shows you exactly what you’ll get, in plain English, before anything downloads.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            URLBar(compact: false).frame(maxWidth: 580)
            ProjectChip()
            if let s = model.clipboardSuggestion, model.watchClipboard {
                Button { model.urlText = s.absoluteString; model.analyse() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copied link: ") + Text(s.host ?? "").bold() + Text(s.path.prefix(24))
                        Text("Use it").foregroundStyle(Brand.accent).fontWeight(.semibold)
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .help("Digby noticed a link on your clipboard. It never downloads anything until you ask.")
            }
            Text("Explains every choice · Never lowers quality silently · Keeps itself up to date · Works with Digby Compressor")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The app's own icon, as a quiet brand mark (home screen and About).
struct AppIconMark: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The link field. Several links pasted at once become a batch.
struct URLBar: View {
    @Environment(AppModel.self) private var model
    var compact: Bool
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        let links = AppModel.links(in: model.urlText)
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(focused || !model.urlText.isEmpty ? Brand.accent : .secondary)
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    .background(Circle().fill(Brand.accent.opacity(focused ? 0.16 : 0.09)))
                TextField(compact ? "Paste a link to download" : "Paste a link from YouTube, Vimeo, SoundCloud…", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .font(compact ? TypeStyle.body : TypeStyle.field)
                    .focused($focused)
                    .onSubmit { model.analyse() }
                    .accessibilityLabel("Link to download")
                if links.count > 1 {
                    Chip("\(links.count) links", systemImage: "square.stack", tint: Brand.accent)
                }
                if model.urlText.isEmpty {
                    if compact && !focused {
                        Text("⌘L").font(.caption.monospaced()).foregroundStyle(.tertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
                            .help("Press ⌘L from anywhere in Digby to type or paste a link here")
                    }
                    Button("Paste") { model.pasteFromClipboard() }
                        .buttonStyle(QuietButtonStyle())
                        .help("Paste the link on your clipboard (⇧⌘V)")
                } else if compact {
                    Button { model.urlText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Clear and start again").accessibilityLabel("Clear")
                }
            }
            .padding(.leading, compact ? 7 : 10).padding(.trailing, compact ? 7 : 14).padding(.vertical, compact ? 6 : 10)
            .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
                .strokeBorder(focused ? Brand.accent.opacity(0.7) : Color(nsColor: .separatorColor).opacity(compact ? 0.9 : 1), lineWidth: focused ? 1.5 : 0.5))
            .shadow(color: .black.opacity(compact ? 0.06 : 0.05), radius: compact ? 3 : 8, y: compact ? 1 : 3)
            .shadow(color: Brand.accent.opacity(focused ? 0.18 : 0), radius: 6)
            .animation(.easeOut(duration: 0.15), value: focused)
            .onChange(of: model.focusLinkRequest) { _, _ in focused = true }
            .onAppear { if model.focusLinkRequest > 0 { focused = true } }

            if !compact || !(model.urlText.isEmpty) {
                Button(links.count > 1 ? "Add \(links.count)" : "Analyse") { model.analyse() }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(links.isEmpty)
            }
        }
    }
}

/// While the page is read: the sky drifts and each step is named.
struct AnalysingView: View {
    @Environment(AppModel.self) private var model
    var url: URL
    var step: Int
    var steps: [String] {
        ["Opening the page", "Listing every format the site offers", "Checking sound tracks and subtitles"]
            + (step >= 3 ? ["Playing the page to find the video (the site isn’t readable directly)"] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading \(url.host?.replacingOccurrences(of: "www.", with: "") ?? "the page")…")
                    .font(.system(size: 22, weight: .light)).lineLimit(1).truncationMode(.middle)
                Text("Nothing is downloaded yet").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            Card {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 10) {
                        Group {
                            if i < step { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.good) }
                            else if i == step { ProgressView().controlSize(.small) }
                            else { Image(systemName: "circle").foregroundStyle(.tertiary) }
                        }
                        .frame(width: 18)
                        Text(s).foregroundStyle(i <= step ? .primary : .secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "scope").foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Know this site is tricky, or tired of waiting?").font(.callout.weight(.semibold))
                    Text("Open the page in Digby’s browser and download what you see. Digby keeps reading in the background meanwhile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Find It on the Page") { model.findOnPage(url) }.buttonStyle(QuietButtonStyle())
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            PreviewSkeleton()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysing \(url.host ?? "link"), step \(step + 1) of 3")
    }
}

struct PreviewSkeleton: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: Metrics.thumbnailRadius).fill(Color.secondary.opacity(0.1)).frame(width: 192, height: 108)
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 300, height: 14)
                    Capsule().fill(Color.secondary.opacity(0.08)).frame(width: 180, height: 10)
                    Capsule().fill(Color.secondary.opacity(0.08)).frame(width: 220, height: 10)
                }
                .padding(.top, 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Every link you've pasted, as tabs. Each keeps going on its own; click to switch, × to close.
struct DraftTray: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.drafts) { d in DraftChip(draft: d, selected: d.id == model.selectedDraftID) }
                }
                .padding(.vertical, 2)
            }
                Button { model.select(nil) } label: {
                    Label("New Link", systemImage: "plus").font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedDraft == nil ? Brand.accent : .secondary)
                .help("Paste another link; the others keep going")
                .fixedSize()
                LinksLayoutSwitch()
        }
        .accessibilityLabel("Open links")
    }
}

struct DraftChip: View {
    @Environment(AppModel.self) private var model
    var draft: Draft
    var selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            status.frame(width: 16, height: 16)
            Text(draft.label).lineLimit(1).frame(maxWidth: 170, alignment: .leading)
            if hover || selected {
                Button { withAnimation(.easeOut(duration: 0.15)) { model.close(draft) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain).help(closeHelp).accessibilityLabel("Close \(draft.label)")
            }
        }
        .font(.callout.weight(selected ? .semibold : .regular))
        .padding(.leading, 10).padding(.trailing, hover || selected ? 6 : 12).padding(.vertical, 7)
        .background(Capsule().fill(selected ? Brand.accent.opacity(0.14) : Color.secondary.opacity(hover ? 0.12 : 0.07)))
        .overlay(Capsule().strokeBorder(selected ? Brand.accent.opacity(0.6) : .clear, lineWidth: 1))
        .foregroundStyle(selected ? Brand.accent : Color.primary)
        .contentShape(Capsule())
        .onTapGesture { model.select(draft) }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(draft.label), \(statusText)")
    }

    var closeHelp: String {
        if case .downloading = draft.state { return "Close (the download carries on under Downloads)" }
        return "Close"
    }
    var statusText: String {
        switch draft.state {
        case .analysing: "reading the page"
        case .ready, .collection: "ready to choose"
        case .downloading: "downloading"
        case .completed: "downloaded"
        case .failed: "didn’t work"
        case .empty: ""
        }
    }
    var status: some View { StatusMark(state: draft.state) }

    struct StatusMark: View {
        var state: ComposerState
        var body: some View { mark }
        @ViewBuilder var mark: some View {
        switch state {
        case .analysing: ProgressView().controlSize(.mini)
        case .ready, .collection: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(Brand.accent)
        case .downloading(let item):
            ZStack {
                Circle().stroke(Brand.accent.opacity(0.2), lineWidth: 2)
                Circle().trim(from: 0, to: item.fraction ?? 0.05).stroke(Brand.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .padding(1)
        case .completed: Circle().fill(Brand.dawn).frame(width: 8, height: 8)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.warn)
        case .empty: EmptyView()
        }
        }
    }
}

struct NewLinkHint: View {
    var empty = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up").foregroundStyle(Brand.accent)
            Text(empty ? "Paste a link in the bar above." : "Paste another link above. Links you’ve already added keep going in the background.").foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
}

/// Tabs above the page, or a list in the sidebar.
struct LinksLayoutSwitch: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 2) {
            option(list: false, symbol: "rectangle.split.3x1", help: "Show open links as tabs")
            option(list: true, symbol: "sidebar.left", help: "Show open links as a list in the sidebar")
        }
        .padding(2)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
        .fixedSize()
    }
    func option(list: Bool, symbol: String, help: String) -> some View {
        let on = model.linksAsList == list
        return Button { withAnimation(.easeOut(duration: 0.15)) { model.linksAsList = list } } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 20)
                .background(Capsule().fill(on ? Brand.accent.opacity(0.18) : .clear))
                .foregroundStyle(on ? Brand.accent : .secondary)
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help).accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One open link as a sidebar row (list layout).
struct DraftRow: View {
    @Environment(AppModel.self) private var model
    var draft: Draft
    @State private var hover = false
    var selected: Bool { model.section == .download && model.selectedDraftID == draft.id }
    var body: some View {
        HStack(spacing: 8) {
            DraftChip.StatusMark(state: draft.state).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.label).font(.callout).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hover {
                Button { model.close(draft) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Close").accessibilityLabel("Close \(draft.label)")
            }
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Brand.accent.opacity(0.16) : hover ? Color.secondary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.select(draft) }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    var subtitle: String {
        switch draft.state {
        case .analysing(_, let step): step >= 3 ? "Playing the page…" : "Reading the page…"
        case .ready, .collection: "Ready to choose"
        case .downloading(let i): i.fraction.map { "Downloading \(Int($0 * 100))%" } ?? "Downloading…"
        case .completed: "Downloaded"
        case .failed(_, let d): d.title
        case .empty: ""
        }
    }
}

/// After pressing Download: where the video went.
struct StartedStrip: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Brand.accent)
            Text("“\(item.title)” is downloading.").lineLimit(1)
            Spacer()
            Button("Show in Downloading") { model.section = .queue; model.justStarted = nil }.buttonStyle(QuietButtonStyle())
        }
        .font(.callout)
        .padding(12)
        .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.opacity)
    }
}
