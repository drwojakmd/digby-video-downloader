import Foundation

/// A plain-English explanation of one choice: a one-line meaning, then what you gain and what you give up.
/// House rules (checked by the tests): summary ≤ 25 words, at most 3 pros and 3 cons, no unexplained jargon.
public struct Explanation: Sendable, Hashable {
    public var summary: String
    public var pros: [String]
    public var cons: [String]
    public init(_ summary: String, pros: [String] = [], cons: [String] = []) {
        self.summary = summary; self.pros = pros; self.cons = cons
    }
}

/// Every explanation the app shows. One place, so the wording can be reviewed as a whole.
public enum Explain {

    // MARK: Download type
    public static func kind(_ k: DownloadKind) -> Explanation {
        switch k {
        case .videoAndAudio:
            return Explanation("A normal video, with picture and sound.",
                               pros: ["What almost everyone wants"], cons: ["The largest of the three"])
        case .videoOnly:
            return Explanation("Just the picture, with no sound track at all.",
                               pros: ["Useful for editing, or footage where the sound doesn’t matter"],
                               cons: ["Plays silently"])
        case .audioOnly:
            return Explanation("Just the sound, saved as an audio file.",
                               pros: ["Much smaller", "Ideal for music, talks and podcasts"], cons: ["No picture"])
        }
    }

    // MARK: Resolution
    /// `bestIs`: what "Best" resolves to on this Mac (lower than the top when the top won't play here).
    public static func resolution(_ choice: ResolutionChoice, catalogue: FormatCatalogue, bestIs: ResolutionTier? = nil) -> Explanation {
        guard case .tier(let t) = choice else {
            let top = catalogue.tiers.first
            if let b = bestIs, let top, b != top {
                return Explanation("The sharpest picture that plays on this Mac (here: \(b.name)). The \(top.name) version would need VLC or IINA; choose \(top.name) to get it anyway.",
                                   pros: ["Opens in QuickTime, Photos, Finder preview and iMovie", "Smaller than the \(top.name) version"],
                                   cons: ["Less detail than the \(top.name) original on big screens"])
            }
            return Explanation("The sharpest picture this video offers that plays on this Mac (here: \(top?.name ?? "the highest")).",
                               pros: ["Nothing is held back", "Opens in the usual Mac apps when saved as MP4 or MOV"], cons: ["Usually the largest file"])
        }
        let top = catalogue.tiers.first
        switch t {
        case .p4320: return Explanation("8K: four times the detail of 4K. Very few screens can show it.",
                                        pros: ["Future-proof archive"], cons: ["Enormous files", "Needs a fast Mac to play smoothly"])
        case .p2160: return Explanation("4K Ultra HD: the sharpest picture on most large TVs and big monitors.",
                                        pros: ["Crisp on big screens", "Good for cropping or zooming in editing"],
                                        cons: ["About 3–4× the size of Full HD", "Little visible benefit on a laptop or phone"])
        case .p1440: return Explanation("Quad HD (1440p): between Full HD and 4K. Common on gaming and creator channels.",
                                        pros: ["Sharper than Full HD on large monitors"], cons: ["Roughly twice the size of Full HD"])
        case .p1080: return Explanation("Full HD (1080p): sharp on laptops, phones and most TVs. The everyday standard.",
                                        pros: ["Looks great on almost any screen", "Reasonable file size"],
                                        cons: top.map { $0 > .p1080 ? ["Less detail than the \($0.name) original on big screens"] : [] } ?? [])
        case .p720: return Explanation("HD (720p): fine on laptops and phones, a little soft on big TVs.",
                                       pros: ["About half the size of Full HD"], cons: ["Small text in screen recordings may be hard to read"])
        case .p480: return Explanation("Standard definition, like DVD. Watchable on a phone; blurry on large screens.",
                                       pros: ["Small files"], cons: ["Visibly soft", "Text and fine detail blur"])
        case .p360: return Explanation("Low resolution: fine in a small window or on a phone, soft anywhere bigger.",
                                       pros: ["Small files, quick to download"], cons: ["Text and faces lose detail"])
        default: return Explanation("Very low resolution. Use only when size matters more than picture.",
                                    pros: ["Tiny files"], cons: ["Very blurry on any modern screen"])
        }
    }

