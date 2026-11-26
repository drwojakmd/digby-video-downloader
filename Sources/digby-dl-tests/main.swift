// Unit tests for DigbyDownloadCore. Run: swift run digby-dl-tests (exit code 1 on any failure).
import Foundation
import DigbyDownloadCore
import SQLite3

var failures = 0, passed = 0
func check(_ cond: @autoclosure () -> Bool, _ name: String, file: String = #file, line: Int = #line) {
    if cond() { passed += 1 } else { failures += 1; print("✗ \(name)  (line \(line))") }
}

let m1 = PlaybackEnvironment(decodesAV1: false)     // M1/M2: no AV1 in QuickTime
let m3 = PlaybackEnvironment(decodesAV1: true)
let cat = FormatCatalogue(SampleMedia.video)
func plan(_ change: (inout Choices) -> Void = { _ in }, _ env: PlaybackEnvironment = m1, _ c: FormatCatalogue = cat) -> SelectionResult {
    var ch = Choices(); change(&ch); return FormatSelector.select(c, ch, playback: env)
}

// MARK: Families
check(VideoCodec(raw: "avc1.640028") == .avc, "avc1 → H.264")
check(VideoCodec(raw: "av01.0.12M.08") == .av1, "av01 → AV1")
check(VideoCodec(raw: "vp09.00.51.08") == .vp9, "vp09 → VP9")
check(VideoCodec(raw: "hvc1.2.4.L153") == .hevc, "hvc1 → HEVC")
check(AudioCodec(raw: "mp4a.40.2") == .aac, "mp4a → AAC")
check(ResolutionTier(width: 1920, height: 1080) == .p1080, "1920×1080 → 1080p")
check(ResolutionTier(width: 1920, height: 800) == .p1080, "cinemascope 1920×800 → 1080p")
check(ResolutionTier(width: 1080, height: 1920) == .p1080, "portrait 1080×1920 → 1080p")
check(ResolutionTier(width: 3840, height: 1608) == .p2160, "3840×1608 → 4K")
check(ResolutionTier(width: 854, height: 480) == .p480, "854×480 → 480p")
check(ResolutionTier(width: 256, height: 144) == .p144, "256×144 → 144p")
check(Container.mp4.holds(VideoCodec.av1) && !Container.mov.holds(VideoCodec.vp9) && !Container.webm.holds(VideoCodec.avc), "container ↔ video codec")
check(!Container.mp4.holds(AudioCodec.opus) && Container.mkv.holds(AudioCodec.opus) && Container.webm.holds(AudioCodec.opus), "container ↔ audio codec")

// MARK: Catalogue
check(cat.tiers == [.p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144], "only offered tiers, highest first")
check(!cat.video.contains { $0.ext == "mhtml" }, "storyboards dropped")
check(cat.codecs(at: .p2160) == [.av1, .vp9], "4K codecs")
check(cat.codecs(at: .p1080) == [.avc, .av1, .vp9], "1080p codecs")
check(cat.languages.first?.code == "en" && cat.languages.first?.isOriginal == true, "original language first")
check(cat.languages.count == 5, "five sound languages")
check(cat.hasHDR && cat.hasHDR(at: .p2160) && !cat.hasHDR(at: .p1080), "HDR only at 4K")
check(cat.humanSubtitles.count == 2 && cat.automaticSubtitles.count == 3, "human vs automatic subtitles")

// MARK: Selection — defaults
if let p = plan().plan {
    // Best + MP4 on an M1: 4K exists only as AV1/VP9, which QuickTime on an M1 can't play → the best that plays: 1080p60 H.264.
    check(p.video?.id == "299", "best/MP4/M1 → best that plays on this Mac: 1080p60 H.264 (got \(p.video?.id ?? "nil"))")
    check(p.audio?.id == "140", "AAC English original chosen for MP4 (copy)")
    check(p.audioAction == .copy && !p.convertsAnything, "no conversion")
    check(p.formatExpression == "299+140", "format expression")
    check(p.size?.isExact == true, "exact size when both streams report one")
    check(p.chips(catalogue: cat).contains("English (original)") == false, "chips combine codec and language")
    check(p.notes.contains { $0.contains("Best that plays on this Mac: 1080p") && $0.contains("choose 4K") }, "says 4K exists and how to get it")
    check(FormatSelector.bestTier(cat, Choices(), playback: m1) == .p1080, "Best resolves to 1080p on an M1")
}
if let p = plan({ $0.container = .mkv }).plan {
    check(p.video?.tier == .p2160, "MKV (not a QuickTime file type): Best stays the highest resolution")
}
if let p = plan().plan, let q = plan({ _ in }, m3).plan {
    check(q.video?.id == "401" && p.video?.id != q.video?.id, "M3 (plays AV1): Best is 4K AV1")
}
if let p = plan({ _ in }, m3).plan {
    check(!p.notes.contains { $0.contains("can’t play") }, "no playback warning on a Mac that decodes AV1")
} else { check(false, "default plan is ready") }

if let p = plan({ $0.resolution = .tier(.p1080) }).plan {
    check(p.video?.id == "299", "1080p/MP4/M1 → H.264 60 fps (playable on this Mac), got \(p.video?.id ?? "nil")")
}
if let p = plan({ $0.resolution = .tier(.p1080) }, m3).plan {
    check(p.video?.id == "399" || p.video?.id == "299", "1080p/MP4/M3 → a playable stream")
    // AV1 2900 kbps /0.5 = 5800 vs H.264 6100/1.0 = 6100 → H.264 still wins on picture information
    check(p.video?.id == "299", "ranking by picture information per codec")
}
if let p = plan({ $0.resolution = .tier(.p1080); $0.preferPlayableOnThisMac = false }).plan {
    check(p.video?.fps == 60, "60 fps preferred over 30 fps at the same tier")
}
if let p = plan({ $0.resolution = .tier(.p1080); $0.container = .mkv }).plan {
    check(p.audio?.id == "251" || p.audio?.id == "140", "MKV keeps any sound")
    check(p.audioAction == .copy, "MKV never converts")
}
if let p = plan({ $0.preferHDR = true }).plan {
    check(p.video?.id == "701" && p.video?.dynamicRange == .hdr10, "HDR requested → HDR stream")
}
if let p = plan({ $0.resolution = .tier(.p1080); $0.preferHDR = true }).plan {
    check(p.video?.dynamicRange == .sdr && p.notes.contains { $0.contains("HDR isn’t offered") }, "HDR unavailable → SDR with a note")
}

// MARK: Selection — never silently compromise
if case .unsatisfiable(let reason, let alts) = plan({ $0.resolution = .tier(.p4320) }) {
    check(reason.contains("8K"), "8K not offered → explained")
    check(alts.contains { $0.label.contains("4K") }, "nearest tier offered as alternative")
} else { check(false, "8K request must not silently downgrade") }

if case .unsatisfiable(_, let alts) = plan({ $0.resolution = .tier(.p2160); $0.codec = .specific(.avc) }) {
    check(alts.contains { $0.label.contains("H.264 at 1080p") }, "H.264 at 4K impossible → offers H.264 at 1080p")
} else { check(false, "4K H.264 must be unsatisfiable") }

if let p = plan({ $0.codec = .specific(.avc) }).plan {
    check(p.video?.tier == .p1080 && p.notes.contains { $0.contains("up to 1080p") }, "best + H.264 → 1080p with an explicit note")
}

