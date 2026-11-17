import Foundation

/// FFmpeg step: copies the downloaded streams into the chosen file type. Picture is always copied;
/// sound is copied unless the plan says it must be converted; subtitles are embedded in the format
/// each file type supports.
struct PostProcessor: Sendable {
    var ffmpeg: URL

    func make(_ output: URL, from input: URL, subtitles: [(file: URL, language: String, automatic: Bool)], burn: URL? = nil, request req: DownloadRequest,
              cancel: CancelToken, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let p = req.plan
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats", "-i", input.path]
        for s in subtitles { args += ["-i", s.file.path] }

        switch p.kind {
        case .videoAndAudio:
            args += ["-map", "0:v:0", "-map", "0:a:0?"]
        case .videoOnly:
            args += ["-map", "0:v:0", "-an"]
        case .audioOnly:
            args += ["-map", "0:a:0", "-vn"]
        }
        for i in subtitles.indices { args += ["-map", "\(i + 1):0"] }

        if p.kind != .audioOnly {
            // Re-encoding only when chosen: high-quality H.264 (visually transparent at CRF 18), 8-bit for compatibility.
            args += p.videoConverted ? ["-c:v", "libx264", "-crf", "18", "-preset", "faster", "-profile:v", "high", "-pix_fmt", "yuv420p"]
                                     : ["-c:v", "copy"]
            if let burn {
                // Run from the work folder so the filter only sees a plain file name (no path to escape).
                args += ["-vf", Self.burnFilter(burn.lastPathComponent)]
            }
        }
        if p.kind != .videoOnly {
            switch p.audioAction {
            case .convert(let to)?: args += Self.encoder(to, outputExtension: p.outputExtension)
            default: args += ["-c:a", "copy"]
            }
        }
        if !subtitles.isEmpty {
            let codec: String = switch p.container { case .mp4?, .mov?: "mov_text"; case .webm?: "webvtt"; default: "srt" }
            args += ["-c:s", codec]
            for (i, s) in subtitles.enumerated() {
                args += ["-metadata:s:s:\(i)", "language=\(Self.iso639_2(s.language))"]
                if s.automatic { args += ["-metadata:s:s:\(i)", "title=\(Languages.name(s.language)) (automatic)"] }
            }
        }
        args += ["-map_metadata", "0"]
        args += req.embedChapters && p.kind != .audioOnly ? ["-map_chapters", "0"] : ["-map_chapters", "-1"]
        if ["mp4", "mov", "m4a"].contains(p.outputExtension) { args += ["-movflags", "+faststart"] }
        if p.outputExtension == "opus" || p.outputExtension == "ogg" { args += ["-f", "ogg"] }
        args += [output.path]

        let duration = req.plan.clip?.length ?? req.media.duration
        let r = try await ProcessRunner.run(ffmpeg, args, currentDirectory: burn?.deletingLastPathComponent(), started: { cancel.attach($0) }) { line, isError in
            guard !isError, line.hasPrefix("out_time_us="), let d = duration, let us = Double(line.dropFirst(12)) else { return }
            progress(min(1, us / 1_000_000 / d))
        }
        if r.cancelled || cancel.isCancelled { throw ErrorClassifier.cancelled() }
        guard r.succeeded else {
            Log.write("ffmpeg failed: \(r.stderr.suffix(800))")
            throw Failure(kind: .unsupportedFormat, title: "Couldn’t make the \(p.outputExtension.uppercased()) file",
                          explanation: "The downloaded streams couldn’t be put into this file type. Choosing MKV keeps them exactly as downloaded.",
                          retryable: false, suggestsEngineUpdate: false, detail: Redactor.redact(String(r.stderr.suffix(800))))
        }
    }

    static func burnFilter(_ fileName: String) -> String { BurnIn.filter(fileName) }


    /// Sound encoders, at settings where the conversion is not audible to most people.
    static func encoder(_ codec: AudioCodec, outputExtension: String) -> [String] {
        switch codec {
        case .aac: return ["-c:a", "aac_at", "-b:a", "256k"]            // Apple's AAC encoder (in the managed FFmpeg)
        case .opus: return ["-c:a", "libopus", "-b:a", "160k"]
        case .mp3: return ["-c:a", "libmp3lame", "-b:a", "320k"]
        case .flac: return ["-c:a", "flac"]
        default: return outputExtension == "wav" ? ["-c:a", "pcm_s16le"] : ["-c:a", "aac_at", "-b:a", "256k"]
        }
    }

