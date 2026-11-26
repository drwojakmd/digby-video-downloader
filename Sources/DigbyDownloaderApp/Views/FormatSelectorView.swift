import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// Ready to download: the preview, the categorised choices, and exactly what you'll get.
struct ReadyView: View {
    @Environment(AppModel.self) private var model
    @Bindable var analysis: Analysis

    var body: some View {
        let result = analysis.result(model.playback)
        VStack(alignment: .leading, spacing: 18) {
            MediaPreviewCard(media: analysis.catalogue.media, catalogue: analysis.catalogue)
            Card(padding: 20) {
                FormatSelectorView(analysis: analysis, result: result)
                Divider().padding(.vertical, 2)
                if let note = analysis.autoNote {
                    InfoRow(note, systemImage: "wand.and.stars", tint: Brand.accent)
                }
                PlanSummary(result: result, catalogue: analysis.catalogue) { analysis.choices = $0; analysis.autoNote = nil }
                if analysis.choices.kind != .audioOnly {
                    Divider().padding(.vertical, 2)
                    CompressAfterRow(downloadBytes: result.plan?.size?.bytes,
                                     codec: result.plan.flatMap { $0.videoConverted ? .avc : $0.video?.videoCodec })
                }
                DownloadBar(analysis: analysis, result: result)
            }
            if analysis.advanced {
                AdvancedFormatTable(analysis: analysis, plan: result.plan)
            }
        }
    }
}