if case .unsatisfiable(let reason, let alts) = plan({ $0.resolution = .tier(.p2160); $0.container = .mov }) {
    check(reason.contains("MOV"), "4K in MOV impossible (AV1/VP9 only) → explained")
    check(alts.contains { $0.choices.container == .mkv }, "offers MKV")
} else { check(false, "4K MOV must not re-encode silently") }

if case .unsatisfiable = plan({ $0.resolution = .tier(.p1080); $0.codec = .specific(.vp9); $0.container = .mov }) { check(true, "") }
else { check(false, "VP9 in MOV is refused") }

// Opus forced into MP4 by manual stream choice → conversion is explicit
if let p = plan({ $0.resolution = .tier(.p1080); $0.manualAudioID = "251" }).plan {
    check(p.audioAction == .convert(to: .aac) && p.notes.contains { $0.contains("converted to AAC") }, "Opus into MP4 → explicit conversion note")
    check(p.size?.isExact == false, "converted size is an estimate")
}

// MARK: Languages
if let p = plan({ $0.language = .language("es") }).plan {
    check(p.audio?.language == "es" && p.audio?.audioCodec == .aac, "Spanish dub, AAC for MP4")
}
if let p = plan({ $0.language = .language("fr") }).plan {
    check(p.audio?.id == "251-2" && p.audioAction == .convert(to: .aac), "French exists only as Opus → converted for MP4, said so")
}
if case .unsatisfiable(let r, let alts) = plan({ $0.language = .language("it") }) {
    check(r.contains("Italian") && alts.count == 5, "Italian unavailable → lists the five real languages")
} else { check(false, "missing language must not fall back silently") }
if let p = plan({ $0.language = .language("it"); $0.fallbackLanguage = "de" }).plan {
    check(p.audio?.language == "de" && p.notes.contains { $0.contains("second choice") }, "fallback language used and stated")
}

// MARK: Audio only
if let p = plan({ $0.kind = .audioOnly }).plan {
    check(p.video == nil && p.audioAction == .copy, "audio only, original → copy")
    check(p.outputExtension == "m4a" || p.outputExtension == "opus", "natural extension")
}
if let p = plan({ $0.kind = .audioOnly; $0.audioOutput = .m4a }).plan {
    check(p.audio?.audioCodec == .aac && p.audioAction == .copy, "M4A prefers the AAC source: no conversion")
}
if let p = plan({ $0.kind = .audioOnly; $0.audioOutput = .mp3 }).plan {
    check(p.audioAction == .convert(to: .mp3) && !p.notes.isEmpty, "MP3 conversion is stated")
}
if let p = plan({ $0.kind = .audioOnly; $0.audioOutput = .flac }).plan {
    check(p.outputExtension == "flac" && p.notes.contains { $0.contains("can’t add quality") }, "FLAC honesty note")
}

// MARK: Video only
if let p = plan({ $0.kind = .videoOnly; $0.resolution = .tier(.p720) }).plan {
    check(p.audio == nil && p.audioAction == nil && p.formatExpression == "298", "video only → one stream")
}

// MARK: Muxed-only site
let simple = FormatCatalogue(SampleMedia.simple)
if let p = plan({ _ in }, m1, simple).plan {
    check(p.video?.id == "hls-1080" && p.audio == nil && p.audioAction == .copy, "muxed source: one stream carries the sound")
    check(p.size?.isExact == false, "size estimated from bitrate")
}
check(simple.languages.isEmpty, "no language info → no language row")
if let p = plan({ $0.kind = .audioOnly }, m1, simple).plan {
    check(p.video == nil && p.audio?.id == "hls-720" && p.notes.contains { $0.contains("keeps only the sound") }, "audio only from combined files: smallest version, said so")
} else { check(false, "audio only must work on sites with combined files only") }

// MARK: Subtitles
if let p = plan({ $0.subtitles = SubtitleChoice(mode: .files) }).plan {
    check(p.subtitles.map(\.language) == ["en"] && p.subtitles.first?.isAutomatic == false, "subtitles default to the sound's language, human first")
}
if let p = plan({ $0.subtitles = SubtitleChoice(mode: .embed, languages: ["fr"]) }).plan {
    check(p.subtitles.isEmpty && p.notes.contains { $0.contains("No subtitles") }, "French only automatic → none unless allowed, stated")
}
if let p = plan({ $0.subtitles = SubtitleChoice(mode: .embed, languages: ["fr"], includeAutomatic: true) }).plan {
    check(p.subtitles.first?.isAutomatic == true, "automatic captions when allowed")
}
if let p = plan({ $0.subtitles = SubtitleChoice(mode: .files, all: true, includeAutomatic: true) }).plan {
    check(p.subtitles.count == 4, "all languages (en, es human; de, fr automatic)")
}

// MARK: Determinism
check(plan() == plan(), "same input → same plan")

// MARK: Plain-English house rules
func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }
var all: [Explanation] = DownloadKind.allCases.map(Explain.kind)
all += ([.best] + ResolutionTier.allCases.map { .tier($0) }).map { Explain.resolution($0, catalogue: cat) }
all += ([.automatic] + VideoCodec.allCases.map { .specific($0) }).flatMap { [Explain.codec($0, playback: m1), Explain.codec($0, playback: m3)] }
all += Container.allCases.map(Explain.container) + AudioOutput.allCases.map(Explain.audioOutput) + SubtitleMode.allCases.map(Explain.subtitles)
all += cat.languages.map(Explain.language) + [Explain.hdr, Explain.automaticSubtitles, Explain.noConversion, Explain.size(nil)]
for e in all {
    check(words(e.summary) <= 25, "summary ≤ 25 words: “\(e.summary)” (\(words(e.summary)))")
    check(e.pros.count <= 3 && e.cons.count <= 3, "≤ 3 pros/cons: \(e.summary)")
}
check(Glossary.terms.count >= 12, "glossary covers the terms")

// MARK: Dependency verification (real yt-dlp 2026.10.26 signed checksums)
let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fixtures")
do {
    let key = try OpenPGP.publicKey(armored: PinnedKeys.ytDlp)
    check(key.fingerprint.map { String(format: "%02x", $0) }.joined() == PinnedKeys.ytDlpFingerprint, "pinned key fingerprint")
    let sums = try Data(contentsOf: fixtures.appendingPathComponent("ytdlp-2026.10.26-SHA2-256SUMS"))
    let sig = try Data(contentsOf: fixtures.appendingPathComponent("ytdlp-2026.10.26-SHA2-256SUMS.sig"))
    do { try OpenPGP.verify(data: sums, signature: sig, key: key); check(true, "") } catch { check(false, "genuine yt-dlp checksums verify: \(error)") }
    var tampered = sums; tampered[10] ^= 0x01
    do { try OpenPGP.verify(data: tampered, signature: sig, key: key); check(false, "tampered checksums must be rejected") }
    catch { check(true, "") }
    var badSig = sig; badSig[badSig.count - 5] ^= 0x40
    do { try OpenPGP.verify(data: sums, signature: badSig, key: key); check(false, "corrupted signature must be rejected") }
    catch { check(true, "") }
} catch { check(false, "fixtures readable: \(error)") }

