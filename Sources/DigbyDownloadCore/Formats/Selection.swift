import Foundation

public enum DownloadKind: String, CaseIterable, Sendable, Hashable, Codable {
    case videoAndAudio, videoOnly, audioOnly
    public var label: String {
        switch self { case .videoAndAudio: "Video + Audio"; case .videoOnly: "Video Only"; case .audioOnly: "Audio Only" }
    }
    public var systemImage: String {
        switch self { case .videoAndAudio: "play.rectangle"; case .videoOnly: "film"; case .audioOnly: "waveform" }
    }
}

public enum ResolutionChoice: Sendable, Hashable, Codable {
    case best, tier(ResolutionTier)
}

public enum CodecChoice: Sendable, Hashable, Codable {
    case automatic, specific(VideoCodec)
}

public enum LanguageChoice: Sendable, Hashable, Codable {
    case original, language(String)
}

/// Audio-only output.
public enum AudioOutput: String, CaseIterable, Sendable, Hashable, Codable {
    case original, m4a, mp3, flac, wav, opus
    public var name: String {
        switch self {
        case .original: "Original"; case .m4a: "M4A"; case .mp3: "MP3"; case .flac: "FLAC"; case .wav: "WAV"; case .opus: "Opus"
        }
    }
    public var plainLabel: String {
        switch self {
        case .original: "As it is"; case .m4a: "Apple"; case .mp3: "Plays anywhere"; case .flac: "Lossless"
        case .wav: "Editing"; case .opus: "Smallest"
        }
    }
}

public enum SubtitleMode: String, CaseIterable, Sendable, Hashable, Codable {
    case none, embed, files, burn
    public var label: String {
        switch self { case .none: "None"; case .embed: "Inside the video"; case .files: "Separate files"; case .burn: "On the picture" }
    }
}

/// Only part of the video: from `start` to `end` (seconds). `exact` cuts on the very frame (slower);
/// otherwise the cut lands on the nearest key frame, a few seconds early at most.
public struct ClipRange: Sendable, Hashable, Codable {
    public var start: Double
    public var end: Double
    public var exact: Bool
    public init(start: Double, end: Double, exact: Bool = false) { self.start = start; self.end = end; self.exact = exact }
    public var length: Double { max(0, end - start) }
    /// "1:20–3:45"
    public var label: String { Fmt.duration(start) + "–" + Fmt.duration(end) }
    /// For file names: "1m20s-3m45s".
    public var fileLabel: String {
        func f(_ t: Double) -> String {
            let s = Int(t.rounded(.down)); let h = s / 3600, m = s / 60 % 60, sec = s % 60
            return (h > 0 ? "\(h)h" : "") + (h > 0 || m > 0 ? "\(m)m" : "") + "\(sec)s"
        }
        return f(start) + "-" + f(end)
    }
}

public struct SubtitleChoice: Sendable, Hashable, Codable {
    public var mode: SubtitleMode
    /// Base language codes. Empty with `all == false` means "the audio's language".
    public var languages: [String]
    public var all: Bool
    public var includeAutomatic: Bool
    /// Translate the chosen subtitles into this language on this Mac (needs macOS 15).
    public var translateTo: String? = nil
    public init(mode: SubtitleMode = .none, languages: [String] = [], all: Bool = false, includeAutomatic: Bool = false) {
        self.mode = mode; self.languages = languages; self.all = all; self.includeAutomatic = includeAutomatic
    }
}

/// What the person asked for, in their terms.
public struct Choices: Sendable, Hashable, Codable {
    public var kind: DownloadKind = .videoAndAudio
    public var resolution: ResolutionChoice = .best
    public var codec: CodecChoice = .automatic
    public var container: Container = .mp4
    public var preferHDR: Bool = false
    public var language: LanguageChoice = .original
    public var fallbackLanguage: String? = nil
    public var audioOutput: AudioOutput = .original
    public var subtitles = SubtitleChoice()
    /// For Automatic: among equally good streams, prefer ones this Mac plays in QuickTime.
    public var preferPlayableOnThisMac: Bool = true
    /// Advanced Mode: exact streams chosen by format id.
    public var manualVideoID: String? = nil
    public var manualAudioID: String? = nil
    /// Only when the person chooses it: re-encode a picture the file type can't hold as H.264 (plays everywhere).
    public var convertPicture: Bool = false
    /// Only when the person chooses it: keep the site's own file even if its picture format is unusual for that type
    /// (e.g. VP9 inside the site's MP4). Plays in browsers and VLC, not QuickTime.
    public var keepSiteFile: Bool = false
    /// Only part of the video (nil: all of it). Belongs to one video, so profiles never keep it.
    public var clip: ClipRange? = nil
    public init() {}
}

