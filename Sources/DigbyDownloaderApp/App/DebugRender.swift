import SwiftUI
import AppKit
import DigbyDownloadCore

/// Developer aid: `DIGBY_DL_RENDER=/path/dir` makes the app put itself into every designed state and
/// save PNGs of its own window (light and dark), then quit. Needs no Screen Recording permission,
/// because the app only draws its own views. `DIGBY_DL_STATES=ready,queue` limits the set.
enum DebugRender {
    /// `DIGBY_DL_E2E=<link>` + `DIGBY_DL_E2E_OUT=<dir>`: paste the link, analyse, download with the default
    /// choices (optionally `DIGBY_DL_E2E_RES=720`), saving a snapshot at each stage, then quit. Real engine.
    @MainActor static func runEndToEnd(model m: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let link = env["DIGBY_DL_E2E"], let dir = env["DIGBY_DL_E2E_OUT"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            func snap(_ name: String) async {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await savePanel(AnyView(ComposerContent().environment(m).frame(width: 760).padding(24)), appearance: false, to: "\(dir)/\(name).png")
                print("e2e: \(name)")
            }
            while !m.enginesReady { try? await Task.sleep(nanoseconds: 300_000_000) }
            m.urlText = link; m.analyse()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await snap("1-analysing")
            // Wait through analysis and any diagnosing/recovery (snapshot the diagnosing card once).
            var sawDiagnosis = false
            while true {
                if case .analysing = m.composer { try? await Task.sleep(nanoseconds: 300_000_000); continue }
                if case .failed(_, let d) = m.composer, d.inProgress {
                    if !sawDiagnosis { sawDiagnosis = true; await snap("1b-diagnosing") }
                    try? await Task.sleep(nanoseconds: 300_000_000); continue
                }
                break
            }
            if case .ready(let a) = m.composer {
                if let r = env["DIGBY_DL_E2E_RES"].flatMap(Int.init).flatMap(ResolutionTier.init(rawValue:)) { a.choices.resolution = .tier(r) }
                if a.result(m.playback).plan == nil { a.choices.resolution = .best }
                if a.result(m.playback).plan == nil { a.choices.container = .mkv }
                if let c = env["DIGBY_DL_E2E_CLIP"]?.split(separator: "-").compactMap({ Double($0) }), c.count == 2 {
                    a.choices.clip = ClipRange(start: c[0], end: c[1], exact: env["DIGBY_DL_E2E_EXACT"] != nil)
                }
                print("e2e: title \(a.catalogue.media.title) | \(a.result(m.playback).plan?.chips(catalogue: a.catalogue).joined(separator: " · ") ?? "no plan") | notice: \(a.catalogue.media.notice ?? "-")")
                await snap("2-ready")
                m.startDownload(a)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await snap("3-downloading")
                // Starting a download moves it to Downloading (its tab closes), so wait on the queue itself.
                while m.leaves.contains(where: { $0.isActive || $0.state == .waiting }) { try? await Task.sleep(nanoseconds: 500_000_000) }
                if let i = m.leaves.last {
                    switch i.state {
                    case .done(let url): print("e2e: DONE \(i.size.map { Fmt.bytes($0.bytes) } ?? "") \(i.summary) → \(url.lastPathComponent)")
                    case .failed(let why): print("e2e: FAILED \(why)")
                    default: print("e2e: ended as \(i.state)")
                    }
                }
                if let h = m.history.first { print("e2e: history \(h.succeeded ? "✓" : "✗") \(h.title) | \(h.detail)") }
            }
            if case .failed(_, let d) = m.composer { print("e2e: FAILED \(d.title) — \(d.failure?.detail.prefix(200) ?? "")") }
            await snap("4-result")
            print("e2e: done")
            NSApp.terminate(nil)
        }
    }

