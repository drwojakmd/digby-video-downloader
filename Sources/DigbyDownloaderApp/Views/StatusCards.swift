import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// Downloading: the streaks draw down toward the landing point as the file arrives.
struct DownloadingCard: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem

    var body: some View {
        Card(padding: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.skyGradient)
                LandfallView(progress: item.fraction ?? 0.1, drift: false, color: .white, pointColor: Brand.dawnFixed)
                    .padding(.horizontal, 40)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .animation(.linear(duration: 0.25), value: item.fraction)
            }
            .frame(height: 150)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(TypeStyle.headline).lineLimit(1)
                    Text(item.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.fraction.map { "\(Int($0 * 100))%" } ?? "")
                    .font(.system(size: 30, weight: .light)).monospacedDigit()
            }
            LandfallProgress(fraction: item.fraction)
            HStack {
                Text(statusLine).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Pause") { model.pause(item); model.reset(); model.section = .queue }.buttonStyle(QuietButtonStyle(tint: .secondary))
                    .help("Stops for now and keeps what has downloaded; resume it from Downloads")
                Button("Cancel") { model.cancel(item); model.reset() }.buttonStyle(QuietButtonStyle(tint: .secondary))
            }
            InfoRow("You can start another download while this one finishes. Everything is listed under Downloads.", systemImage: "arrow.down.circle")
            Button("Download Something Else") { model.reset() }.buttonStyle(QuietButtonStyle())
        }
    }

    var statusLine: String {
        switch item.state {
        case .downloading(let f, let speed, let rem):
            var parts: [String] = []
            if let s = item.size, let f { parts.append("\(Fmt.bytes(Int64(Double(s.bytes) * f))) of \(Fmt.size(s))") }
            if speed > 0 { parts.append(Fmt.speed(speed)) }
            if let rem { parts.append(Fmt.remaining(rem)) }
            return parts.joined(separator: "  ·  ")
        case .verifying: return "Checking the finished file plays, with the right length, picture and sound…"
        case .processing(let s): return s + "…"
        case .analysing: return item.phase.isEmpty ? "Starting…" : item.phase + "…"
        default: return ""
        }
    }
}

/// Done: only shown after the file was checked.
struct CompletedCard: View {
    @Environment(AppModel.self) private var model
    var item: QueueItem

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.skyGradient)
                    LandfallView(progress: 1, settled: true, color: .white, pointColor: Brand.dawnFixed, count: 5)
                        .padding(.horizontal, 10).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloaded").font(TypeStyle.title)
                    Text(item.title).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.good)
                        Text("Checked: it plays, with the expected length, picture and sound.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(item.summary.components(separatedBy: " · "), id: \.self) { Chip($0, tint: Brand.accent) }
                if let s = item.size { Chip(Fmt.bytes(s.bytes), systemImage: "internaldrive") }
            }
            ForEach(item.notes, id: \.self) { InfoRow($0, systemImage: "info.circle.fill", tint: Brand.warn) }
            if case .done(let url) = item.state {
                HStack(spacing: 10) {
                    Button("Show in Finder") { model.reveal(url) }.buttonStyle(ProminentButtonStyle())
                    Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(QuietButtonStyle())
                    if let d = item.details { Button("Details") { model.detailsShown = d }.buttonStyle(QuietButtonStyle(tint: .secondary))
                        .help("The original video, what you chose, and what Digby checked") }
                    Spacer()
                    Button("Download Another") { model.reset() }.buttonStyle(QuietButtonStyle(tint: .secondary))
                }
                CompressWithDigby(file: url)
            }
        }
    }
}