public enum StreamAction: Sendable, Hashable {
    case copy
    case convert(to: AudioCodec)
}

public struct SizeEstimate: Sendable, Hashable {
    public var bytes: Int64
    public var isExact: Bool
    public init(bytes: Int64, isExact: Bool) { self.bytes = bytes; self.isExact = isExact }
}

/// The result of selection: exactly which streams, what happens to them, and anything that differs
/// from what was asked. Never contains a hidden compromise.
public struct DownloadPlan: Sendable, Hashable {
    public var kind: DownloadKind
    public var video: MediaFormat?
    public var audio: MediaFormat?        // nil when the video stream carries the sound, or video-only
    public var audioAction: StreamAction?
    public var outputExtension: String
    public var container: Container?
    public var size: SizeEstimate?
    public var subtitles: [SubtitleTrack]
    public var subtitleMode: SubtitleMode
    /// Plain-English notes about anything that isn't a straight copy of what was asked.
    public var notes: [String]

    /// The engine's stream selection ("137+140").
    public var formatExpression: String {
        [video?.id, audio?.id].compactMap { $0 }.joined(separator: "+")
    }
    /// The picture is re-encoded as H.264 (only when chosen).
    public var videoConverted: Bool = false
    /// Subtitles drawn onto the picture (needs the picture re-encoded).
    public var burnsSubtitles: Bool { subtitleMode == .burn && !subtitles.isEmpty && kind != .audioOnly }
    /// Translate the first subtitle track into this language on this Mac.
    public var translateTo: String? = nil
    /// Only this part of the video.
    public var clip: ClipRange? = nil
    /// One-click improvements shown with the plan (e.g. "Convert so it plays on this Mac").
    public var suggestions: [Alternative] = []
    public var convertsAnything: Bool {
        if videoConverted { return true }
        if case .convert = audioAction { return true }
        return false
    }
    public var soundFormat: MediaFormat? { audio ?? (video?.hasAudio == true ? video : nil) }
}

public struct Alternative: Sendable, Hashable, Identifiable {
    public var label: String
    public var choices: Choices
    public var id: String { label }
}

public enum SelectionResult: Sendable, Hashable {
    case ready(DownloadPlan)
    /// The request can't be met exactly. Nothing is downloaded until the person picks something.
    case unsatisfiable(reason: String, alternatives: [Alternative])

    public var plan: DownloadPlan? { if case .ready(let p) = self { return p }; return nil }
}

/// Deterministic stream selection: the same catalogue and choices always give the same plan.
public enum FormatSelector {