    // MARK: Video format (codec)
    public static func codec(_ choice: CodecChoice, playback: PlaybackEnvironment) -> Explanation {
        guard case .specific(let c) = choice else {
            return Explanation("Digby picks the best-quality format that fits your file type, preferring ones this Mac can play.",
                               pros: ["No need to know the technical details"], cons: [])
        }
        switch c {
        case .avc:
            return Explanation("H.264: the most widely supported video format. Plays on practically anything.",
                               pros: ["Old PCs, TVs, game consoles, editors and every browser", "Easiest to edit"],
                               cons: ["Files are larger for the same picture", "Some sites only offer it up to 1080p"])
        case .hevc:
            return Explanation("HEVC (H.265): a newer format, about half the size of H.264 for the same picture.",
                               pros: ["Plays on all recent Macs, iPhones, iPads and Apple TV"],
                               cons: ["Some older Windows PCs and TVs can’t play it"])
        case .av1:
            return Explanation("AV1: the most efficient format. The best picture for its size, used by YouTube for high resolutions.",
                               pros: ["Smallest files for the quality"],
                               cons: playback.decodesAV1 ? ["Older Macs and iPhones can’t play it in QuickTime"]
                                   : ["This Mac can’t play it in QuickTime or Finder preview (needs M3 or newer); use VLC or IINA"])
        case .vp9:
            return Explanation("VP9: Google’s web format, often what YouTube offers for 1440p and 4K.",
                               pros: ["Plays in every web browser, VLC and IINA", "Often the only source for 4K"],
                               cons: ["QuickTime and Photos can’t play it", "Needs MKV or WebM to stay untouched"])
        case .other:
            return Explanation("A less common format provided by this site.", pros: [], cons: ["May need VLC or IINA to play"])
        }
    }

    // MARK: File type (container)
    public static func container(_ c: Container) -> Explanation {
        switch c {
        case .mp4:
            return Explanation("MP4: the standard video file. Opens on Macs, PCs, phones, TVs and in every editor.",
                               pros: ["Best compatibility"], cons: ["Some sound formats must be converted to fit"])
        case .mkv:
            return Explanation("MKV: a flexible file that holds any picture, sound and subtitle format exactly as downloaded.",
                               pros: ["Nothing is ever converted", "Keeps several sound tracks and subtitles"],
                               cons: ["QuickTime and Photos can’t open it; VLC and IINA can"])
        case .webm:
            return Explanation("WebM: the web’s open format, for VP9 or AV1 video with Opus sound.",
                               pros: ["Plays in every browser", "No conversion for YouTube’s VP9/AV1 streams"],
                               cons: ["Not supported by QuickTime, Photos or many editors"])
        case .mov:
            return Explanation("MOV: Apple’s QuickTime file, preferred by Final Cut Pro and some editing tools.",
                               pros: ["Ideal for Apple editing software"], cons: ["Holds only H.264 or HEVC video"])
        }
    }

    // MARK: Sound
    public static func language(_ l: AudioLanguage) -> Explanation {
        if l.isOriginal {
            return Explanation("The sound as originally recorded, in \(l.name).", pros: ["The real voices and performances"], cons: [])
        }
        return Explanation("A \(l.isDubbed ? "dubbed" : "translated") \(l.name) sound track added by the creator or the site.",
                           pros: ["Hear it in \(l.name)"], cons: ["Voices are not the original performers’"])
    }

    public static func audioOutput(_ o: AudioOutput) -> Explanation {
        switch o {
        case .original:
            return Explanation("Saves the sound exactly as the site provides it. No conversion, no quality loss.",
                               pros: ["Best possible quality", "Fastest"], cons: ["The file type depends on the site (often M4A or Opus)"])
        case .m4a:
            return Explanation("M4A (AAC): Apple’s standard audio file. Plays in Music, on iPhone and almost everywhere.",
                               pros: ["Great quality for its size", "Usually no conversion needed"], cons: [])
        case .mp3:
            return Explanation("MP3: the classic audio file. Plays on absolutely everything, including old car stereos.",
                               pros: ["Universal"], cons: ["Usually means converting, which loses a tiny bit of quality"])
        case .flac:
            return Explanation("FLAC: a lossless file, for music libraries that want a perfect copy of what was downloaded.",
                               pros: ["No further quality loss, ever"], cons: ["Several times larger", "Can’t improve on the source"])
        case .wav:
            return Explanation("WAV: uncompressed sound, mainly for audio and video editing software.",
                               pros: ["Opens in any editor instantly"], cons: ["Very large: about 10 MB per minute"])
        case .opus:
            return Explanation("Opus: a modern, very efficient audio format; often what the site already uses.",
                               pros: ["Smallest files for great sound"], cons: ["Some older devices and car stereos can’t play it"])
        }
    }