// MARK: Decoding real engine output (Internet Archive, Wikimedia Commons; scrubbed)
func decodeFixture(_ name: String) -> MediaInfo? {
    guard let d = try? Data(contentsOf: fixtures.appendingPathComponent(name)), case .single(let m)? = try? YtDlpDecoder.decode(d) else { return nil }
    return m
}
if let m = decodeFixture("wikimedia-bigbuckbunny4k.json") {
    check(m.title == "Big Buck Bunny 4K" && m.site == "Wikimedia Commons" && m.duration != nil, "Wikimedia: title, site, duration")
    check(!m.formats.contains { $0.ext == "mpd" }, "manifest without details dropped")
    check(m.formats.first { $0.id == "3" } == nil, "negative bitrate/size format with no codecs dropped")
    let vp9 = m.formats.first { $0.id == "4" }
    check(vp9?.videoCodec == .vp9 && vp9?.audioCodec == .opus && vp9?.fileSizeIsExact == false, "muxed VP9+Opus, approximate size")
    check(m.formats.first { $0.id == "1" }?.hasAudio == false, "acodec none → no sound")
    check(m.formats.first { $0.id == "source" }?.hasUnknownCodec == true, "missing codecs → unknown (to inspect), not none")
    check(m.subtitles.count >= 10 && m.subtitles.allSatisfy { !$0.isAutomatic }, "human subtitles decoded")
    let cat = FormatCatalogue(m)
    check(cat.tiers.contains(.p1080) && cat.tiers.contains(.p2160), "tiers include 1080p and the 4K source")
    if case .unsatisfiable(_, let alts) = FormatSelector.select(cat, { var c = Choices(); c.resolution = .tier(.p1080); return c }(), playback: m1) {
        check(alts.contains { $0.choices.container == .webm || $0.choices.container == .mkv }, "VP9-only 1080p in MP4 → offers WebM/MKV, never re-encodes silently")
    } else { check(false, "VP9 1080p into MP4 must not be ready") }
    if let p = FormatSelector.select(cat, { var c = Choices(); c.resolution = .tier(.p1080); c.container = .webm; return c }(), playback: m1).plan {
        check(p.formatExpression == "4" && p.audio == nil && p.audioAction == .copy, "WebM: the muxed stream, copied")
    } else { check(false, "1080p WebM plan") }
} else { check(false, "Wikimedia fixture decodes") }
if let m = decodeFixture("archive-org-bigbuckbunny.json") {
    check(m.site == "Internet Archive" && m.formats.count == 3, "Archive: three files")
    check(m.formats.allSatisfy { $0.hasUnknownCodec && $0.hasVideo && $0.hasAudio }, "codecs not reported → unknown picture and sound, to be inspected")
} else { check(false, "Archive fixture decodes") }

// MARK: Real YouTube answer (Big Buck Bunny 4K60, via signed-in session; scrubbed)
if let m = decodeFixture("youtube-bigbuckbunny-4k60.json") {
    let cat = FormatCatalogue(m)
    check(m.site == "YouTube" && cat.tiers.first == .p2160, "YouTube: up to 4K")
    check(!m.formats.contains { $0.ext == "mhtml" }, "storyboards dropped")
    if let p = FormatSelector.select(cat, { var c = Choices(); c.resolution = .tier(.p1080); return c }(), playback: m1).plan {
        check(p.video?.hasAudio == false, "picture from a picture-only stream, not the combined HLS one (got \(p.video?.id ?? "-"))")
        check(p.video?.id == "299", "1080p60 H.264 (plays on an M1)")
        check(p.audio?.note?.contains("DRC") != true && p.audio?.audioCodec == .aac, "AAC sound, not the DRC copy")
        check(p.audioAction == .copy, "no conversion")
    } else { check(false, "YouTube 1080p plan") }
    if let p = FormatSelector.select(cat, { var c = Choices(); c.container = .mkv; c.preferPlayableOnThisMac = false; return c }(), playback: m1).plan {
        check(p.video?.id == "315" || p.video?.id == "401", "MKV best: 4K60 stream")
        check(p.audio?.audioCodec != .other, "never the experimental IAMF track by default")
    }
    if let p = FormatSelector.select(cat, { var c = Choices(); c.kind = .audioOnly; return c }(), playback: m1).plan {
        check(p.audio?.audioCodec != .other && p.audio?.note?.contains("DRC") != true, "audio only: a normal, uncompressed-volume track")
    }
} else { check(false, "YouTube fixture decodes") }

// MARK: Error classification (real engine messages)
check(ErrorClassifier.classify(stderr: "ERROR: [youtube] aqz-KE-bpKQ: Sign in to confirm you’re not a bot. This helps protect our community.").kind == .botCheck, "bot check recognised")
check(ErrorClassifier.classify(stderr: "ERROR: [vimeo] 1084537: Got HTTP Error 403 when using impersonate target. If you are using a data center IP or VPN/proxy, your IP may be blocked").kind == .blocked, "403 / blocked IP recognised")
check(ErrorClassifier.classify(stderr: "ERROR: [vimeo] 1084537: Got HTTP Error 403 when using impersonate target. If you are using a data center IP or VPN/proxy, your IP may be blocked").title.contains("network"), "blocked IP explained as your network")
check(ErrorClassifier.classify(stderr: "ERROR: [Rumble] v6: Got HTTP Error 403 caused by Cloudflare anti-bot challenge; Just a moment...").kind == .botCheck, "Cloudflare challenge explained as a human check")
check(ErrorClassifier.classify(stderr: "ERROR: [generic] x: HTTP Error 403: Forbidden").title == "The site refused Digby", "plain 403 explained")
check(ErrorClassifier.classify(stderr: "ERROR: [youtube] x: Private video. Sign in if you've been granted access").kind == .privateMedia, "private video")
check(ErrorClassifier.classify(stderr: "ERROR: Unsupported URL: https://example.com/").kind == .unsupportedSite, "unsupported site")
check(ErrorClassifier.classify(stderr: "ERROR: [generic] Unable to extract title; please report this issue").kind == .outdatedExtractor, "outdated extractor")
check(ErrorClassifier.classify(stderr: "ERROR: unable to download video data: HTTP Error 429: Too Many Requests").retryable, "429 is retryable")
check(!ErrorClassifier.classify(stderr: "ERROR: This video is DRM protected").retryable, "DRM never retried")
check(!Redactor.redact("GET https://x.com/v?sig=SECRET&token=abc Cookie: SID=123").contains("SECRET"), "redactor removes query secrets")
check(!Redactor.redact("Cookie: SID=123abc").contains("123abc"), "redactor removes cookies")

// MARK: Sign-in cookie jar: only YouTube + Google account cookies survive
do {
    let f = FileManager.default.temporaryDirectory.appendingPathComponent("jar-\(UUID().uuidString).txt")
    let lines = ["# Netscape HTTP Cookie File", ".youtube.com\tTRUE\t/\tTRUE\t0\tA\t1", "#HttpOnly_.google.com\tTRUE\t/\tTRUE\t0\tB\t2",
                 "accounts.google.com\tFALSE\t/\tTRUE\t0\tC\t3", "mail.google.com\tFALSE\t/\tTRUE\t0\tD\t4", ".drive.google.com\tTRUE\t/\tTRUE\t0\tE\t5",
                 ".bank.example\tTRUE\t/\tTRUE\t0\tF\t6", "www.youtube.com\tFALSE\t/\tTRUE\t0\tG\t7"]
    try lines.joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
    try SignInStore.restrict(f, to: .youtube)
    let kept = try String(contentsOf: f, encoding: .utf8).split(separator: "\n").compactMap { $0.split(separator: "\t").dropFirst(5).first.map(String.init) }
    check(kept.sorted() == ["A", "B", "C", "G"], "jar keeps YouTube + Google sign-in cookies only (got \(kept))")
    let perms = (try FileManager.default.attributesOfItem(atPath: f.path)[.posixPermissions] as? Int) ?? 0
    check(perms == 0o600, "jar readable only by you")
    try? FileManager.default.removeItem(at: f)
} catch { check(false, "jar test: \(error)") }
check(SignInSite.site(for: URL(string: "https://youtu.be/x")!) == .youtube && SignInSite.site(for: URL(string: "https://music.youtube.com/watch?v=x")!) == .youtube, "YouTube links recognised")
check(SignInSite.site(for: URL(string: "https://notyoutube.com/x")!) != .youtube, "look-alike domains don't get YouTube cookies")
check(SignInSite.site(for: URL(string: "https://www.vimeo.com/123")!)?.rawValue == "vimeo.com", "any site: its domain")
check(SignInSite.site(for: URL(string: "https://www.bbc.co.uk/x")!)?.rawValue == "bbc.co.uk", "two-part country domains kept whole")
check(!SignInSite(rawValue: "vimeo.com").keeps(domain: ".evilvimeo.com") && SignInSite(rawValue: "vimeo.com").keeps(domain: ".player.vimeo.com"),
      "a site's jar keeps only that domain and its subdomains")