/// The hand-off to the sibling app, with what it means in plain English.
struct CompressWithDigby: View {
    @Environment(AppModel.self) private var model
    var file: URL
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "rectangle.compress.vertical").font(.system(size: 20)).foregroundStyle(Brand.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Make it smaller").font(.callout.weight(.semibold))
                Text(model.compressorInstalled
                     ? "Opens this video in Digby Video Compressor, which can shrink it a lot with no visible loss. This download stays as it is."
                     : "Digby Video Compressor can shrink videos a lot with no visible loss. Install it to use this.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Compress with Digby") { model.compressWithDigby(file) }
                .buttonStyle(QuietButtonStyle()).disabled(!model.compressorInstalled)
        }
        .padding(12)
        .background(Brand.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A failure, explained: what happened, what Digby did about it, and what you can do.
struct DiagnosisCard: View {
    @Environment(AppModel.self) private var model
    var url: URL
    var diagnosis: Diagnosis

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: diagnosis.inProgress ? "stethoscope" : symbol)
                    .font(.system(size: 22)).foregroundStyle(diagnosis.inProgress ? Brand.accent : Brand.warn).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(diagnosis.title).font(TypeStyle.title)
                    Text(diagnosis.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(diagnosis.inProgress ? "Digby is working on it" : "What Digby checked")
                ForEach(Array(diagnosis.whatDigbyDid.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 9) {
                        Group {
                            if step.1 { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.good) }
                            else if diagnosis.inProgress && i == diagnosis.whatDigbyDid.firstIndex(where: { !$0.1 }) { ProgressView().controlSize(.small) }
                            else { Image(systemName: "circle").foregroundStyle(.tertiary) }
                        }
                        .frame(width: 18)
                        Text(step.0).font(.callout)
                    }
                }
            }
            .padding(.leading, 44)
            let routes = (offersOutOfSight ? [Self.outOfSight] : []) + diagnosis.actions.filter { Self.routeActions.contains($0) }
            let others = diagnosis.actions.filter { !Self.routeActions.contains($0) }
            if !routes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(routes.count == 1 ? "What you can do" : routes.count == 2 ? "Two ways to get it" : "Ways to get it")
                    ForEach(routes, id: \.self) { a in
                        RouteOption(title: a, explanation: explanation(a), prominent: a == routes.first,
                                    enabled: available(a), buttonTitle: a == Self.outOfSight ? "Allow for \(siteName)" : nil) { perform(a) }
                    }
                    if offersOutOfSight {
                        Button("Don’t Offer This for \(siteName)") { model.setPageCatch(url, allowed: false) }
                            .buttonStyle(.link).font(.caption)
                            .help("Digby won’t offer to play \(siteName) pages out of sight. Change this in Settings → Privacy.")
                    }
                }
                .padding(.leading, 44)
            }
            if !others.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(others.enumerated()), id: \.offset) { i, a in
                        if i == 0 && routes.isEmpty { Button(a) { perform(a) }.buttonStyle(ProminentButtonStyle()).disabled(!available(a)).help(help(a)) }
                        else { Button(a) { perform(a) }.buttonStyle(QuietButtonStyle()).disabled(!available(a)).help(help(a)) }
                    }
                    Spacer()
                }
                .padding(.leading, 44)
            }
            Text(url.absoluteString).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).padding(.leading, 44)
        }
    }

    func perform(_ action: String) {
        switch action {
        case "Try Again", "Retry Now": model.urlText = url.absoluteString; model.analyse()
        case "Copy Report": model.copyReport(diagnosis, link: url)
        case "Open in Browser": NSWorkspace.shared.open(url)
        case "Use My Browser’s Sign-in": model.requestSignIn(for: url)
        case "Find the Video on the Page": model.findOnPage(url)
        case Self.outOfSight: model.allowPageCatch(andRetry: url)
        case Diagnosis.tryNightly: model.tryNightly(url)
        default: break
        }
    }

    /// Asked once per site: offered when the engine couldn't read a page that a player might still show,
    /// and you haven't answered for this site yet.
    var offersOutOfSight: Bool {
        guard !diagnosis.inProgress, let f = diagnosis.failure, AppModel.pageCatchable.contains(f.kind), !f.noPageRoutes, SiteKey.of(url) != nil else { return false }
        return model.pageCatchAnswer(url) == nil
    }
    var siteName: String { SiteKey.of(url) ?? "this site" }
    static let outOfSight = "Play the Page Out of Sight"
    func available(_ action: String) -> Bool { action != "Use My Browser’s Sign-in" || SignInSite.site(for: url) != nil }
    func help(_ action: String) -> String {
        switch action {
        case "Use My Browser’s Sign-in": "Download as you, signed in to \(SignInSite.site(for: url)?.displayName ?? "this site"). Your sign-in stays on this Mac."
        case "Copy Report": "Copies a diagnostic report with links, cookies and your user name removed."
        case "Find the Video on the Page": "Opens the page in Digby’s browser. Play the video and Digby catches it."
        default: ""
        }
    }

    static let routeActions = [Diagnosis.tryNightly, "Use My Browser’s Sign-in", "Find the Video on the Page"]

    func explanation(_ action: String) -> Explanation {
        let site = SignInSite.site(for: url)?.displayName ?? (url.host ?? "this site")
        if action == Self.outOfSight {
            return Explanation(
                "Digby opens the page in a hidden window, plays it with the sound off and catches the video, as if you’d pressed play yourself. You’re asked once for \(siteName); after that its links just work.",
                pros: ["Automatic from now on: no window to open, nothing to click",
                       "Works on many sites the engine can’t read, because the site’s own player finds the video",
                       "You can change your answer in Settings → Privacy"],
                cons: ["The site’s page really runs in Digby’s browser, scripts and trackers included, like visiting it yourself; anything it saves stays there until you choose Forget All",
                       "Can’t sign in or pass an “Are you human?” check for you",
                       "Sometimes only the quality the player chose is available"])
        }
        if action == Diagnosis.tryNightly {
            return Explanation(
                "The newest tested (Stable) engine can’t read this page yet. Fixes for changed sites usually reach the Nightly build within a day. Digby checks it’s genuine and test-runs it, as with every engine, then reads the page again.",
                pros: ["Often fixes a site the day after it changes",
                       "Verified the same way as Stable: signed checksums and a test-run",
                       "Digby moves back to Stable by itself once Stable catches up; Roll Back in Settings works too"],
                cons: ["Less tested than Stable, so very occasionally it has a new bug",
                       "Waits until running downloads finish before switching"])
        }
        if action == "Use My Browser’s Sign-in" {
            return Explanation(
                "Digby tries again as you, using the sign-in already in your web browser for \(site). Nothing to click on the page; Digby still picks the best quality for you.",
                pros: ["Fully automatic, with all the usual quality and format choices",
                       "Works for things only signed-in viewers can see",
                       "Your sign-in stays on this Mac; Digby reads it fresh each time and never sends it anywhere else"],
                cons: ["You must already be signed in to \(site) in your browser",
                       "Doesn’t help when the site wants an “Are you human?” check or blocks your network",
                       "macOS may ask you to allow access to your browser’s saved sign-ins"])
        }
        return Explanation(
            "Digby opens the page in its own small browser. You do what you’d normally do — sign in, pass any check, press play — then click Download.",
            pros: ["Works almost anywhere you can watch the video yourself",
                   "Gets past “Are you human?” checks, because you pass them",
                   "Sign-ins made there are remembered by Digby for next time"],
            cons: ["Needs a few clicks from you",
                   "Sometimes only the quality the player chose is available",
                   "Copy-protected (DRM) videos still can’t be saved"])
    }

    var symbol: String {
        switch diagnosis.kind {
        case .privateMedia, .loginRequired: "lock"
        case .rateLimited: "hourglass"
        case .network: "wifi.exclamationmark"
        case .diskFull: "internaldrive"
        default: "exclamationmark.triangle"
        }
    }
}