    public static func select(_ c: FormatCatalogue, _ ch: Choices, playback: PlaybackEnvironment) -> SelectionResult {
        var notes: [String] = []
        var video: MediaFormat?
        var audio: MediaFormat?

        // MARK: picture
        if ch.kind != .audioOnly {
            switch pickVideo(c, ch, playback: playback, notes: &notes) {
            case .success(let v): video = v
            case .failure(let f): return .unsatisfiable(reason: f.reason, alternatives: f.alternatives)
            }
        }

        // MARK: sound
        let usesMuxedSound = ch.kind == .videoAndAudio && video?.hasAudio == true && c.audio.isEmpty
        if (ch.kind == .videoAndAudio && !usesMuxedSound) || ch.kind == .audioOnly {
            switch pickAudio(c, ch, notes: &notes) {
            case .success(let a): audio = a
            case .failure(let f): return .unsatisfiable(reason: f.reason, alternatives: f.alternatives)
            }
        }

        // MARK: what happens to the sound
        var action: StreamAction?
        var ext: String
        var container: Container?
        switch ch.kind {
        case .videoAndAudio, .videoOnly:
            container = ch.container
            ext = ch.container.rawValue
            if let sound = audio ?? (usesMuxedSound ? video : nil), let codec = sound.audioCodec, ch.kind == .videoAndAudio {
                if ch.container.holds(codec) { action = .copy }
                else {
                    action = .convert(to: ch.container.fallbackAudio)
                    notes.append("The sound is \(codec.name), which \(ch.container.name) players often can’t play, so it will be converted to \(ch.container.fallbackAudio.name) at high quality. Choose MKV to keep it untouched.")
                }
            }
        case .audioOnly:
            let codec = audio?.audioCodec ?? .other
            (action, ext) = audioOutputAction(codec, ch.audioOutput, notes: &notes)
        }

        var subs = pickSubtitles(c, ch, audioLanguage: (audio ?? video)?.language)
        if ch.subtitles.mode != .none && subs.isEmpty {
            notes.append("No subtitles in the chosen languages are available for this video.")
        }
        let burning = ch.subtitles.mode == .burn && ch.kind != .audioOnly && !subs.isEmpty
        if burning {
            if container == .webm {
                return .unsatisfiable(reason: "Subtitles on the picture need the picture re-encoded as H.264, which WebM can’t hold.",
                                      alternatives: [Alternative(label: "Use MP4", choices: with(ch) { $0.container = .mp4 }),
                                                     Alternative(label: "Keep subtitles separate (WebM)", choices: with(ch) { $0.subtitles.mode = .files })])
            }
            subs = [subs[0]]      // one language on the picture
        }
        var translateTo: String? = nil
        if let to = ch.subtitles.translateTo, ch.subtitles.mode != .none, ch.kind != .audioOnly {
            if let first = subs.first {
                if Languages.base(first.language) == Languages.base(to) {
                    notes.append("\(Languages.name(to)) subtitles come from the site, so nothing needs translating.")
                } else {
                    translateTo = Languages.base(to)
                    notes.append("The \(Languages.name(Languages.base(first.language))) subtitles are translated into \(Languages.name(Languages.base(to))) on this Mac by macOS. Nothing is sent anywhere; machine translation can get names, jokes and slang wrong.")
                }
            }
        }

        // Picture: copied, unless the file type can't hold it and the person chose to convert or keep the site's file.
        var videoConverted = false
        var suggestions: [Alternative] = []
        if let v = video, let codec = v.videoCodec, let k = container, ch.kind != .audioOnly, k == .mp4 || k == .mov,
           k.holds(codec), !playback.playsInQuickTime(codec, in: k) {
            // Fits the file type, but this Mac can't play it: convert only if asked; otherwise offer it in one click.
            if ch.convertPicture {
                videoConverted = true
                notes.removeAll { $0.hasPrefix("This Mac can’t play") }
                notes.append("This Mac can’t play \(codec.name), so Digby re-encodes the picture as H.264 at high quality. This takes about as long as the video, and the result is very slightly softer than the original.")
            } else {
                suggestions.append(Alternative(label: "Convert to H.264 so it plays on this Mac", choices: with(ch) { $0.convertPicture = true }))
            }
        }
        if burning {
            videoConverted = true
            let lang = Languages.name(Languages.base(translateTo ?? subs[0].language))
            notes.append("\(lang) subtitles are drawn onto the picture: always visible on every screen and app, but they can’t be switched off. The picture is re-encoded as H.264 at high quality, which takes about as long as the video.")
        } else if let v = video, let codec = v.videoCodec, let k = container, ch.kind != .audioOnly, !k.holds(codec) {
            if ch.convertPicture {
                videoConverted = true
                notes.append("The picture is \(codec == .other ? "in an unusual format" : codec.name), which most \(k.name) players can’t play, so Digby re-encodes it as H.264 at high quality. This takes about as long as the video, and the result is very slightly softer than the original.")
            } else if ch.keepSiteFile {
                notes.append("Kept exactly as the site provides it: \(codec == .other ? "an unusual" : codec.name) picture inside \(k.name). It plays in web browsers, VLC and IINA, but not in QuickTime or Photos.")
            }
        }
        var plan = DownloadPlan(kind: ch.kind, video: video, audio: audio, audioAction: action, outputExtension: ext,
                                container: container,
                                size: estimate(video: video, audio: audio, action: action, duration: c.media.duration),
                                subtitles: subs, subtitleMode: ch.subtitles.mode, notes: notes)
        plan.videoConverted = videoConverted
        plan.suggestions = suggestions
        plan.translateTo = translateTo
        if videoConverted, let v = video, let w = v.width, let h = v.height, let d = c.media.duration {
            // High-quality H.264 (CRF 18) needs roughly 0.085 bits per pixel per frame; sound as planned.
            let videoBytes = Double(w * h) * (v.fps ?? 30) * 0.085 / 8 * d
            let soundBytes = Double(plan.size?.bytes ?? 0) - Double(v.fileSize ?? 0)
            plan.size = SizeEstimate(bytes: Int64(videoBytes + max(0, soundBytes)), isExact: false)
        } else if videoConverted { plan.size?.isExact = false }
        // Only part of the video.
        if var clip = ch.clip {
            let d = c.media.duration
            clip.start = max(0, clip.start)
            if let d { clip.end = min(clip.end, d) }
            if clip.length < 1 {
                return .unsatisfiable(reason: "The part to keep is shorter than a second.",
                                      alternatives: [Alternative(label: "Download the whole video", choices: with(ch) { $0.clip = nil })])
            }
            if let d, clip.start <= 0.5, clip.end >= d - 0.5 {
                // That's the whole video.
            } else {
                plan.clip = clip
                if let d, d > 0, let s = plan.size { plan.size = SizeEstimate(bytes: Int64(Double(s.bytes) * clip.length / d), isExact: false) }
                notes.append(clip.exact
                    ? "Only \(clip.label) (\(Fmt.duration(clip.length))) is downloaded, cut on the exact frames. Cutting exactly re-encodes the picture of that part, so it takes a little longer."
                    : "Only \(clip.label) (\(Fmt.duration(clip.length))) is downloaded. The cut lands on the nearest key frame, so it may begin a few seconds before \(Fmt.duration(clip.start)).")
                plan.notes = notes
            }
        }
        return .ready(plan)
    }