if let old = try? JSONDecoder().decode(SignInSettings.self, from: Data(#"{"sites":["youtube",{"browser":{"_0":"brave"}}]}"#.utf8)) {
    check(old.sites[.youtube] == .browser(.brave), "settings saved by 1.0 still load")
} else { check(false, "settings saved by 1.0 still load") }

// MARK: History (SQLite)
do {
    let dbFile = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).sqlite")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("keep-\(UUID().uuidString).mp4")
    try Data("x".utf8).write(to: file)
    do {
        let h = try HistoryStore(file: dbFile)
        var ch = Choices(); ch.resolution = .tier(.p1080)
        h.add(HistoryEntry(id: "a", title: "Mountain 100% wild_cats", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=a")!,
                           date: Date(timeIntervalSince1970: 100), file: file, kind: .videoAndAudio, detail: "1080p", bytes: 10, succeeded: true, choices: ch))
        h.add(HistoryEntry(id: "b", title: "Piano", site: "Bandcamp", url: URL(string: "https://bandcamp.com/b")!,
                           date: Date(timeIntervalSince1970: 200), file: nil, kind: .audioOnly, detail: "FLAC", bytes: 5, succeeded: true))
        h.add(HistoryEntry(id: "c", title: "Private one", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=c")!,
                           date: Date(timeIntervalSince1970: 300), file: nil, kind: .videoAndAudio, detail: "This video is private", bytes: 0, succeeded: false))
        check(h.entries().map(\.id) == ["c", "b", "a"], "newest first")
        check(h.entries(search: "youtube").count == 2 && h.entries(search: "piano").first?.id == "b", "search by site and title")
        check(h.entries(search: "100%").map(\.id) == ["a"] && h.entries(search: "_").map(\.id) == ["a"], "search treats % and _ literally")
        check(h.entries(audioOnly: true).map(\.id) == ["b"] && h.entries(succeeded: false).map(\.id) == ["c"], "filters")
        check(h.entries(search: "Mountain").first?.choices?.resolution == .tier(.p1080), "choices remembered for Download Again")
        h.remove(id: "a")
        check(h.entries().map(\.id) == ["c", "b"] && FileManager.default.fileExists(atPath: file.path), "removing a record keeps the file")
    }
    let reopened = try HistoryStore(file: dbFile)
    check(reopened.entries().count == 2, "history survives reopening")
    try? FileManager.default.removeItem(at: dbFile); try? FileManager.default.removeItem(at: file)
} catch { check(false, "history: \(error)") }

// MARK: Versions, update schedule, recovery policy
check(Version.isNewer("2026.11.04.232659", than: "2026.10.26"), "nightly date newer than stable date")
check(!Version.isNewer("2026.10.26", than: "2026.10.26") && !Version.isNewer("2026.10.9", than: "2026.10.26"), "equal / older dates")
check(Version.isNewer("9.0.10", than: "9.0.2") && Version.isNewer("v2.10.0", than: "2.9.8"), "numeric, not alphabetical")
check(UpdateSchedule.isDue(lastCheck: nil, channel: .stable), "never checked → due")
check(!UpdateSchedule.isDue(lastCheck: Date().addingTimeInterval(-3600), channel: .stable), "stable: not again within a day")
check(UpdateSchedule.isDue(lastCheck: Date().addingTimeInterval(-7 * 3600), channel: .nightly), "nightly: every 6 hours")
func kindFailure(_ k: Failure.Kind) -> Failure { Failure(kind: k, title: "", explanation: "", retryable: true, suggestsEngineUpdate: false, detail: "") }
check(RecoveryPolicy.next(after: kindFailure(.network), attempt: 1, engineUpdateTried: false) == .retry(after: 5, reason: "The connection dropped"), "network: quick retry")
check(RecoveryPolicy.next(after: kindFailure(.rateLimited), attempt: 2, engineUpdateTried: false) == .retry(after: 300, reason: "The site asked Digby to slow down"), "rate limit: back off")
check(RecoveryPolicy.next(after: kindFailure(.outdatedExtractor), attempt: 1, engineUpdateTried: false) == .updateEngineThenRetry, "site changed: update the engine")
check(RecoveryPolicy.next(after: kindFailure(.outdatedExtractor), attempt: 2, engineUpdateTried: true) == .giveUp, "…but only once")
check(RecoveryPolicy.next(after: kindFailure(.network), attempt: RecoveryPolicy.maxAttempts, engineUpdateTried: false) == .giveUp, "never retries forever")
for k in [Failure.Kind.privateMedia, .drm, .geoRestricted, .botCheck, .diskFull, .unavailable] {
    check(RecoveryPolicy.next(after: kindFailure(k), attempt: 1, engineUpdateTried: false) == .giveUp, "no pointless retry for \(k.rawValue)")
}
let report = DiagnosticReport.make(failure: Failure(kind: .blocked, title: "Refused", explanation: "", retryable: true, suggestsEngineUpdate: true,
                                                    detail: "GET https://rr1.googlevideo.com/v?sig=SECRET Cookie: SID=abc123 \(NSHomeDirectory())/x"),
                                   link: URL(string: "https://www.youtube.com/watch?v=PRIVATEID")!, engines: [:], appVersion: "0.1.0")
check(!report.contains("SECRET") && !report.contains("abc123") && !report.contains("PRIVATEID") && !report.contains(NSHomeDirectory()),
      "diagnostic report: no query secrets, cookies, private link or home folder")
check(report.contains("www.youtube.com") && report.contains("blocked"), "report names the site and the problem")