    // MARK: Subtitles
    public static func subtitles(_ m: SubtitleMode) -> Explanation {
        switch m {
        case .none: return Explanation("No subtitles are saved.")
        case .embed:
            return Explanation("Subtitles go inside the video file; switch them on or off in your player.",
                               pros: ["One tidy file"], cons: ["Some players and TVs ignore embedded subtitles"])
        case .files:
            return Explanation("Subtitles are saved as separate .srt files next to the video, with the same name.",
                               pros: ["Work with nearly every player", "Easy to edit"], cons: ["More files to keep together"])
        case .burn:
            return Explanation("Subtitles are drawn onto the picture itself, like a foreign film at the cinema.",
                               pros: ["Show on every screen, TV, phone and social site", "Nothing to switch on"],
                               cons: ["Can’t be switched off or changed", "The picture is re-encoded (slower, very slightly softer)", "One language only"])
        }
    }
    public static let automaticSubtitles = Explanation(
        "Automatic captions are made by the site’s speech recognition, not written by a person.",
        pros: ["Available for many videos that have no other subtitles"],
        cons: ["Contain mistakes, especially with names, accents and music"])

    // MARK: Other terms
    public static let hdr = Explanation("HDR (high dynamic range): brighter highlights and richer colour on HDR screens, such as recent MacBook Pros and iPhones.",
                                        pros: ["Stunning on HDR displays"], cons: ["Can look dull or washed out on ordinary screens and in some editors"])
    public static func size(_ s: SizeEstimate?) -> Explanation {
        guard let s else { return Explanation("This site doesn’t say how big the file is, so Digby can’t estimate it in advance.") }
        return s.isExact ? Explanation("The exact file size, as reported by the site.")
                         : Explanation("An estimate from the stream’s bitrate and length. The real file may differ by around 10%.")
    }
    public static let noConversion = Explanation("The picture and sound are copied exactly as the site provides them: no quality is lost.")
}

/// Every term, for the Help → Glossary window.
public enum Glossary {
    public struct Term: Sendable, Hashable, Identifiable {
        public var term: String; public var meaning: String
        public var id: String { term }
    }
    public static let terms: [Term] = [
        .init(term: "Resolution", meaning: "How many dots (pixels) make up the picture. More means sharper, and bigger files. 1080p means 1080 rows of pixels."),
        .init(term: "Codec / video format", meaning: "The method used to squeeze video into a file. H.264, HEVC, AV1 and VP9 are codecs. Newer ones give the same picture in less space, but older devices may not play them."),
        .init(term: "Container / file type", meaning: "The kind of file that holds the picture, sound and subtitles together: MP4, MKV, WebM or MOV. Like a box: what’s inside matters more than the box, but not every box opens everywhere."),
        .init(term: "Remuxing", meaning: "Moving picture and sound into a different file type without changing them. Fast and lossless."),
        .init(term: "Converting / re-encoding", meaning: "Recompressing the picture or sound into another format. Slower, and loses a little quality each time. Digby avoids it unless you choose it."),
        .init(term: "Bitrate", meaning: "How much data per second the video or sound uses. Higher usually means better quality and a bigger file."),
        .init(term: "Frame rate (fps)", meaning: "How many pictures per second. 60 fps looks smoother than 30, especially in games and sport."),
        .init(term: "HDR / SDR", meaning: "HDR videos have brighter highlights and more vivid colour on screens that support it. SDR is the ordinary kind that looks right everywhere."),
        .init(term: "Lossless", meaning: "Stored without throwing away any detail. FLAC is lossless audio. It can’t add quality the source never had."),
        .init(term: "Original vs dubbed audio", meaning: "The original sound track is the one recorded with the video. A dubbed track replaces the voices with another language."),
        .init(term: "Automatic captions", meaning: "Subtitles generated by speech recognition. Handy, but often contain mistakes."),
        .init(term: "Playlist / channel", meaning: "A collection of videos. Digby lets you download all of them, or pick the ones you want."),
        .init(term: "Extraction engine", meaning: "The component that understands each website and finds the video files. Digby uses yt-dlp and keeps it up to date automatically."),
    ]
}