    // MARK: - Video

    struct Failure: Error { var reason: String; var alternatives: [Alternative] }

    /// The highest resolution with a picture format this Mac plays in QuickTime in the chosen file type, when that
    /// matters (MP4/MOV, playable preferred, nothing re-encoded). Nil when it doesn't apply or nothing plays.
    public static func bestPlayableTier(_ c: FormatCatalogue, _ ch: Choices, playback: PlaybackEnvironment) -> ResolutionTier? {
        guard ch.preferPlayableOnThisMac, ch.container == .mp4 || ch.container == .mov, !ch.convertPicture, !ch.keepSiteFile,
              ch.subtitles.mode != .burn, ch.manualVideoID == nil, !ch.preferHDR else { return nil }   // asking for HDR outranks playability
        return c.tiers.first { t in c.codecs(at: t).contains { ch.container.holds($0) && playback.playsInQuickTime($0, in: ch.container) } }
    }
    /// What "Best" resolves to for these choices on this Mac.
    public static func bestTier(_ c: FormatCatalogue, _ ch: Choices, playback: PlaybackEnvironment) -> ResolutionTier? {
        if case .automatic = ch.codec, let t = bestPlayableTier(c, ch, playback: playback) { return t }
        return c.tiers.first
    }

    static func pickVideo(_ c: FormatCatalogue, _ ch: Choices, playback: PlaybackEnvironment, notes: inout [String]) -> Result<MediaFormat, Failure> {
        if let id = ch.manualVideoID {
            guard let f = c.video.first(where: { $0.id == id }) else {
                return .failure(Failure(reason: "The stream you picked (\(id)) is no longer offered.", alternatives: []))
            }
            if let codec = f.videoCodec, ch.kind != .audioOnly, !ch.container.holds(codec) {
                return .failure(containerFailure(codec: codec, ch))
            }
            return .success(f)
        }
        guard let top = c.tiers.first else {
            return .failure(Failure(reason: "This source has no video, only sound.", alternatives: [with(ch) { $0.kind = .audioOnly }].map { Alternative(label: "Download the sound only", choices: $0) }))
        }

        // Which tier?
        var tier: ResolutionTier
        switch ch.resolution {
        case .tier(let t):
            guard c.tiers.contains(t) else {
                let alts = nearest(c.tiers, to: t).map { tt in Alternative(label: "Use \(tt.name)", choices: with(ch) { $0.resolution = .tier(tt) }) }
                return .failure(Failure(reason: "\(t.name) isn’t offered for this video.", alternatives: alts))
            }
            tier = t
        case .best:
            tier = top
            // "Best" means the sharpest picture that plays on this Mac (QuickTime, Photos, Finder preview), when the
            // file type is one those apps open. Higher tiers stay one click away and are named in the note.
            if case .automatic = ch.codec, let playable = bestPlayableTier(c, ch, playback: playback), playable != top {
                tier = playable
                let topCodecs = c.codecs(at: top).map(\.name).joined(separator: " or ")
                notes.append("Best that plays on this Mac: \(playable.name). \(top.name) comes only as \(topCodecs), which QuickTime on this Mac can’t play; choose \(top.name) to get it anyway (plays in VLC or IINA).")
            }
            if case .specific(let codec) = ch.codec, !c.codecs(at: top).contains(codec) {
                guard let best = c.tiers.first(where: { c.codecs(at: $0).contains(codec) }) else {
                    return .failure(Failure(reason: "\(codec.name) isn’t offered for this video.",
                                            alternatives: c.codecs(at: top).filter { ch.container.holds($0) }.map { v in
                                                Alternative(label: "Use \(v.name)", choices: with(ch) { $0.codec = .specific(v) }) }
                                                + [Alternative(label: "Let Digby choose", choices: with(ch) { $0.codec = .automatic })]))
                }
                tier = best
                notes.append("\(codec.name) is offered up to \(best.name); the highest resolution, \(top.name), comes only as \(c.codecs(at: top).map(\.name).joined(separator: " or ")).")
            }
        }

        var pool = c.streams(at: tier)
        switch ch.codec {
        case .specific(let codec):
            pool = pool.filter { $0.videoCodec == codec }
            if pool.isEmpty {
                let here = c.codecs(at: tier)
                let alts = here.filter { ch.container.holds($0) }.map { v in Alternative(label: "Use \(v.name)", choices: with(ch) { $0.codec = .specific(v) }) }
                    + c.tiers.filter { c.codecs(at: $0).contains(codec) }.prefix(2).map { t in
                        Alternative(label: "\(codec.name) at \(t.name)", choices: with(ch) { $0.resolution = .tier(t) }) }
                return .failure(Failure(reason: "At \(tier.name) this video comes only as \(here.map(\.name).joined(separator: " or ")), not \(codec.name).", alternatives: alts))
            }
            if !ch.container.holds(codec) && !ch.convertPicture && ch.subtitles.mode != .burn && !(ch.keepSiteFile && pool.contains { $0.ext == ch.container.rawValue }) {
                return .failure(containerFailure(codec: codec, ch, siteExts: Set(pool.map(\.ext))))
            }
        case .automatic:
            var fitting = pool.filter { $0.videoCodec.map(ch.container.holds) ?? false }
            if fitting.isEmpty && ch.keepSiteFile { fitting = pool.filter { $0.ext == ch.container.rawValue } }
            if fitting.isEmpty && (ch.convertPicture || ch.subtitles.mode == .burn) { fitting = pool }
            if fitting.isEmpty {
                let codecs = Set(pool.compactMap(\.videoCodec))
                let alts = Container.allCases.filter { k in codecs.contains(where: k.holds) && k != ch.container }.map { k in
                    Alternative(label: "Save as \(k.name)", choices: with(ch) { $0.container = k }) }
                    + conversionAlternatives(ch, siteExts: Set(pool.map(\.ext)))
                return .failure(Failure(reason: "At \(tier.name) this video comes as \(codecs.map(\.name).sorted().joined(separator: " or ")), which \(ch.container.name) can’t hold without re-encoding the picture.", alternatives: alts))
            }
            pool = fitting
            if ch.preferPlayableOnThisMac, ch.container == .mp4 || ch.container == .mov {
                let playable = pool.filter { $0.videoCodec.map { playback.playsInQuickTime($0, in: ch.container) } ?? false }
                if !playable.isEmpty { pool = playable }
            }
        }

        // When separate sound exists, take the picture from a picture-only stream: combined (often HLS) versions
        // report inflated bitrates and carry weaker sound that would shadow the better separate track.
        if !c.audio.isEmpty || ch.kind == .videoOnly {
            let pure = pool.filter { !$0.hasAudio }
            if !pure.isEmpty { pool = pure }
        }
        let hdr = pool.filter { $0.dynamicRange.isHDR }, sdr = pool.filter { !$0.dynamicRange.isHDR }
        if ch.preferHDR {
            if !hdr.isEmpty { pool = hdr } else { notes.append("HDR isn’t offered at \(tier.name) in this format, so you’ll get the standard (SDR) version.") }
        } else if !sdr.isEmpty { pool = sdr }

        let best = pool.sorted(by: videoOrder).first!
        // Say so when the result won't open in QuickTime / Finder preview on this Mac.
        if let codec = best.videoCodec, ch.container == .mp4 || ch.container == .mov, !playback.playsInQuickTime(codec, in: ch.container) {
            let playableTier = c.tiers.first { t in c.codecs(at: t).contains { playback.playsInQuickTime($0, in: ch.container) } }
            var note = "This Mac can’t play \(codec.name) in QuickTime or Finder preview\(codec == .av1 ? " (that needs an M3 or newer)" : ""); it plays in VLC or IINA."
            if let t = playableTier { note += " Choose \(t.name) for a version that plays everywhere." }
            notes.append(note)
        }
        return .success(best)
    }