    func subtitleToSRT(_ file: URL, cancel: CancelToken) async throws -> URL {
        if file.pathExtension == "srt" { return file }
        let out = file.deletingPathExtension().appendingPathExtension("srt")
        let r = try await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-i", file.path, out.path],
                                            started: { cancel.attach($0) })
        guard r.succeeded else { return file }     // keep the original format rather than lose the subtitles
        return out
    }

    /// MP4/MOV store three-letter language codes.
    static func iso639_2(_ code: String) -> String {
        Locale.Language(identifier: code).languageCode?.identifier(.alpha3) ?? "und"
    }
}

public struct VerificationReport: Sendable {
    public var passed: Bool { problems.isEmpty }
    public var problems: [String]
    public var duration: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var width: Int?, height: Int?
    public var summary: String {
        [width.map { "\($0)×\(height ?? 0)" }, videoCodec, audioCodec, duration.map { Fmt.duration($0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// FFprobe reads the finished file back: right streams, right formats, right length.
struct Verifier: Sendable {
    var ffprobe: URL

    func verify(_ file: URL, plan: DownloadPlan, expectedDuration: Double?, slack: Double = 0) async throws -> VerificationReport {
        var report = VerificationReport(problems: [])
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int64) ?? 0
        guard size > 0 else { report.problems.append("The file is empty."); return report }
        let r = try await ProcessRunner.run(ffprobe, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", file.path])
        guard r.succeeded, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any] else {
            report.problems.append("The file can’t be read as media."); return report
        }
        let streams = j["streams"] as? [[String: Any]] ?? []
        let video = streams.first { ($0["codec_type"] as? String) == "video" && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
        let audio = streams.first { ($0["codec_type"] as? String) == "audio" }
        report.videoCodec = (video?["codec_name"] as? String).map(Self.pretty)
        report.audioCodec = (audio?["codec_name"] as? String).map(Self.pretty)
        report.width = video?["width"] as? Int; report.height = video?["height"] as? Int
        report.duration = ((j["format"] as? [String: Any])?["duration"] as? String).flatMap(Double.init)

        let wantsVideo = plan.kind != .audioOnly, wantsAudio = plan.kind != .videoOnly
        if wantsVideo && video == nil { report.problems.append("There’s no picture in the file.") }
        if !wantsVideo && video != nil { report.problems.append("The audio file unexpectedly contains video.") }
        if wantsAudio && audio == nil && plan.soundFormat != nil { report.problems.append("There’s no sound in the file.") }
        if !wantsAudio && audio != nil { report.problems.append("The video-only file still has sound.") }
        if let expected = plan.videoConverted ? VideoCodec.avc : plan.video?.videoCodec, expected != .other, let got = video?["codec_name"] as? String,
           VideoCodec(raw: FormatInspector.codecTag(["codec_name": got]) ?? got) != expected {
            report.problems.append("The picture is \(Self.pretty(got)), not \(expected.name) as chosen.")
        }
        if let want = plan.video?.height, let got = report.height, let w = plan.video?.width, let gw = report.width,
           abs(min(want, w) - min(got, gw)) > 8 {
            report.problems.append("The picture is \(gw)×\(got), not \(w)×\(want) as chosen.")
        }
        if let expected = expectedDuration, let got = report.duration, expected > 5 {
            let tolerance = max(2, expected * 0.02) + slack
            if abs(expected - got) > tolerance {
                report.problems.append("The file is \(Fmt.duration(got)) long, but the video is \(Fmt.duration(expected)).")
            }
        }
        return report
    }

    static func pretty(_ codec: String) -> String {
        switch codec {
        case "h264": "H.264"; case "hevc": "HEVC"; case "av1": "AV1"; case "vp9": "VP9"; case "aac": "AAC"; case "opus": "Opus"
        case "mp3": "MP3"; case "flac": "FLAC"; case "vorbis": "Vorbis"; case let s where s.hasPrefix("pcm"): "PCM"
        default: codec
        }
    }
}

/// Subtitles drawn on the picture: the system's own sans-serif, white with a soft outline, near the bottom.
public enum BurnIn {
    public static func filter(_ fileName: String) -> String {
        "subtitles=filename=\(fileName):fontsdir=/System/Library/Fonts:force_style='FontName=Helvetica Neue,FontSize=17,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,BorderStyle=1,Outline=1.4,Shadow=0.6,MarginV=22'"
    }
}