struct FormatSelectorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var analysis: Analysis
    var result: SelectionResult

    var cat: FormatCatalogue { analysis.catalogue }
    var plan: DownloadPlan? { result.plan }
    /// The resolution actually in play (the chosen one, or what "Best" resolved to).
    var tier: ResolutionTier? {
        if case .tier(let t) = analysis.choices.resolution { return t }
        return plan?.video?.tier ?? cat.tiers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            KindPicker(kind: Binding(get: { analysis.choices.kind }, set: { set(\.kind, $0) }), hasVideo: !cat.tiers.isEmpty)

            if analysis.choices.kind != .audioOnly {
                resolutionRow
                codecRow
                if let t = tier, cat.hasHDR(at: t) { hdrRow }
                containerRow
                pictureRow
            }
            if analysis.choices.kind != .videoOnly {
                if cat.languages.count > 1 { languageRow }
                if analysis.choices.kind == .audioOnly { audioFormatRow }
            }
            if analysis.choices.kind != .audioOnly, !(cat.humanSubtitles.isEmpty && cat.automaticSubtitles.isEmpty) {
                SubtitleRow(analysis: analysis)
            }
            if let d = cat.media.duration, d >= 5 {
                ClipRow(analysis: analysis, duration: d, chapters: cat.media.chapters)
            }
        }
    }

    // MARK: Rows

    var resolutionRow: some View {
        let best = FormatSelector.bestTier(cat, { var c = analysis.choices; c.resolution = .best; return c }(), playback: model.playback)
        return ChoiceRow(title: "Resolution", symbol: "rectangle.on.rectangle",
                         explanation: Explain.resolution(analysis.choices.resolution, catalogue: cat, bestIs: best)) {
            PillButton("Best", detail: best.map { "\($0.name) · " + sizeText(\.resolution, .best) },
                       selected: analysis.choices.resolution == .best,
                       help: "The highest resolution that plays on this Mac") { set(\.resolution, .best) }
            ForEach(cat.tiers, id: \.self) { t in
                let why = unavailable(\.resolution, .tier(t))
                PillButton(t.name, detail: sizeText(\.resolution, .tier(t)), selected: analysis.choices.resolution == .tier(t),
                           enabled: why == nil || analysis.choices.resolution == .tier(t),
                           help: why ?? "\(t.plainLabel): \(Explain.resolution(.tier(t), catalogue: cat).summary)") { set(\.resolution, .tier(t)) }
            }
        }
    }

    @ViewBuilder var codecRow: some View {
        let codecs = cat.codecs(at: tier)
        if codecs.count > 1 {
            ChoiceRow(title: "Video format", symbol: "film", explanation: Explain.codec(analysis.choices.codec, playback: model.playback)) {
                PillButton("Automatic", detail: analysis.choices.codec == .automatic ? plan?.video?.videoCodec.map { "Using \($0.name)" } ?? "Best that fits" : "Best that fits",
                           selected: analysis.choices.codec == .automatic,
                           help: "Digby picks the best-quality format that fits your file type") { set(\.codec, .automatic) }
                ForEach(codecs, id: \.self) { c in
                    let why = unavailable(\.codec, .specific(c))
                    PillButton(c.plainLabel, detail: c.name, selected: analysis.choices.codec == .specific(c),
                               enabled: why == nil || analysis.choices.codec == .specific(c),
                               help: why ?? Explain.codec(.specific(c), playback: model.playback).summary) { set(\.codec, .specific(c)) }
                }
            }
        }
    }

    var hdrRow: some View {
        ChoiceRow(title: "Brightness range", symbol: "sun.max", explanation: analysis.choices.preferHDR ? Explain.hdr
                  : Explanation("Standard (SDR): looks right on every screen and in every app.", pros: ["Safe everywhere"], cons: ["Not as vivid as HDR on HDR screens"])) {
            PillButton("Standard", detail: "SDR", selected: !analysis.choices.preferHDR) { set(\.preferHDR, false) }
            PillButton("Vivid", detail: "HDR", selected: analysis.choices.preferHDR) { set(\.preferHDR, true) }
        }
    }

    var containerRow: some View {
        ChoiceRow(title: "File type", symbol: "doc", explanation: Explain.container(analysis.choices.container)) {
            ForEach(Container.allCases, id: \.self) { k in
                let why = unavailable(\.container, k)
                PillButton(k.name, detail: why == nil ? k.plainLabel : "Not at \(tier?.name ?? "this quality")", selected: analysis.choices.container == k,
                           enabled: why == nil || analysis.choices.container == k,
                           help: why ?? Explain.container(k).summary) { set(\.container, k) }
            }
        }
    }

    /// Keep the picture as the site sends it, or convert it to H.264: shown whenever that choice matters
    /// (a format this file type can't hold, or this Mac can't play), and switchable both ways.
    @ViewBuilder var pictureRow: some View {
        let ch = analysis.choices
        var withConvert: Choices { var c = ch; c.convertPicture = true; c.keepSiteFile = false; return c }
        var asIs: Choices { var c = ch; c.convertPicture = false; return c }
        let convertPlan = FormatSelector.select(cat, withConvert, playback: model.playback).plan
        let asIsResult = FormatSelector.select(cat, asIs, playback: model.playback)
        let relevant = ch.convertPicture || convertPlan?.videoConverted == true
        if relevant, ch.kind != .audioOnly {
            let source = (asIsResult.plan?.video ?? convertPlan?.video)?.videoCodec
            let keepWorks = asIsResult.plan != nil || cat.video.contains { $0.ext == ch.container.rawValue }
            ChoiceRow(title: "Picture", symbol: "wand.and.rays", explanation: ch.convertPicture
                ? Explanation("Re-encodes the picture as H.264 so it plays on any device, including this Mac.",
                              pros: ["Plays everywhere: QuickTime, Photos, iPhone, TVs, editors"],
                              cons: ["Takes about as long as the video to prepare", "Very slightly softer than the original"])
                : Explanation("The picture exactly as the site sends it\(source.map { " (\($0.name))" } ?? ""): best quality, fastest.",
                              pros: ["No quality lost", "Ready as soon as it’s downloaded"],
                              cons: source.map { s in ["\(s.name) may not play in QuickTime, Photos or on older devices"] } ?? [])) {
                PillButton("Keep as is", detail: source?.name ?? "Original", selected: !ch.convertPicture, enabled: keepWorks,
                           help: keepWorks ? "Picture copied exactly as the site sends it" : "This file type can’t hold the site’s picture without converting") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        analysis.choices.convertPicture = false
                        if asIsResult.plan == nil { analysis.choices.keepSiteFile = true }
                    }
                }
                PillButton("Convert to H.264", detail: "Plays everywhere", selected: ch.convertPicture) {
                    withAnimation(.easeOut(duration: 0.15)) { analysis.choices.convertPicture = true; analysis.choices.keepSiteFile = false }
                }
            }
        }
    }

    /// Why an option can't be chosen with the other current choices (nil when it can).
    func unavailable<V>(_ key: WritableKeyPath<Choices, V>, _ value: V) -> String? {
        var c = analysis.choices; c[keyPath: key] = value; c.manualVideoID = nil; c.manualAudioID = nil
        if case .unsatisfiable(let reason, _) = FormatSelector.select(cat, c, playback: model.playback) { return reason }
        return nil
    }

    var languageRow: some View {
        let current: AudioLanguage? = {
            switch analysis.choices.language {
            case .original: return cat.originalLanguage
            case .language(let c): return cat.languages.first { $0.code == c }
            }
        }()
        return ChoiceRow(title: "Sound language", symbol: "globe", explanation: current.map(Explain.language)) {
            ForEach(cat.languages) { l in
                let choice: LanguageChoice = l.isOriginal ? .original : .language(l.code)
                PillButton(l.name, detail: l.isOriginal ? "Original" : (l.isDubbed ? "Dubbed" : "Translated"),
                           selected: analysis.choices.language == choice) { set(\.language, choice) }
            }
        }
    }

    var audioFormatRow: some View {
        ChoiceRow(title: "Audio file", symbol: "waveform", explanation: Explain.audioOutput(analysis.choices.audioOutput)) {
            ForEach(AudioOutput.allCases, id: \.self) { o in
                PillButton(o == .original ? "As it is" : o.name, detail: o == .original ? soundSourceName : o.plainLabel,
                           selected: analysis.choices.audioOutput == o, help: Explain.audioOutput(o).summary) { set(\.audioOutput, o) }
            }
        }
    }

    var soundSourceName: String {
        (plan?.audio?.audioCodec?.name).map { "Original \($0)" } ?? "Original"
    }

    // MARK: Helpers

    func set<V>(_ key: WritableKeyPath<Choices, V>, _ value: V) {
        withAnimation(.easeOut(duration: 0.15)) {
            analysis.choices[keyPath: key] = value
            analysis.choices.manualVideoID = nil; analysis.choices.manualAudioID = nil
            analysis.profileID = nil
        }
    }

    /// The size this option would give with the other choices unchanged, or why it isn't possible.
    func sizeText<V>(_ key: WritableKeyPath<Choices, V>, _ value: V) -> String {
        var c = analysis.choices; c[keyPath: key] = value; c.manualVideoID = nil; c.manualAudioID = nil
        switch FormatSelector.select(cat, c, playback: model.playback) {
        case .ready(let p): return p.size.map { Fmt.size($0) } ?? "—"
        case .unsatisfiable:
            if case .specific(let codec) = c.codec, case .tier(let t) = c.resolution, !cat.codecs(at: t).contains(codec) { return "No \(codec.name)" }
            return "Not in \(c.container.name)"
        }
    }
}