    /// Higher frame rate first, then more picture information per codec, then a known size, then id (stable).
    static func videoOrder(_ a: MediaFormat, _ b: MediaFormat) -> Bool {
        let fa = (a.fps ?? 30).rounded(), fb = (b.fps ?? 30).rounded()
        if fa != fb { return fa > fb }
        let ea = (a.videoBitrate ?? a.totalBitrate ?? 0) / (a.videoCodec?.efficiency ?? 1)
        let eb = (b.videoBitrate ?? b.totalBitrate ?? 0) / (b.videoCodec?.efficiency ?? 1)
        if ea != eb { return ea > eb }
        if (a.fileSize != nil) != (b.fileSize != nil) { return a.fileSize != nil }
        return a.id < b.id
    }

    static func containerFailure(codec: VideoCodec, _ ch: Choices, siteExts: Set<String> = []) -> Failure {
        let others = Container.allCases.filter { $0 != ch.container && $0.holds(codec) }
        return Failure(reason: "\(ch.container.name) can’t hold \(codec.name) video without re-encoding the picture, which would lose quality.",
                       alternatives: others.map { k in Alternative(label: "Save as \(k.name)", choices: with(ch) { $0.container = k }) }
                       + [Alternative(label: "Let Digby choose the format", choices: with(ch) { $0.codec = .automatic })]
                       + conversionAlternatives(ch, siteExts: siteExts))
    }