// MARK: Download details (kept after completion) and History upgrade from 1.0
do {
    var ch = Choices(); ch.resolution = .tier(.p1080)
    let p = FormatSelector.select(cat, ch, playback: m1).plan!
    let d = DownloadDetails.make(catalogue: cat, choices: ch, plan: p)
    check(d.offered.first?.resolution == "4K" && d.offered.count == cat.tiers.count, "details: every offered resolution")
    check(d.choices.contains { $0.label == "Resolution" && $0.value == "1080p" }, "details: the choice, in plain words")
    check(d.soundLanguages.first == "English (original)" && d.subtitles.contains("French (automatic)"), "details: languages and subtitles")
    check(d.streams == p.formatExpression && d.verified == nil, "details: streams; not verified yet")

    // A 1.0 database (schema 1) must open, upgrade and keep its rows.
    let f = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString).sqlite")
    var db: OpaquePointer?
    sqlite3_open(f.path, &db)
    sqlite3_exec(db, """
        CREATE TABLE downloads (id TEXT PRIMARY KEY, title TEXT NOT NULL, site TEXT NOT NULL, url TEXT NOT NULL, date REAL NOT NULL,
          file TEXT, kind TEXT NOT NULL, detail TEXT NOT NULL, bytes INTEGER NOT NULL, succeeded INTEGER NOT NULL, thumbnail TEXT, choices TEXT);
        INSERT INTO downloads VALUES ('old','Old one','YouTube','https://youtube.com/x',1,NULL,'videoAndAudio','1080p',5,1,NULL,NULL);
        PRAGMA user_version = 1;
        """, nil, nil, nil)
    sqlite3_close(db)
    let h = try HistoryStore(file: f)
    check(h.entries().map(\.id) == ["old"], "1.0 history upgraded, rows kept")
    h.add(HistoryEntry(id: "new", title: "New", site: "YouTube", url: URL(string: "https://youtube.com/y")!, file: nil, kind: .videoAndAudio,
                       detail: "1080p", bytes: 1, succeeded: true, details: d))
    let again = try HistoryStore(file: f)
    check(again.entries(search: "New").first?.details?.choices == d.choices, "details survive reopening")
    try? FileManager.default.removeItem(at: f)
} catch { check(false, "details/history: \(error)") }

// MARK: Page catcher: which requests are "the video"
check(CaughtStream.classify(URL(string: "https://cdn.example.com/v/master.m3u8?token=1")!) == .stream, "HLS playlist caught")
check(CaughtStream.classify(URL(string: "https://cdn.example.com/v/seg-00042.ts")!) == nil, "segments ignored")
check(CaughtStream.classify(URL(string: "https://cdn.example.com/v/chunk_12.m4s")!) == nil, "fragments ignored")
check(CaughtStream.wholeFile(URL(string: "https://video.fbcdn.net/v/abc.mp4?_nc_cat=1&bytestart=0&byteend=9999&oh=x")!)?.absoluteString
      == "https://video.fbcdn.net/v/abc.mp4?_nc_cat=1&oh=x", "byte-range piece → its whole file (other parameters kept)")
check(CaughtStream.wholeFile(URL(string: "https://a/f.mp4?token=1")!) == nil, "no range markers → unchanged")
check(CaughtStream.classify(URL(string: "https://cdn.example.com/a/film-720.mp4")!) == .file, "whole file caught")
check(CaughtStream.classify(URL(string: "https://example.com/logo.png")!) == nil && CaughtStream.classify(URL(string: "blob:https://x/1")!) == nil, "images and blobs ignored")
let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\nhigh.m3u8\n"
check(CaughtStream.inspectPlaylist(master) == (true, 1080), "master playlist: best resolution read")
let picks = [CaughtStream(url: URL(string: "https://a/f.mp4")!, kind: .file, maxHeight: 1080, bytes: 9),
             CaughtStream(url: URL(string: "https://a/m.m3u8")!, kind: .adaptive, maxHeight: 720, bytes: nil),
             CaughtStream(url: URL(string: "https://a/s.mp3")!, kind: .audio, maxHeight: nil, bytes: 5)]
check(CaughtStream.best(picks)?.kind == .adaptive, "suggests the full adaptive stream first")
check(picks[1].label == "Video stream, up to 720p", "plain label")
check(CaughtStream.best([CaughtStream(url: URL(string: "https://a/r.m3u8")!, kind: .stream), CaughtStream(url: URL(string: "https://a/high.mp4")!, kind: .file, bytes: 9)])?.kind == .file,
      "a whole file beats one quality of a stream")
check(CaughtStream.classify(mimeType: "application/vnd.apple.mpegurl") == .stream && CaughtStream.classify(mimeType: "video/mp4") == .file, "server's media type understood")

check(CaughtPage.cleanTitle("Big Buck Bunny : Free Download, Borrow, and Streaming : Internet Archive", host: "archive.org") == "Big Buck Bunny", "Archive title tidied")
check(CaughtPage.cleanTitle("File:Big Buck Bunny 4K.webm - Wikimedia Commons", host: "commons.wikimedia.org") == "Big Buck Bunny 4K", "Wikimedia title tidied")
check(CaughtPage.cleanTitle("A walk in the hills - with Anna", host: "example.com") == "A walk in the hills - with Anna", "titles that don't end with the site are kept whole")

// MARK: Convert to MP4 / keep the site's file (only when chosen)
if let m = decodeFixture("wikimedia-bigbuckbunny4k.json") {
    let c = FormatCatalogue(m)
    var ch = Choices(); ch.resolution = .tier(.p1080)
    if case .unsatisfiable(_, let alts) = FormatSelector.select(c, ch, playback: m1) {
        check(alts.contains { $0.choices.convertPicture }, "VP9 into MP4: offers Convert to MP4")
        check(alts.contains { $0.choices.container == .webm }, "…and WebM")
    } else { check(false, "VP9 into MP4 is never silent") }
    ch.convertPicture = true
    if let p = FormatSelector.select(c, ch, playback: m1).plan {
        check(p.videoConverted && p.convertsAnything && p.size?.isExact == false, "conversion planned, stated, size estimated")
        check(p.chips(catalogue: c).contains("H.264 (converted from VP9)"), "chip says what happens")
        check(p.notes.contains { $0.contains("re-encodes it as H.264") }, "plain-English note")
    } else { check(false, "convert plan") }
}
let siteMP4 = MediaInfo(id: "b", webpageURL: URL(string: "https://www.bitchute.com/video/x")!, title: "T", site: "bitchute.com", duration: 60,
                        formats: [MediaFormat(id: "0", ext: "mp4", width: 854, height: 480, videoCodecName: "vp9", audioCodecName: "mp4a.40.2", videoBitrate: 800)])
var keep = Choices(); keep.keepSiteFile = true
if let p = FormatSelector.select(FormatCatalogue(siteMP4), keep, playback: m1).plan {
    check(!p.videoConverted && p.notes.contains { $0.contains("Kept exactly as the site provides it") }, "keep the site's MP4: copied untouched, stated")
} else { check(false, "keep site file plan") }
if case .unsatisfiable(_, let alts) = FormatSelector.select(FormatCatalogue(siteMP4), Choices(), playback: m1) {
    check(alts.contains { $0.choices.keepSiteFile }, "site's own MP4 offered as it is")
}

// AV1 fits MP4 but an M1 can't play it: offered as one click, converted only when chosen
if let p = plan({ $0.resolution = .tier(.p2160) }, m1).plan {
    check(p.video?.videoCodec == .av1 && !p.videoConverted && p.suggestions.contains { $0.choices.convertPicture }, "AV1 on M1: convert offered, not forced")
}
if let p = plan({ $0.resolution = .tier(.p2160); $0.convertPicture = true }, m1).plan {
    check(p.videoConverted && !p.notes.contains { $0.hasPrefix("This Mac can’t play AV1 in") }, "AV1 on M1, convert chosen: converted, warning replaced")
}
if let p = plan({ $0.convertPicture = true }, m3).plan { check(!p.videoConverted, "M3 plays AV1: nothing converted even when allowed") }

// MARK: File names
check(FileNamer.sanitize("A/B: C?*<>|\"") == "A–B – C", "unsafe characters replaced")
check(FileNamer.sanitize(String(repeating: "é", count: 300)).utf8.count <= 200, "long names trimmed to fit")
check(FileNamer.render("{title} ({resolution})", media: SampleMedia.simple, plan: nil) == "Morning Fog, Short Film", "empty token leaves no ()")
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digby-name-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data().write(to: dir.appendingPathComponent("Film.mp4"))
    check(FileNamer.unique("Film", ext: "mp4", in: dir).lastPathComponent == "Film (2).mp4", "never overwrites: adds a number")
    try? FileManager.default.removeItem(at: dir)
} catch { check(false, "temp dir") }