    /// `DIGBY_DL_CATCH=<page>` + `DIGBY_DL_E2E_OUT=<dir>`: open the page in the catcher, start its video muted,
    /// catch the stream, analyse and download it with the real engine, snapshotting each stage; then quit.
    @MainActor static func runCatchTest(model m: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let page = env["DIGBY_DL_CATCH"].flatMap(URL.init(string:)), let dir = env["DIGBY_DL_E2E_OUT"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            while !m.enginesReady { try? await Task.sleep(nanoseconds: 300_000_000) }
            PageCatcherWindow.show(page, model: m)
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let c = PageCatcherWindow.current, let w = PageCatcherWindow.window else { NSApp.terminate(nil); return }
            _ = try? await c.webView?.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v => { v.muted = true; v.play && v.play() }); 1")
            for _ in 0..<60 where c.streams.isEmpty { try? await Task.sleep(nanoseconds: 500_000_000) }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            save(w, to: "\(dir)/1-catcher.png")
            print("catch: \(c.streams.map { "\($0.kind) \($0.label) \($0.url.host ?? "")" })")
            if env["DIGBY_DL_CATCH_MODE"] == "page" {
                print("catch: using Download from This Page")
                m.analyse(pageWithSession: await c.sessionPage(), fallback: []); w.close()
            } else {
                guard let best = c.best else { print("catch: nothing caught"); NSApp.terminate(nil); return }
                let p = await c.page(for: best)
                m.analyse(caught: best, on: p); w.close()
            }
            while true { if case .analysing = m.composer { try? await Task.sleep(nanoseconds: 300_000_000) } else { break } }
            await savePanel(AnyView(ComposerContent().environment(m).frame(width: 760).padding(24)), appearance: false, to: "\(dir)/2-ready.png")
            if case .failed(_, let d) = m.composer { print("catch: FAILED \(d.title) \(d.failure?.detail.prefix(160) ?? "")") }
            if case .ready(let a) = m.composer {
                if a.result(m.playback).plan == nil { a.choices.container = .mkv }
                print("catch: title \(a.catalogue.media.title) | tiers \(a.catalogue.tiers.map(\.name))")
                print("catch: plan \(a.result(m.playback).plan?.chips(catalogue: a.catalogue).joined(separator: " · ") ?? "none")")
                m.startDownload(a)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                while true { if case .downloading = m.composer { try? await Task.sleep(nanoseconds: 500_000_000) } else { break } }
            }
            await savePanel(AnyView(ComposerContent().environment(m).frame(width: 760).padding(24)), appearance: false, to: "\(dir)/3-result.png")
            print("catch: done"); NSApp.terminate(nil)
        }
    }

    @MainActor static func runIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        runEndToEnd(model: model)
        runCatchTest(model: model)
        guard let dir = env["DIGBY_DL_RENDER"] else { return }
        let m = model
        let only = env["DIGBY_DL_STATES"].map { Set($0.split(separator: ",").map(String.init)) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.title.contains("Digby") }) else {
                print("render: no window"); NSApp.terminate(nil); return
            }
            win.setContentSize(NSSize(width: env["DIGBY_DL_WIDTH"].flatMap(Double.init) ?? 1180, height: 940))
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for (name, setup) in states(m) where only?.contains(name) ?? true {
                    setup()
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    save(win, to: "\(dir)/\(name)-\(dark ? "dark" : "light").png")
                    if m.section == .download, case .empty = m.composer {} else if m.section == .download, !dark {
                        // the whole page, beyond the window's height
                        await savePanel(AnyView(ComposerContent().environment(m).frame(width: 760).padding(24)), appearance: dark,
                                        to: "\(dir)/\(name)-full.png")
                    }
                }
                for (name, view) in panels(model) where only?.contains(name) ?? true {
                    await savePanel(view, appearance: dark, to: "\(dir)/\(name)-\(dark ? "dark" : "light").png")
                }
            }
            print("render: done → \(dir)")
            NSApp.terminate(nil)
        }
    }

    @MainActor static func states(_ m: AppModel) -> [(String, () -> Void)] {
        func ready(_ change: @escaping (Analysis) -> Void = { _ in }) -> () -> Void {
            { m.section = .download; m.urlText = "https://www.youtube.com/watch?v=sample-aurora"
              let a = m.makeAnalysis(SampleMedia.video); change(a); m.composer = .ready(a) }
        }
        let url = URL(string: "https://www.youtube.com/watch?v=sample-aurora")!
        let downloading = QueueItem(title: SampleMedia.video.title, site: "YouTube", summary: "4K 60 · AV1 · AAC · English (original) · MP4",
                                    size: SizeEstimate(bytes: 1_260_000_000, isExact: true),
                                    state: .downloading(fraction: 0.47, speed: 12_400_000, remaining: 54))
        let done = QueueItem(title: SampleMedia.video.title, site: "YouTube", summary: "4K 60 · AV1 · AAC · English (original) · MP4",
                             size: SizeEstimate(bytes: 1_260_000_000, isExact: true),
                             state: .done(URL(fileURLWithPath: NSHomeDirectory() + "/Movies/Digby/Above the Clouds.mp4")))
        return [
            ("empty", { m.section = .download; m.urlText = ""; m.clipboardSuggestion = URL(string: "https://www.youtube.com/watch?v=e1"); m.drafts = []; m.selectedDraftID = nil }),
            ("analysing", { m.section = .download; m.urlText = url.absoluteString; m.clipboardSuggestion = nil; m.composer = .analysing(url, step: 1) }),
            ("ready", ready()),
            ("tabs", { m.section = .download; m.linksAsList = false
                let a = m.makeAnalysis(SampleMedia.video)
                let d1 = Draft(url: URL(string: "https://vimeo.com/000000")!, state: .analysing(URL(string: "https://vimeo.com/000000")!, step: 1))
                let d2 = Draft(url: URL(string: "https://soundcloud.com/x")!, state: .ready(m.makeAnalysis(SampleMedia.simple))); d2.title = "Morning Fog, Short Film"
                let d3 = Draft(url: URL(string: "https://rumble.com/v1")!, state: .failed(URL(string: "https://rumble.com/v1")!, MockData.privateDiagnosis))
                let d0 = Draft(url: SampleMedia.video.webpageURL, state: .ready(a)); d0.title = SampleMedia.video.title
                m.drafts = [d0, d1, d2, d3]; m.selectedDraftID = d0.id }),
            ("list", { m.linksAsList = true }),
            ("ready-1080", ready { $0.choices.resolution = .tier(.p1080) }),
            ("ready-subtitles", ready { $0.choices.resolution = .tier(.p1080); $0.choices.language = .language("es")
                $0.choices.subtitles = SubtitleChoice(mode: .embed, languages: ["en", "es"]) }),
            ("ready-audio", ready { $0.choices.kind = .audioOnly; $0.choices.audioOutput = .mp3 }),
            ("unsatisfiable", ready { $0.choices.resolution = .tier(.p2160); $0.choices.container = .mov }),
            ("advanced", ready { $0.choices.resolution = .tier(.p1080); $0.advanced = true }),
            ("collection", { m.section = .download; m.urlText = "https://www.youtube.com/playlist?list=sample"; m.composer = .collection(CollectionDraft(SampleMedia.playlist)) }),
            ("downloading", { m.section = .download; m.composer = .downloading(downloading) }),
            ("completed", { m.section = .download; m.composer = .completed(done) }),
            ("failed", { m.section = .download; m.composer = .failed(url, MockData.privateDiagnosis) }),
            ("failed-out-of-sight", { m.section = .download
                let page = URL(string: "https://astralcodexten.substack.com/p/sample")!
                m.composer = .failed(page, Diagnosis(ErrorClassifier.classify(stderr: "ERROR: Unsupported URL: \(page.absoluteString)"), engineVersion: "2026.10.26")) }),
            ("diagnosing", { m.section = .download; m.engineBanner = "Updating the extraction engine: yt-dlp 2026.10.26 → 2026.11.10 (keeps downloads working when sites change)"
                m.composer = .failed(url, MockData.outdatedDiagnosis) }),
            ("queue", { m.engineBanner = nil; m.section = .queue }),
            ("history", { m.section = .history }),
            ("project", { m.openProject(m.projects[0]) }),
            ("trim", ready { $0.choices.resolution = .tier(.p1080); $0.choices.clip = ClipRange(start: 83, end: 166)
                $0.choices.subtitles = SubtitleChoice(mode: .burn, languages: ["en"]); $0.choices.subtitles.translateTo = "ja"; $0.overnight = true }),
            ("queue-overnight", { m.currentProjectID = nil; m.selectedProjectID = nil; m.section = .queue; m.leaves.first { $0.state == .waiting }?.overnight = true }),
            ("queue-details", { m.section = .queue; if let i = m.leaves.first(where: { $0.details != nil }) ?? m.leaves.first { m.expandedQueueIDs = [i.id] } }),
            ("resume", { m.section = .history
                m.lastSession = LastSessionReport(items: [
                    LastSessionItem(id: "1", name: "Northern Lights over Tromsø", outcome: .finished),
                    LastSessionItem(id: "2", name: "Aurora timelapse (4K)", outcome: .stopped, reason: "Was downloading", canResume: true),
                    LastSessionItem(id: "3", name: "Lecture 4: Plasma physics", outcome: .stopped, reason: "Was waiting its turn", canResume: true),
                    LastSessionItem(id: "4", name: "Live stream replay", outcome: .failed, reason: "The site needs you to sign in", canResume: true),
                    LastSessionItem(id: "5", name: "Trailer", outcome: .cancelled)], noun: "download") }),
        ]
    }

    @MainActor static func panels(_ m: AppModel) -> [(String, AnyView)] {
        [
            ("settings-general", AnyView(GeneralSettings().environment(m).frame(width: 620, height: 420))),
            ("settings-downloads", AnyView(DownloadSettings().environment(m).frame(width: 680, height: 600))),
            ("settings-engines", AnyView(EngineSettings().environment(m).frame(width: 620, height: 520))),
            ("catcher-empty", AnyView(PageCatcherView(catcher: PageCatcher(url: URL(string: "about:blank")!), close: {}).environment(m).frame(width: 900, height: 700))),
            ("catcher-caught", AnyView(PageCatcherView(catcher: {
                let c = PageCatcher(url: URL(string: "about:blank")!)
                c.streams = [CaughtStream(url: URL(string: "https://cdn.example.com/master.m3u8")!, kind: .adaptive, maxHeight: 1080),
                             CaughtStream(url: URL(string: "https://media.example.com/clip.mp4")!, kind: .file, maxHeight: 720, bytes: 310_000_000),
                             CaughtStream(url: URL(string: "https://ads.example.net/promo.mp4")!, kind: .file, maxHeight: 360, bytes: 4_000_000)]
                return c }(), close: {}).environment(m).frame(width: 900, height: 700))),
            ("settings-browser", AnyView(BrowserSettings().frame(width: 680, height: 600))),
            ("watching", AnyView(WatchingView().environment(m).frame(width: 820, height: 420))),
            ("project-sheet", AnyView(ProjectSheet(request: NewProjectRequest()).environment(m))),
            ("settings-diagnostics", AnyView(DiagnosticsSettings().environment(m).frame(width: 680, height: 600))),
            ("settings-privacy", AnyView(PrivacySettings().environment(m).frame(width: 620, height: 470))),
            ("menubar", AnyView(MenuBarView().environment(m))),
            ("signin-sheet", AnyView(SignInSheet(site: .youtube, retry: nil).environment(m))),
            ("details", AnyView(DetailsView(details: {
                var ch = Choices(); ch.resolution = .tier(.p1080)
                let cat = FormatCatalogue(SampleMedia.video)
                var d = DownloadDetails.make(catalogue: cat, choices: ch, plan: FormatSelector.select(cat, ch, playback: m.playback).plan!)
                d.verified = "1920×1080 · H.264 · AAC · 12:34"; d.file = URL(fileURLWithPath: NSHomeDirectory() + "/Movies/Digby/Above the Clouds (1080p).mp4")
                d.bytes = 581_000_000; d.completedAt = Date()
                return d }()).environment(m))),
            ("sidebar", AnyView(Sidebar().environment(m).frame(width: 230, height: 420))),
            ("glossary", AnyView(GlossaryView())),
            ("about", AnyView(AboutView())),
        ]
    }

    /// Snapshot of a window's content (layer tree render; cacheDisplay misses layer-backed SwiftUI content).
    @MainActor static func save(_ win: NSWindow, to path: String) {
        guard let view = win.contentView?.superview ?? win.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let scale = win.backingScaleFactor, size = view.bounds.size
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if ProcessInfo.processInfo.environment["DIGBY_DL_CACHE"] != nil {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-cache.png")))
        }
        // Prefer the layer render where it has content (SwiftUI drawing lives in layers).
        if let layer = view.layer,
           let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
            ctx.scaleBy(x: scale, y: scale)
            layer.render(in: ctx)
            if let img = ctx.makeImage() {
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                return
            }
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Snapshot of a free-standing view, hosted in an off-screen window.
    @MainActor static func savePanel(_ view: AnyView, appearance dark: Bool, to path: String) async {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host; w.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 500_000_000)
        save(w, to: path)
        w.orderOut(nil)
    }
}