    /// The two explicit ways past a file type that can't hold the picture: convert it, or keep the site's own file.
    static func conversionAlternatives(_ ch: Choices, siteExts: Set<String>) -> [Alternative] {
        var a: [Alternative] = []
        if ch.container == .mp4 || ch.container == .mov {
            a.append(Alternative(label: "Convert to \(ch.container.name) (plays everywhere, takes longer)",
                                 choices: with(ch) { $0.convertPicture = true; $0.keepSiteFile = false }))
        }
        if siteExts.contains(ch.container.rawValue) {
            a.append(Alternative(label: "Keep the site’s \(ch.container.name) as it is",
                                 choices: with(ch) { $0.keepSiteFile = true; $0.convertPicture = false }))
        }
        return a
    }

    // MARK: - Audio

    static func pickAudio(_ c: FormatCatalogue, _ ch: Choices, notes: inout [String]) -> Result<MediaFormat, Failure> {
        if let id = ch.manualAudioID {
            guard let f = c.audio.first(where: { $0.id == id }) else {
                return .failure(Failure(reason: "The sound stream you picked (\(id)) is no longer offered.", alternatives: []))
            }
            return .success(f)
        }
        // Audio only from a site that only offers combined files: take the best sound, smallest picture.
        if c.audio.isEmpty, ch.kind == .audioOnly {
            let muxed = c.video.filter(\.hasAudio)
            if let best = muxed.sorted(by: { a, b in
                if (a.audioBitrate ?? 0) != (b.audioBitrate ?? 0) { return (a.audioBitrate ?? 0) > (b.audioBitrate ?? 0) }
                let sa = a.fileSize ?? Int64.max, sb = b.fileSize ?? Int64.max
                return sa != sb ? sa < sb : (a.height ?? 0) < (b.height ?? 0)
            }).first {
                notes.append("This site has no separate sound file, so Digby downloads its smallest video version and keeps only the sound.")
                return .success(best)
            }
        }
        guard !c.audio.isEmpty else {
            return .failure(Failure(reason: "This source offers no separate sound stream.",
                                    alternatives: ch.kind == .audioOnly ? [] : [Alternative(label: "Download the video only", choices: with(ch) { $0.kind = .videoOnly })]))
        }
        var pool: [MediaFormat]
        let hasLanguageInfo = c.audio.contains { $0.language != nil }
        switch ch.language {
        case .original:
            let orig = c.originalLanguage?.code
            pool = c.audio.filter { $0.audioRole == .original || (orig != nil && $0.language.map(Languages.base) == orig && $0.audioRole != .dubbed) }
            if pool.isEmpty { pool = hasLanguageInfo ? c.audio.filter { $0.audioRole != .dubbed } : c.audio }
            if pool.isEmpty { pool = c.audio }
        case .language(let code):
            pool = c.audio.filter { $0.language.map(Languages.base) == code }
            if pool.isEmpty, let fb = ch.fallbackLanguage {
                pool = c.audio.filter { $0.language.map(Languages.base) == fb }
                if !pool.isEmpty { notes.append("\(Languages.name(code)) sound isn’t offered, so you’ll get \(Languages.name(fb)), your second choice.") }
            }
            if pool.isEmpty {
                let alts = c.languages.map { l in Alternative(label: l.name + (l.isOriginal ? " (original)" : ""),
                                                              choices: with(ch) { $0.language = l.isOriginal ? .original : .language(l.code) }) }
                return .failure(Failure(reason: "This video has no \(Languages.name(code)) sound.", alternatives: alts))
            }
        }

        let preferred: Set<AudioCodec>
        switch ch.kind {
        case .audioOnly:
            switch ch.audioOutput {
            case .m4a: preferred = [.aac]
            case .opus: preferred = [.opus]
            case .mp3: preferred = [.mp3]
            default: preferred = []
            }
        default:
            preferred = Set(AudioCodec.allCases.filter(ch.container.holds))
        }
        // Avoid, unless nothing else exists: volume-compressed "DRC" copies and codecs few players handle (e.g. IAMF).
        func odd(_ f: MediaFormat) -> Int {
            (f.note?.uppercased().contains("DRC") == true ? 1 : 0) + (f.audioCodec == .other ? 2 : 0)
        }
        let best = pool.sorted { a, b in
            let pa = a.audioCodec.map(preferred.contains) ?? false, pb = b.audioCodec.map(preferred.contains) ?? false
            if pa != pb { return pa }
            if odd(a) != odd(b) { return odd(a) < odd(b) }
            let ra = a.audioRole == .descriptive ? 1 : 0, rb = b.audioRole == .descriptive ? 1 : 0
            if ra != rb { return ra < rb }
            if (a.audioBitrate ?? 0) != (b.audioBitrate ?? 0) { return (a.audioBitrate ?? 0) > (b.audioBitrate ?? 0) }
            return a.id < b.id
        }.first!
        return .success(best)
    }