// MARK: File-name building blocks
do {
    let d = NameParts(template: "{title} ({resolution})")
    check(d?.parts == [.init(.title), .init(.resolution, .round)], "default template reads as Title + (Quality)")
    check(d?.template == "{title} ({resolution})", "default template round-trips exactly")
    let three = NameParts(parts: [.init(.date), .init(.uploader), .init(.title), .init(.id, .square)], separator: " · ")
    check(three.template == "{date} · {uploader} · {title} [{id}]", "parts build a template with the chosen separator")
    check(NameParts(template: three.template) == three, "built template reads back to the same parts")
    check(NameParts(template: "{uploader}_{title}_[{id}]")?.separator == "_", "underscore names read back")
    check(NameParts(template: "My {title}") == nil, "typed text of your own stays a text template")
    check(NameParts(template: "{title} - {title}") == nil, "a repeated part isn't a building-block name")
    check(NameParts(template: "{title} - {uploader} · {date}") == nil, "mixed separators aren't building blocks")
    check(NameParts.presets.allSatisfy { NameParts(template: $0.parts.template) == $0.parts }, "every preset round-trips")
    var anon = SampleMedia.simple; anon.uploader = nil
    let noUploader = FileNamer.render("{title} - {uploader} - {id}", media: anon, plan: nil)
    check(!noUploader.contains(" - - ") && !noUploader.hasSuffix(" -"), "empty middle part leaves a single separator (\(noUploader))")
    check(!FileNamer.render("{uploader} · {title}", media: anon, plan: nil).hasPrefix("·"), "empty first part leaves no dot")
}

// MARK: Only part of the video
do {
    let cat = FormatCatalogue(SampleMedia.video)   // 12:34
    var ch = Choices(); ch.resolution = .tier(.p1080)
    let whole = FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan
    ch.clip = ClipRange(start: 80, end: 225)
    let part = FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan
    check(part?.clip == ClipRange(start: 80, end: 225), "a part is planned")
    if let w = whole?.size?.bytes, let p = part?.size?.bytes { check(p < w / 4 && p > 0, "a part's size is scaled to its length") }
    check(part?.notes.contains { $0.contains("1:20–3:45") } == true, "the part is said in plain words")
    ch.clip = ClipRange(start: 0, end: 99_999)
    check(FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan?.clip == nil, "the whole length is just the whole video")
    ch.clip = ClipRange(start: 30, end: 30.2)
    check(FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan == nil, "a part under a second isn't offered")
    check(ClipRange(start: 80, end: 3725).fileLabel == "1m20s-1h2m5s", "a part's file label")
}

// MARK: Subtitles on the picture, translated
do {
    let cat = FormatCatalogue(SampleMedia.video)
    var ch = Choices(); ch.resolution = .tier(.p1080); ch.subtitles = SubtitleChoice(mode: .burn, languages: ["en", "es"])
    let p = FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan
    check(p?.burnsSubtitles == true && p?.videoConverted == true, "subtitles on the picture re-encode the picture")
    check(p?.subtitles.count == 1, "one language on the picture")
    ch.container = .webm
    check(FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan == nil, "WebM can't hold a burned picture: offered alternatives instead")
    ch.container = .mp4; ch.subtitles = SubtitleChoice(mode: .embed, languages: ["en"]); ch.subtitles.translateTo = "de"
    let t = FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan
    check(t?.translateTo == "de" && t?.videoConverted == false, "translation planned without touching the picture")
    ch.subtitles.translateTo = "en"
    check(FormatSelector.select(cat, ch, playback: PlaybackEnvironment(decodesAV1: true)).plan?.translateTo == nil, "no translation into the same language")
    check(BurnIn.filter("burn.srt").hasPrefix("subtitles=filename=burn.srt:"), "burn filter uses a plain file name")
}
do {
    let srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nthere\r\n\r\n2\n00:00:03,000 --> 00:00:04,000\n{\\an8}Above\n"
    let cues = SRT.parse(srt)
    check(cues.count == 2 && cues[0].plainText == "Hello there" && cues[1].plainText == "Above", "subtitle cues read, tags removed")
    check(SRT.parse(SRT.write(cues)) == cues, "subtitles written back keep their timing")
}

// MARK: Sorting into folders
do {
    var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 5; c.hour = 12
    let date = Calendar(identifier: .gregorian).date(from: c)!
    check(FolderSorting.none.subfolder(media: SampleMedia.video, date: date) == nil, "no sorting: no subfolder")
    check(FolderSorting.month.subfolder(media: SampleMedia.video, date: date) == "2026-11 November", "month folders sort in order and read well")
    check(FolderSorting.day.subfolder(media: SampleMedia.video, date: date) == "2026-11-05", "day folders")
    check(FolderSorting.site.subfolder(media: SampleMedia.video, date: date) == "YouTube", "site folders")
    check(FolderSorting.channel.subfolder(media: SampleMedia.video, date: date) == "Highland Skies Studio", "channel folders")
    var anon = SampleMedia.simple; anon.uploader = "a/b: c"
    check(FolderSorting.channel.subfolder(media: anon, date: date) == "a–b – c", "channel names made safe for folders")
    anon.uploader = nil
    check(FolderSorting.channel.subfolder(media: anon, date: date) == "Vimeo", "no channel: the site instead")
}

// MARK: Missing pages (the engine says "unable to extract"; the page's own status says 404)
do {
    let extract = ErrorClassifier.classify(stderr: "ERROR: [wikimedia.org] X.webm: Unable to extract video info; please report this issue on https://github.com/yt-dlp/yt-dlp/issues")
    check(extract.kind == .outdatedExtractor, "unable to extract → looks like a site change")
    check(ErrorClassifier.missingPage(status: 404, after: extract)?.kind == .unavailable, "…but a 404 page is a missing page")
    check(ErrorClassifier.missingPage(status: 410, after: extract)?.noPageRoutes == true, "410 counts as missing, marked for no page routes")
    check(ErrorClassifier.missingPage(status: 200, after: extract) == nil, "a page that exists stays a site change")
    let forbidden = ErrorClassifier.classify(stderr: "ERROR: HTTP Error 403: Forbidden")
    check(ErrorClassifier.missingPage(status: 404, after: forbidden) == nil, "other kinds aren't rewritten")
}

