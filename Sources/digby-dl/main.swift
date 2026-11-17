// digby-dl: command-line front end to DigbyDownloadCore (used for end-to-end tests; handy for scripting).
//
//   digby-dl engines [install|check|rollback <tool>] [--channel stable|nightly|experimental]
//   digby-dl analyse <url> [choices…]
//   digby-dl download <url> [choices…] [--to DIR] [--name TEMPLATE]
//   digby-dl version
//
// --json (analyse, download, version): one JSON object per line, for other apps:
//   {"event":"analysed","title","site","uploader","duration","webpage"}  {"event":"phase","text"}
//   {"event":"progress","done","total","speed"}  {"event":"done","path","bytes","summary","format"}
//   {"event":"error","kind","title","message"}   — kind is Failure.Kind (plus "playlist", "notAvailable", "usage").
// The interface is versioned by "protocol" in `digby-dl version --json`.
//
// Choices: --kind video|video-only|audio  --res best|2160|1080|…  --codec auto|avc|hevc|av1|vp9
//          --container mp4|mkv|webm|mov  --audio original|m4a|mp3|flac|wav|opus  --lang CODE  --fallback CODE
//          --subs embed|files  --sub-langs en,es  --auto-subs  --hdr  --video-id ID  --audio-id ID
import Foundation
import AppKit
import VideoToolbox
import DigbyDownloadCore

setvbuf(stdout, nil, _IOLBF, 0)
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ name: String) -> Bool { if let i = args.firstIndex(of: name) { args.remove(at: i); return true }; return false }
var jsonMode = false
func emit(_ o: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes, .sortedKeys]) { print(String(decoding: d, as: UTF8.self)) }
}
func fail(_ s: String, kind: String = "unknown", title: String? = nil) -> Never {
    if jsonMode { emit(["event": "error", "kind": kind, "title": title ?? s, "message": s]); exit(1) }
    FileHandle.standardError.write(Data("✗ \(s)\n".utf8)); exit(1)
}
jsonMode = flag("--json")

let playback = PlaybackEnvironment(decodesAV1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))

func choices() -> Choices {
    var c = Choices()
    switch option("--kind") { case "video-only"?: c.kind = .videoOnly; case "audio"?: c.kind = .audioOnly; default: break }
    if let r = option("--res"), r != "best" { guard let n = Int(r), let t = ResolutionTier(rawValue: n) else { fail("unknown resolution \(r)") }; c.resolution = .tier(t) }
    if let k = option("--codec"), k != "auto" { guard let v = VideoCodec(rawValue: k) else { fail("unknown codec \(k)") }; c.codec = .specific(v) }
    if let k = option("--container") { guard let v = Container(rawValue: k) else { fail("unknown container \(k)") }; c.container = v }
    if let a = option("--audio") { guard let v = AudioOutput(rawValue: a) else { fail("unknown audio format \(a)") }; c.audioOutput = v }
    if let l = option("--lang") { c.language = l == "original" ? .original : .language(l) }
    c.fallbackLanguage = option("--fallback")
    if let s = option("--subs") { c.subtitles.mode = s == "files" ? .files : .embed }
    if let s = option("--sub-langs") { if s == "all" { c.subtitles.all = true } else { c.subtitles.languages = s.split(separator: ",").map(String.init) } }
    c.subtitles.includeAutomatic = flag("--auto-subs")
    c.preferHDR = flag("--hdr")
    c.convertPicture = flag("--convert")
    c.keepSiteFile = flag("--keep-site-file")
    c.manualVideoID = option("--video-id"); c.manualAudioID = option("--audio-id")
    return c
}

func describe(_ m: MediaInfo, _ cat: FormatCatalogue) {
    print("“\(m.title)” — \(m.uploader ?? "?") · \(m.site) · \(m.duration.map { Fmt.duration($0) } ?? "length unknown")")
    if let n = m.notice { print("  notice: \(n)") }
    print("  \(cat.video.count) picture streams, \(cat.audio.count) sound streams" + (cat.excludedDRM > 0 ? ", \(cat.excludedDRM) copy-protected (ignored)" : ""))
    for t in cat.tiers { print("  \(t.name.padding(toLength: 6, withPad: " ", startingAt: 0)) \(cat.codecs(at: t).map(\.name).joined(separator: ", "))" + (cat.hasHDR(at: t) ? "  (HDR available)" : "")) }
    if !cat.languages.isEmpty { print("  sound: " + cat.languages.map { $0.name + ($0.isOriginal ? " (original)" : $0.isDubbed ? " (dub)" : "") }.joined(separator: ", ")) }
    if !cat.humanSubtitles.isEmpty || !cat.automaticSubtitles.isEmpty {
        print("  subtitles: \(cat.humanSubtitles.map(\.language).joined(separator: ", "))" + (cat.automaticSubtitles.isEmpty ? "" : "; automatic: \(cat.automaticSubtitles.map(\.language).joined(separator: ", "))"))
    }
}