/// Three large choices: what kind of file.
struct KindPicker: View {
    @Binding var kind: DownloadKind
    var hasVideo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Download")
            HStack(spacing: 10) {
                ForEach(DownloadKind.allCases, id: \.self) { k in
                    let on = kind == k, enabled = hasVideo || k == .audioOnly
                    Button { kind = k } label: {
                        HStack(spacing: 9) {
                            Image(systemName: k.systemImage).font(.system(size: 17, weight: .regular))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(k.label).font(.system(size: 13, weight: .semibold))
                                Text(Explain.kind(k).summary).font(.caption).lineLimit(2).opacity(0.75)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .foregroundStyle(on ? Brand.accent : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? Brand.accent.opacity(0.1) : Color.secondary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? Brand.accent : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                        .opacity(enabled ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
    }
}

struct SubtitleRow: View {
    @Bindable var analysis: Analysis
    var cat: FormatCatalogue { analysis.catalogue }
    var body: some View {
        let s = analysis.choices.subtitles
        VStack(alignment: .leading, spacing: 10) {
            ChoiceRow(title: "Subtitles", symbol: "captions.bubble", explanation: Explain.subtitles(s.mode)) {
                ForEach(SubtitleMode.allCases, id: \.self) { m in
                    PillButton(m.label, selected: s.mode == m) { analysis.choices.subtitles.mode = m }
                }
            }
            if s.mode != .none {
                let langs = Array(Set((cat.humanSubtitles + (s.includeAutomatic ? cat.automaticSubtitles : [])).map { Languages.base($0.language) })).sorted()
                FlowLayout(spacing: 6) {
                    PillButton("All languages", selected: s.all) { analysis.choices.subtitles.all.toggle() }
                    ForEach(langs, id: \.self) { code in
                        let isAuto = !cat.humanSubtitles.contains { Languages.base($0.language) == code }
                        let on = s.all || s.languages.contains(code) || (s.languages.isEmpty && !s.all && code == (cat.originalLanguage?.code ?? "en"))
                        PillButton(Languages.name(code), detail: isAuto ? "Automatic" : "By a person", selected: on) {
                            var l = s.languages.isEmpty ? [cat.originalLanguage?.code ?? "en"] : s.languages
                            if let i = l.firstIndex(of: code) { l.remove(at: i) } else { l.append(code) }
                            analysis.choices.subtitles.languages = l; analysis.choices.subtitles.all = false
                        }
                    }
                }
                TranslateMenu(analysis: analysis)
                if !cat.automaticSubtitles.isEmpty {
                    Toggle(isOn: $analysis.choices.subtitles.includeAutomatic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include automatic captions")
                            Text(Explain.automaticSubtitles.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

/// "You'll get": the result in one line, the size, and an honest status.
struct PlanSummary: View {
    var result: SelectionResult
    var catalogue: FormatCatalogue
    var apply: (Choices) -> Void

    var body: some View {
        switch result {
        case .ready(let p):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("You’ll get")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.size(p.size)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(p.size == nil ? "The site doesn’t say" : p.size!.isExact ? "Exact size" : "Estimated size")
                            .font(.caption).foregroundStyle(.secondary)
                            .help(Explain.size(p.size).summary)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(p.chips(catalogue: catalogue), id: \.self) { Chip($0, tint: Brand.accent) }
                    if !p.subtitles.isEmpty {
                        Chip("Subtitles: " + (p.translateTo.map { SubtitleTranslation.name($0) + " (translated)" + (p.burnsSubtitles ? "" : ", ") } ?? "")
                             + (p.translateTo != nil && p.burnsSubtitles ? "" : p.subtitles.map { Languages.name($0.language) + ($0.isAutomatic ? " (auto)" : "") }.joined(separator: ", ")),
                             systemImage: "captions.bubble", tint: Brand.accent)
                    }
                }
                if !p.convertsAnything {
                    InfoRow(p.kind == .audioOnly ? "Sound copied exactly as the site provides it: no quality lost."
                                                 : "Picture and sound copied exactly as the site provides them: no quality lost.",
                            systemImage: "checkmark.circle.fill", tint: Brand.good)
                }
                ForEach(p.notes, id: \.self) { InfoRow($0, systemImage: "info.circle.fill", tint: Brand.warn) }

            }
        case .unsatisfiable(let reason, let alts):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This combination isn’t available").font(TypeStyle.headline)
                        Text(reason + " Digby won’t quietly swap in something lower.").foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !alts.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(alts) { a in Button(a.label) { apply(a.choices) }.buttonStyle(QuietButtonStyle()) }
                    }
                    .padding(.leading, 24)
                }
            }
            .padding(14)
            .background(Brand.warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct DownloadBar: View {
    @Environment(AppModel.self) private var model
    @Bindable var analysis: Analysis
    var result: SelectionResult

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(model.profiles) { p in
                    Button { analysis.choices = p.choices; analysis.profileID = p.id } label: {
                        Label { Text(p.name); Text(p.summary) } icon: { Image(systemName: p.symbol) }
                    }
                }
                Divider()
                Button("Save These Choices as a Profile…") {
                    let a = NSAlert(); a.messageText = "Name this profile"
                    a.informativeText = "It will appear in Profiles for every download. Manage profiles in Settings → Downloads."
                    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); field.placeholderString = "e.g. Lectures for iPad"
                    a.accessoryView = field; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
                    a.window.initialFirstResponder = field
                    if a.runModal() == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        var c = analysis.choices; c.manualVideoID = nil; c.manualAudioID = nil; c.clip = nil; c.subtitles.translateTo = nil
                        model.saveProfile(named: field.stringValue, choices: c)
                    }
                }
            } label: {
                Label(analysis.profileID.flatMap { id in model.profiles.first { $0.id == id }?.name } ?? "Profiles", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Ready-made sets of choices, such as Universal Compatibility or Archive")

            Button { analysis.advanced.toggle() } label: {
                Label(analysis.advanced ? "Hide Every Format" : "See Every Format", systemImage: "tablecells")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Advanced: the full list of streams the site offers, with technical details")

            Spacer(minLength: 8)
            SaveToMenu(projectID: $analysis.projectID, audio: analysis.choices.kind == .audioOnly) {
                model.newProjectRequest = NewProjectRequest(forAnalysis: analysis)
            }
            .font(.callout)
            OvernightToggle(on: $analysis.overnight)
            Button(analysis.overnight ? "Download Overnight" : "Download") { model.startDownload(analysis) }
                .buttonStyle(ProminentButtonStyle())
                .disabled(result.plan == nil)
                .keyboardShortcut(.return, modifiers: .command)
                .help(analysis.overnight ? "Waits in Downloading until \(AppModel.clock(model.overnightStart)), then downloads" : "")
        }
        .padding(.top, 4)
    }
}

/// "Translate into…": the chosen subtitles, translated on this Mac by macOS (macOS 15 and later).
struct TranslateMenu: View {
    @Bindable var analysis: Analysis
    var body: some View {
        let to = analysis.choices.subtitles.translateTo
        HStack(spacing: 8) {
            Image(systemName: "character.bubble").foregroundStyle(to == nil ? Color.secondary : Brand.accent)
            Text("Translate into").font(.callout)
            Menu {
                Toggle("Don’t translate", isOn: Binding(get: { to == nil }, set: { if $0 { analysis.choices.subtitles.translateTo = nil } }))
                Divider()
                ForEach(SubtitleTranslation.targets, id: \.self) { code in
                    Toggle(SubtitleTranslation.name(code), isOn: Binding(get: { to == code }, set: { if $0 { analysis.choices.subtitles.translateTo = code } }))
                }
            } label: { Text(to.map(SubtitleTranslation.name) ?? "Don’t translate") }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(!SubtitleTranslation.isAvailable)
            Text(SubtitleTranslation.isAvailable ? "On this Mac, private: nothing is sent anywhere." : "Needs macOS 15 or later.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .help("For languages the site doesn’t offer: macOS translates the subtitles line by line, on this Mac. Machine translation can get names, jokes and slang wrong.")
    }
}