// MARK: Live streams
check(YtDlpDecoder.liveStatus(Data(#"{"id":"x","formats":[],"live_status":"is_live"}"#.utf8)) == "is_live", "live status read")
check(YtDlpDecoder.liveStatus(Data(#"{"id":"x","formats":[],"is_live":true}"#.utf8)) == "is_live", "older is_live flag read")
check(YtDlpDecoder.liveStatus(Data(#"{"_type":"playlist","entries":[]}"#.utf8)) == nil, "playlists have no live status")
check(ErrorClassifier.classify(stderr: "ERROR: [youtube] abc: This live event will begin in 3 hours.").title == "This live stream hasn’t started yet", "upcoming stream explained")
check(ErrorClassifier.liveNow().kind == .unavailable, "live now: no pointless retries or engine updates")

// MARK: Engine freshness (network mocked)
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    // Quick yt-dlp check: every 4 h on Stable, 2 h on Nightly; never checked → due.
    check(UpdateSchedule.isExtractorDue(CheckState(), channel: .stable, now: t0), "quick check: never checked → due")
    let ok = CheckState(lastSuccess: t0, lastAttempt: t0, failures: 0)
    check(!UpdateSchedule.isExtractorDue(ok, channel: .stable, now: t0 + 3 * 3600), "quick check: not again within 4 h on Stable")
    check(UpdateSchedule.isExtractorDue(ok, channel: .stable, now: t0 + 4 * 3600), "quick check: due after 4 h on Stable")
    check(UpdateSchedule.isExtractorDue(ok, channel: .nightly, now: t0 + 2 * 3600), "quick check: due after 2 h on Nightly")
    // Backoff after failures: 15 min, 30, 60, 120, then capped at the usual interval.
    check([1, 2, 3, 4, 5, 9].map { UpdateSchedule.backoff(failures: $0, cap: 4 * 3600) } == [900, 1800, 3600, 7200, 14400, 14400], "backoff doubles, capped")
    check(UpdateSchedule.backoff(failures: 0, cap: 4 * 3600) == 0, "no backoff without failures")
    var s = ok
    s.failed(at: t0 + 4 * 3600)
    check(!UpdateSchedule.isExtractorDue(s, channel: .stable, now: t0 + 4 * 3600 + 600), "after a failed check: wait 15 min")
    check(UpdateSchedule.isExtractorDue(s, channel: .stable, now: t0 + 4 * 3600 + 900), "after a failed check: retry at 15 min")
    s.failed(at: t0 + 4 * 3600 + 900)
    check(UpdateSchedule.nextExtractorCheck(s, channel: .stable) == t0 + 4 * 3600 + 900 + 1800, "second failure: 30 min")
    s.succeeded(at: t0 + 5 * 3600)
    check(s.failures == 0 && UpdateSchedule.nextExtractorCheck(s, channel: .stable) == t0 + 9 * 3600, "success resets the backoff")
    s.failed(at: t0); for _ in 0..<40 { s.failed(at: t0) }
    check(UpdateSchedule.nextExtractorCheck(s, channel: .stable) == t0 + 4 * 3600, "many failures: never longer than the usual interval")

    // Which build to install.
    check(EngineChoice.shouldInstall("2026.11.10", over: "2026.10.26", channel: .stable, recoveryNightly: false), "newer stable → install")
    check(!EngineChoice.shouldInstall("2026.10.26", over: "2026.10.26", channel: .stable, recoveryNightly: false), "same stable → nothing")
    check(EngineChoice.shouldInstall("2026.10.26", over: "2026.11.04.232659", channel: .stable, recoveryNightly: false), "switched back to Stable → go back to Stable")
    check(!EngineChoice.shouldInstall("2026.10.26", over: "2026.11.04.232659", channel: .stable, recoveryNightly: true), "recovery nightly kept until Stable catches up")
    check(EngineChoice.shouldInstall("2026.11.04", over: "2026.11.04.232659", channel: .stable, recoveryNightly: true), "Stable of the same day replaces the recovery nightly")
    check(!EngineChoice.shouldInstall("2026.11.04.010101", over: "2026.11.04.232659", channel: .nightly, recoveryNightly: false), "older nightly → nothing")

    // Escalation: Stable straight away, then the Nightly is offered (site changes only); Nightly users stop there.
    check(EngineEscalation.next(after: .outdatedExtractor, userChannel: .stable, tried: []) == .update(.stable), "escalation: Stable first")
    check(EngineEscalation.next(after: .outdatedExtractor, userChannel: .stable, tried: [.stable]) == .offerNightly, "escalation: then offer Nightly")
    check(EngineEscalation.next(after: .jsRuntime, userChannel: .stable, tried: [.stable]) == .offerNightly, "escalation: player puzzle counts as a site change")
    check(EngineEscalation.next(after: .outdatedExtractor, userChannel: .stable, tried: [.stable, .nightly]) == .none, "escalation: stops after Nightly")
    check(EngineEscalation.next(after: .blocked, userChannel: .stable, tried: [.stable]) == .none, "escalation: a blocked network isn't offered Nightly")
    check(EngineEscalation.next(after: .outdatedExtractor, userChannel: .nightly, tried: [.nightly]) == .none, "escalation: Nightly users have nothing further")
}

/// A fake engine store and release server for EngineRecovery.
actor FakeEngines {
    var installed: String?
    var recoveryNightly = false
    var releases: [UpdateChannel: String] = [:]
    var failInstall = false
    var installs: [String] = []
    init(installed: String?, releases: [UpdateChannel: String]) { self.installed = installed; self.releases = releases }
    func latest(_ c: UpdateChannel) throws -> ToolRelease {
        guard let v = releases[c] else { throw DependencyError.network("offline") }
        return ToolRelease(tool: .ytdlp, version: v, archive: URL(string: "https://example.invalid/\(v).zip")!, sha256: "00", source: "test")
    }
    func install(_ r: ToolRelease) throws {
        if failInstall { throw DependencyError.verification("bad signature") }
        installed = r.version; recoveryNightly = false; installs.append(r.version)
    }
    func mark(_ on: Bool) { recoveryNightly = on }
    var engine: EngineRecovery.Engine {
        EngineRecovery.Engine(current: { await self.installed }, recoveryNightly: { await self.recoveryNightly },
                              latest: { try await self.latest($0) }, install: { r, _ in try await self.install(r) },
                              markRecoveryNightly: { await self.mark($0) })
    }
}
do {
    // Stable has a fix: it's installed; nothing is marked as a recovery nightly.
    let a = FakeEngines(installed: "2026.10.26", releases: [.stable: "2026.11.10", .nightly: "2026.11.12.010101"])
    let o1 = await EngineRecovery(engine: await a.engine).updateExtractor(on: .stable, userChannel: .stable) { _ in }
    check(o1.updated && o1.to == "2026.11.10", "recovery: newer Stable installed")
    let aMarked = await a.recoveryNightly
    check(aMarked == false, "recovery: Stable install isn't a recovery nightly")
    // Stable has nothing newer: no install; then the offered Nightly installs and is marked.
    let b = FakeEngines(installed: "2026.10.26", releases: [.stable: "2026.10.26", .nightly: "2026.11.12.010101"])
    let o2 = await EngineRecovery(engine: await b.engine).updateExtractor(on: .stable, userChannel: .stable) { _ in }
    let bInstalls = await b.installs
    check(!o2.updated && bInstalls.isEmpty, "recovery: nothing newer on Stable → nothing installed")
    check(EngineEscalation.next(after: .outdatedExtractor, userChannel: .stable, tried: [.stable]) == .offerNightly, "recovery: so Nightly is offered")
    let o3 = await EngineRecovery(engine: await b.engine).updateExtractor(on: .nightly, userChannel: .stable) { _ in }
    let bNow = await b.installed, bMarked = await b.recoveryNightly
    check(o3.updated && o3.channel == .nightly && bNow == "2026.11.12.010101", "recovery: Nightly installed when chosen")
    check(bMarked, "recovery: Nightly marked so the next Stable check keeps it")
    // A build that fails its checks is never installed; offline says so plainly.
    let c = FakeEngines(installed: "2026.10.26", releases: [.stable: "2026.11.10"])
    await c.setFail()
    let o4 = await EngineRecovery(engine: await c.engine).updateExtractor(on: .stable, userChannel: .stable) { _ in }
    let cNow = await c.installed
    check(!o4.updated && cNow == "2026.10.26" && o4.message.contains("didn’t pass"), "recovery: failed verification keeps the current engine")
    let o5 = await EngineRecovery(engine: await c.engine).updateExtractor(on: .nightly, userChannel: .stable) { _ in }
    check(!o5.updated && o5.message.contains("Couldn’t reach"), "recovery: offline is reported, not a fix")
}
extension FakeEngines { func setFail() { failInstall = true } }

// MARK: Site success (local only)
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let ev = [SiteAttempt(site: "youtube.com", date: t0, succeeded: true, engine: "2026.10.26"),
              SiteAttempt(site: "youtube.com", date: t0 + 1, succeeded: false, failure: .botCheck, engine: "2026.10.26"),
              SiteAttempt(site: "youtube.com", date: t0 + 2, succeeded: false, failure: .outdatedExtractor, engine: "2026.10.26"),
              SiteAttempt(site: "youtube.com", date: t0 + 3, succeeded: false, failure: .outdatedExtractor, engine: "2026.10.26"),
              SiteAttempt(site: "youtube.com", date: t0 + 4, succeeded: true, engine: "2026.11.10"),
              SiteAttempt(site: "archive.org", date: t0, succeeded: true, engine: "2026.10.26")]
    let rows = SiteStats.summarise(ev)
    check(rows.map(\.site) == ["youtube.com", "archive.org"], "stats: busiest site first")
    let y = rows[0]
    check(y.attempts == 5 && y.successes == 2 && abs(y.successRate - 0.4) < 1e-9, "stats: tries, successes, rate")
    check(y.commonFailure == .outdatedExtractor && y.failures[.botCheck] == 1, "stats: most common problem")
    check(y.lastWorkingEngine == "2026.11.10" && y.lastFailingEngine == "2026.10.26", "stats: engine versions")
    check(SiteStats.summarise([]).isEmpty, "stats: empty")
    check(SiteAttempt(site: "x.com", succeeded: true, failure: .network, engine: nil).failure == nil, "stats: a success has no failure kind")
    check(SiteStats.site(for: URL(string: "https://www.youtube.com/watch?v=SECRET123&t=4")!) == "youtube.com", "stats: only the site is kept")
    let report = SiteStats.report(rows, appVersion: "1.2", engines: [.ytdlp: "2026.11.10"], channel: .stable,
                                  lastEngineUpdate: UpdateRecord(date: t0, tool: .ytdlp, from: "2026.10.26", to: "2026.11.10", outcome: "installed"))
    check(report.contains("youtube.com | 5 | 2 | 40% | outdatedExtractor"), "report: one line per site")
    check(report.contains("Last engine update: yt-dlp 2026.10.26 → 2026.11.10"), "report: last engine update")
    check(!report.contains("watch?v") && !report.contains("SECRET"), "report: no links")
    // Store: survives a reopen, skips cancellations, caps its size.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digby-stats-\(UUID().uuidString)")
    let file = dir.appendingPathComponent("site-stats.json")
    let st = SiteStatsStore(file: file)
    st.record(ev[0], now: t0); st.record(SiteAttempt(site: "a.com", succeeded: false, failure: .cancelled, engine: nil), now: t0)
    check(SiteStatsStore(file: file).all() == [ev[0]], "store: saved, cancellations not counted")
    for i in 0..<(SiteStatsStore.maxEvents + 5) { st.record(SiteAttempt(site: "b.com", date: t0 + Double(i), succeeded: true, engine: nil), now: t0) }
    check(st.all().count == SiteStatsStore.maxEvents, "store: capped")
    let later = t0 + SiteStatsStore.maxAge + 10_000
    st.record(SiteAttempt(site: "c.com", date: later, succeeded: true, engine: nil), now: later)
    check(st.all().count == 1, "store: old entries expire")
    st.clear(); check(SiteStatsStore(file: file).all().isEmpty, "store: clear")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: Sites (for "play the page out of sight", asked once per site)
do {
    func key(_ s: String) -> String? { SiteKey.of(URL(string: s)!) }
    check(key("https://www.youtube.com/watch?v=x") == "youtube.com", "site: www dropped")
    check(key("https://astralcodexten.substack.com/p/x") == "substack.com", "site: every Substack author is one site")
    check(key("https://www.bbc.co.uk/iplayer") == "bbc.co.uk", "site: country endings keep three parts")
    check(key("https://news.example.com.au/a") == "example.com.au", "site: com.au")
    check(key("https://rumble.com/v1") == "rumble.com", "site: plain domain")
    check(key("https://x.com/a/status/1") == "x.com", "site: short domain")
    check(key("http://192.168.1.4:8080/v.mp4") == "192.168.1.4", "site: IP address is its own site")
    check(key("https://evil-youtube.com/") == "evil-youtube.com", "site: look-alikes stay separate")
}

// ---- resume after quit: the reopen summary and leftovers of a killed run
do {
    let r = LastSessionReport(items: [
        LastSessionItem(id: "a", name: "A", outcome: .finished),
        LastSessionItem(id: "b", name: "B", outcome: .stopped, reason: "Was downloading", canResume: true),
        LastSessionItem(id: "c", name: "C", outcome: .failed, reason: "The site refused the connection", canResume: true),
        LastSessionItem(id: "d", name: "D", outcome: .cancelled)], noun: "download")
    check(r.headline == "Digby closed before 1 download was done.", "resume: headline (\(r.headline))")
    check(r.tally == "1 finished · 1 stopped · 1 failed · 1 cancelled", "resume: tally (\(r.tally))")
    check(r.resumable.map(\.id) == ["b"], "resume: Resume All leaves failed ones for Try Again")
    check(!LastSessionReport(items: [LastSessionItem(id: "a", name: "A", outcome: .finished)], noun: "download").worthShowing, "resume: nothing undone, no summary")
    check(LastSessionReport(items: [LastSessionItem(id: "a", name: "A", outcome: .failed)], noun: "download").headline == "1 download didn’t finish last time.",
          "resume: failure-only headline")
    let enc = try? JSONEncoder().encode(r.items)
    check(enc.flatMap { try? JSONDecoder().decode([LastSessionItem].self, from: $0) } == r.items, "resume: summary rows survive saving")

    let ps = """
      201     1 /Users/x/Library/Application Support/Digby Video Downloader/Tools/yt-dlp/2026.11.01/yt-dlp
      202   201 /Users/x/Library/Application Support/Digby Video Downloader/Tools/ffmpeg/7.1/ffmpeg
      203     1 /opt/homebrew/bin/yt-dlp
      204     1 /Users/x/Library/Application Support/Digby Video Downloader/Tools-old/yt-dlp
    """
    check(Leftovers.orphanPIDs(psOutput: ps, under: "/Users/x/Library/Application Support/Digby Video Downloader/Tools") == [201],
          "resume: only orphaned engines from Digby's own folder are stopped")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("digby-dl-work-\(UUID().uuidString)")
    let sub = root.appendingPathComponent("2026-11", isDirectory: true)
    let fm = FileManager.default
    for d in [root.appendingPathComponent(".digby-download-gone"), sub.appendingPathComponent(".digby-download-gone2"),
              root.appendingPathComponent(".digby-download-running")] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
    check(Leftovers.removeWork(ids: ["gone", "gone2"], in: [root]) == 2, "resume: removed downloads lose their partial data (also one folder down)")
    check(fm.fileExists(atPath: root.appendingPathComponent(".digby-download-running").path), "resume: a download running now keeps its partial data")
    check(Leftovers.removeWork(ids: [], in: [root]) == 0, "resume: nothing named, nothing removed")
    try? fm.removeItem(at: root)
}

print(failures == 0 ? "✓ all \(passed) checks passed" : "\(failures) failed, \(passed) passed")
exit(failures == 0 ? 0 : 1)