    static func audioOutputAction(_ codec: AudioCodec, _ out: AudioOutput, notes: inout [String]) -> (StreamAction, String) {
        func natural(_ c: AudioCodec) -> String {
            switch c { case .aac: "m4a"; case .opus: "opus"; case .vorbis: "ogg"; case .mp3: "mp3"; case .flac: "flac"; default: "mka" }
        }
        switch out {
        case .original: return (.copy, natural(codec))
        case .m4a:
            if codec == .aac { return (.copy, "m4a") }
            notes.append("The source sound is \(codec.name); it will be converted to AAC at high quality. Choose “As it is” to keep the original untouched.")
            return (.convert(to: .aac), "m4a")
        case .opus:
            if codec == .opus { return (.copy, "opus") }
            notes.append("The source sound is \(codec.name); it will be converted to Opus.")
            return (.convert(to: .opus), "opus")
        case .mp3:
            if codec == .mp3 { return (.copy, "mp3") }
            notes.append("Converting \(codec.name) to MP3 loses a little quality (most people can’t hear it at 320 kbps).")
            return (.convert(to: .mp3), "mp3")
        case .flac:
            notes.append("FLAC keeps every bit of the downloaded sound but can’t add quality the source doesn’t have: the file is larger and sounds the same as “As it is”.")
            return (.convert(to: .flac), "flac")
        case .wav:
            notes.append("WAV is uncompressed: about 10 MB per minute, and it sounds the same as “As it is”. Useful for editing software.")
            return (.convert(to: .other), "wav")
        }
    }