/// A playlist or channel: choose which videos, then the shared format choices.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    @Bindable var draft: CollectionDraft

    var body: some View {
        let c = draft.collection
        VStack(alignment: .leading, spacing: 18) {
            Card {
                HStack(alignment: .top, spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        Thumbnail(url: c.entries.last?.thumbnail, seed: c.entries.last?.id ?? "x").frame(width: 172, height: 97).offset(x: 10, y: -8).opacity(0.5)
                        Thumbnail(url: c.entries.first?.thumbnail, seed: c.entries.first?.id ?? "y").frame(width: 172, height: 97)
                    }
                    .frame(width: 192, height: 108, alignment: .bottomLeading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Playlist").font(TypeStyle.sectionLabel).textCase(.uppercase).foregroundStyle(.secondary)
                        Text(c.title).font(TypeStyle.title)
                        Text([c.uploader, c.site, "\(c.entries.count) videos", c.totalDuration.map { Fmt.duration($0) + " in total" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Card(padding: 0) {
                HStack {
                    SectionLabel("\(draft.included.count) of \(c.entries.count) selected")
                    Spacer()
                    Button("Select All") { draft.included = Set(c.entries.map(\.id)) }.buttonStyle(.plain).foregroundStyle(Brand.accent)
                    Button("Select None") { draft.included = [] }.buttonStyle(.plain).foregroundStyle(Brand.accent)
                }
                .font(.callout).padding(.horizontal, 18).padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(Array(c.entries.enumerated()), id: \.element.id) { i, e in
                        Toggle(isOn: Binding(get: { draft.included.contains(e.id) },
                                             set: { if $0 { draft.included.insert(e.id) } else { draft.included.remove(e.id) } })) {
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(.caption).monospacedDigit().foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                                Thumbnail(url: e.thumbnail, seed: e.id).frame(width: 64, height: 36)
                                Text(e.title).lineLimit(1)
                                Spacer()
                                if let d = e.duration { Text(Fmt.duration(d)).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        if i < c.entries.count - 1 { Divider().padding(.leading, 18) }
                    }
                }
                .padding(.bottom, 10)
            }
            Card(padding: 20) {
                KindPicker(kind: $draft.choices.kind, hasVideo: true)
                if draft.choices.kind != .audioOnly {
                    ChoiceRow(title: "Highest resolution", symbol: "rectangle.on.rectangle",
                              explanation: Explanation("Each video downloads at this resolution, or its highest if lower. Digby tells you which videos come out lower.")) {
                        ForEach([ResolutionChoice.best, .tier(.p2160), .tier(.p1080), .tier(.p720), .tier(.p480)], id: \.self) { r in
                            PillButton(r == .best ? "Best" : { if case .tier(let t) = r { return t.name }; return "" }(),
                                       selected: draft.choices.resolution == r) { draft.choices.resolution = r }
                        }
                    }
                    ChoiceRow(title: "File type", symbol: "doc", explanation: Explain.container(draft.choices.container)) {
                        ForEach(Container.allCases, id: \.self) { k in
                            PillButton(k.name, detail: k.plainLabel, selected: draft.choices.container == k) { draft.choices.container = k }
                        }
                    }
                }
                HStack(spacing: 10) {
                    SaveToMenu(projectID: $draft.projectID, audio: draft.choices.kind == .audioOnly) {
                        model.newProjectRequest = NewProjectRequest(forCollection: draft)
                    }
                    .font(.callout)
                    .help("Each playlist gets a folder named after it, inside your usual folder or the project you choose")
                    Spacer(minLength: 8)
                    Button { model.watchRequest = draft } label: { Label("Watch for New Videos…", systemImage: "bell") }
                        .buttonStyle(QuietButtonStyle())
                        .help("Digby checks this \(draft.collection.entries.count > 0 ? "list" : "page") every few hours and downloads new videos by themselves")
                    OvernightToggle(on: $draft.overnight)
                    Button("Download \(draft.included.count) Videos") { model.startCollection(draft) }.buttonStyle(ProminentButtonStyle()).disabled(draft.included.isEmpty)
                }
            }
        }
    }
}

/// One way past a failure, with what it means and its pros and cons.
struct RouteOption: View {
    var title: String
    var explanation: Explanation
    var prominent: Bool
    var enabled: Bool
    var buttonTitle: String? = nil
    var action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                ExplanationLine(explanation: explanation)
            }
            Spacer(minLength: 8)
            let label = enabled ? (buttonTitle ?? "Try This") : "Not Available"
            Group {
                if prominent { Button(label, action: action).buttonStyle(ProminentButtonStyle()) }
                else { Button(label, action: action).buttonStyle(QuietButtonStyle()) }
            }
            .disabled(!enabled)
            .accessibilityLabel(title)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(enabled ? 1 : 0.55)
    }
}