func show(_ r: SelectionResult, _ cat: FormatCatalogue) {
    switch r {
    case .ready(let p):
        print("→ \(p.chips(catalogue: cat).joined(separator: " · "))  [\(p.formatExpression)]  \(Fmt.size(p.size))" + (p.size.map { $0.isExact ? " (exact)" : " (estimated)" } ?? ""))
        print(p.convertsAnything ? "  conversion: sound → \(p.outputExtension)" : "  no conversion: copied exactly")
        for n in p.notes { print("  note: \(n)") }
    case .unsatisfiable(let reason, let alts):
        print("✗ not available: \(reason)")
        for a in alts { print("  alternative: \(a.label)") }
    }
}

/// `--fixture file.json` plans from a saved engine answer instead of the network (tests, documentation).
let fixturePath = option("--fixture")
func analyse(_ url: URL) async -> AnalysisResult {
    if let f = fixturePath, let d = try? Data(contentsOf: URL(fileURLWithPath: f)), let r = try? YtDlpDecoder.decode(d) { return r }
    do { return try await YtDlpEngine().analyse(url) }
    catch let f as Failure {
        if jsonMode { fail(f.explanation, kind: f.kind.rawValue, title: f.title) }
        fail("\(f.title). \(f.explanation)\n  engine said: \(f.detail.prefix(400))")
    }
    catch { fail("\(error)") }
}

guard let command = args.first else { fail("usage: digby-dl engines|analyse|download …") }
args.removeFirst()
let channel = UpdateChannel(rawValue: option("--channel") ?? "stable") ?? .stable
let deps = DependencyManager.shared

switch command {
case "version":
    // Inside the app: …/Contents/Helpers/digby-dl → …/Contents/Info.plist
    let plist = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Info.plist")
    let v = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "dev"
    let missing = await deps.missing().map(\.rawValue)
    if jsonMode { emit(["tool": "digby-dl", "version": v, "protocol": 1, "enginesMissing": missing]) }
    else { print("digby-dl \(v) (protocol 1)" + (missing.isEmpty ? "" : " · engines not installed: \(missing.joined(separator: ", "))")) }

case "engines":
    let sub = args.first ?? "list"
    if sub == "install" {
        do {
            try await deps.ensureInstalled(channel: channel) { p in
                print("  \(p.step)" + (p.fraction.map { String(format: " %3.0f%%", $0 * 100) } ?? ""), terminator: p.fraction == nil ? "\n" : "\r")
            }
        } catch { fail("\(error)") }
        print("")
    } else if sub == "check" {
        for t in ToolID.allCases {
            do { let r = try await deps.latest(t, channel: channel); print("\(t.displayName): latest \(r.version) from \(r.source); sha256 \(r.sha256.prefix(16))…") }
            catch { print("\(t.displayName): \(error)") }
        }
    } else if sub == "update" {
        let have = await deps.installed()
        for t in ToolID.allCases {
            do {
                let r = try await deps.latest(t, channel: channel)
                if have[t]?.version == r.version { print("\(t.displayName) \(r.version) is current"); continue }
                try await deps.install(r) { p in print("  \(p.step)" + (p.fraction.map { String(format: " %3.0f%%", $0 * 100) } ?? ""), terminator: p.fraction == nil ? "\n" : "\r") }
            } catch { print("\(t.displayName): \(error)") }
        }
    } else if sub == "rollback", args.count > 1, let t = ToolID(rawValue: args[1]) {
        do { try await deps.rollback(t); print("rolled back \(t.displayName)") } catch { fail("\(error)") }
    }
    for (t, i) in await deps.installed().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("\(t.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) \(i.version)  (previous: \(i.previousVersion ?? "—"))  \(i.source)")
    }
    let missing = await deps.missing()
    if !missing.isEmpty { print("not installed: \(missing.map(\.displayName).joined(separator: ", "))") }

case "signin":
    // digby-dl signin youtube brave|chrome|…|off
    guard args.count >= 2 else { fail("usage: digby-dl signin youtube|<domain> <browser>|off") }
    let site = SignInSite(rawValue: args[0])
    var st = SignInSettings.load()
    if args[1] == "off" { SignInStore.forget(site); print("signed out of \(site.displayName) in Digby") }
    else {
        guard let b = Browser(rawValue: args[1]) else { fail("browsers: \(Browser.allCases.map(\.rawValue).joined(separator: ", "))") }
        st.sites[site] = .browser(b); try? FileManager.default.removeItem(at: SignInStore.jar(for: site))
        do { try st.save() } catch { fail("\(error)") }
        print("\(site.displayName): using your \(b.displayName) sign-in. \(b.permissionNote)")
    }