    // MARK: - Subtitles

    static func pickSubtitles(_ c: FormatCatalogue, _ ch: Choices, audioLanguage: String?) -> [SubtitleTrack] {
        let s = ch.subtitles
        guard s.mode != .none else { return [] }
        var wanted: [String]
        if s.all { wanted = Array(Set((c.humanSubtitles + (s.includeAutomatic ? c.automaticSubtitles : [])).map { Languages.base($0.language) })).sorted() }
        else if !s.languages.isEmpty { wanted = s.languages }
        else { wanted = [audioLanguage.map(Languages.base) ?? c.originalLanguage?.code ?? "en"] }
        return wanted.compactMap { code in
            c.humanSubtitles.first { Languages.base($0.language) == code }
                ?? (s.includeAutomatic ? c.automaticSubtitles.first { Languages.base($0.language) == code } : nil)
        }
    }

    // MARK: - Size

    static func estimate(video: MediaFormat?, audio: MediaFormat?, action: StreamAction?, duration: Double?) -> SizeEstimate? {
        var total: Int64 = 0, exact = true
        func add(_ f: MediaFormat, bitrate: Double?) -> Bool {
            if let s = f.fileSize { total += s; exact = exact && f.fileSizeIsExact; return true }
            if let b = bitrate, let d = duration { total += Int64(b * 1000 / 8 * d); exact = false; return true }
            return false
        }
        if let v = video, !add(v, bitrate: audio == nil ? v.totalBitrate : v.videoBitrate ?? v.totalBitrate) { return nil }
        if let a = audio {
            if case .convert(let to) = action, let d = duration {
                let kbps: Double = switch to { case .aac: 256; case .opus: 160; case .mp3: 320; case .flac: 900; default: 1411 }
                total += Int64(kbps * 1000 / 8 * d); exact = false
            } else if !add(a, bitrate: a.audioBitrate) { return nil }
        }
        return total > 0 ? SizeEstimate(bytes: total, isExact: exact) : nil
    }

    // MARK: - Helpers

    static func nearest(_ tiers: [ResolutionTier], to t: ResolutionTier) -> [ResolutionTier] {
        let below = tiers.filter { $0 < t }.max(), above = tiers.filter { $0 > t }.min()
        return [below, above].compactMap { $0 }
    }
    static func with(_ c: Choices, _ change: (inout Choices) -> Void) -> Choices { var x = c; change(&x); return x }
}