case "analyse", "download":
    let to = option("--to").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    let workID = option("--work-id"), pauseAt = option("--pause-at").flatMap(Double.init)
    let template = option("--name") ?? "{title} ({resolution})"
    let ch = choices()
    guard let s = args.first, let url = URL(string: s) else { fail("give a link", kind: "usage") }
    let started = Date()
    if jsonMode {
        // Machine-readable run for other Digby apps: no prompts, best plan for the default choices.
        switch await analyse(url) {
        case .collection(let c): fail("This address is a list of \(c.entries.count) videos, not one video.", kind: "playlist", title: "A playlist")
        case .single(let m):
            emit(["event": "analysed", "title": m.title, "site": m.site, "uploader": m.uploader ?? "", "duration": m.duration ?? 0, "webpage": m.webpageURL.absoluteString])
            let cat = FormatCatalogue(m)
            // As the app does: if the requested choices aren't offered, take the best the site has, in a file type it offers.
            var plan = FormatSelector.select(cat, ch, playback: playback).plan
            var c2 = ch
            if plan == nil { c2.resolution = .best; plan = FormatSelector.select(cat, c2, playback: playback).plan }
            for k in Container.allCases where plan == nil { c2.container = k; plan = FormatSelector.select(cat, c2, playback: playback).plan }
            guard let plan else {
                fail("No version of this video matches the requested choices.", kind: "notAvailable", title: "Not available")
            }
            guard command == "download" else { emit(["event": "plan", "format": plan.chips(catalogue: cat).joined(separator: " · ")]); break }
            let folder = to ?? Paths.defaultVideoFolder
            var req = DownloadRequest(media: m, plan: plan, folder: folder, fileName: FileNamer.render(template, media: m, plan: plan))
            req.workID = workID
            let token = CancelToken()
            signal(SIGTERM, SIG_IGN)
            let term = DispatchSource.makeSignalSource(signal: SIGTERM); term.setEventHandler { token.cancel() }; term.resume()
            let last = LockedTime()
            do {
                let out = try await Downloader().download(req, cancel: token) { e in
                    switch e {
                    case .phase(let s): emit(["event": "phase", "text": s])
                    case .progress(let d, let t, let sp, _): if last.due() { emit(["event": "progress", "done": d, "total": t ?? 0, "speed": sp ?? 0]) }
                    case .processing: break
                    }
                }
                emit(["event": "done", "path": out.file.path, "bytes": out.bytes, "summary": out.report.summary,
                      "format": plan.chips(catalogue: cat).joined(separator: " · ")])
            } catch let f as Failure { fail(f.explanation, kind: f.kind.rawValue, title: f.title) }
            catch { fail("\(error)") }
        }
        break
    }
    switch await analyse(url) {
    case .collection(let c):
        print("Playlist “\(c.title)” — \(c.entries.count) items")
        for e in c.entries.prefix(20) { print("  \(e.title) — \(e.url.absoluteString)") }
    case .single(let m):
        let cat = FormatCatalogue(m)
        describe(m, cat)
        print(String(format: "  analysed in %.1f s", Date().timeIntervalSince(started)))
        let result = FormatSelector.select(cat, ch, playback: playback)
        show(result, cat)
        guard command == "download", let plan = result.plan else { break }
        let folder = to ?? (plan.kind == .audioOnly ? Paths.defaultAudioFolder : Paths.defaultVideoFolder)
        var req = DownloadRequest(media: m, plan: plan, folder: folder, fileName: FileNamer.render(template, media: m, plan: plan))
        req.workID = workID
        let token = CancelToken()
        if let pauseAt { DispatchQueue.global().asyncAfter(deadline: .now() + pauseAt) { print("  pausing…"); token.pause() } }
        signal(SIGINT, SIG_IGN)
        let sig = DispatchSource.makeSignalSource(signal: SIGINT); sig.setEventHandler { print("\ncancelling…"); token.cancel() }; sig.resume()
        let last = LockedTime()
        do {
            let out = try await Downloader().download(req, cancel: token) { e in
                switch e {
                case .phase(let s): print("  \(s)…")
                case .progress(let d, let t, let sp, let eta):
                    guard last.due() else { return }
                    let pct = t.map { String(format: "%5.1f%%", Double(d) / Double(max(1, $0)) * 100) } ?? "  ?  "
                    print("  \(pct)  \(Fmt.bytes(d))\(t.map { " of " + Fmt.bytes($0) } ?? "")  \(sp.map { Fmt.speed($0) } ?? "")  \(eta.map { Fmt.remaining($0) } ?? "")")
                case .processing(let f): if let f, last.due() { print(String(format: "  preparing %3.0f%%", f * 100)) }
                }
            }
            print("✓ \(out.file.path)\n  \(Fmt.bytes(out.bytes)) · checked: \(out.report.summary)")
            for s in out.subtitleFiles { print("  subtitles: \(s.lastPathComponent)") }
            print(String(format: "  total %.1f s", Date().timeIntervalSince(started)))
        } catch let f as Failure where token.isPaused { print("⏸ paused; partial data kept in .digby-download-\(workID ?? "?")") ; _ = f
        } catch let f as Failure { fail("\(f.title). \(f.explanation)" + (f.detail.isEmpty ? "" : "\n  detail: \(f.detail.prefix(500))")) }
        catch { fail("\(error)") }
    }
default:
    fail("unknown command \(command)")
}

final class LockedTime: @unchecked Sendable {
    private let lock = NSLock(); private var t = Date.distantPast
    func due() -> Bool { lock.lock(); defer { lock.unlock() }; if Date().timeIntervalSince(t) > 1 { t = Date(); return true }; return false }
}
