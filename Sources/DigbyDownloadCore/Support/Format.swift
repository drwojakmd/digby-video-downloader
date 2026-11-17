import Foundation

/// Number and time formatting shared by the app and the tests.
public enum Fmt {
    public static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: b)
    }
    public static func size(_ s: SizeEstimate?) -> String {
        guard let s else { return "Size unknown" }
        return (s.isExact ? "" : "≈ ") + bytes(s.bytes)
    }
    public static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded()), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    public static func speed(_ bytesPerSecond: Double) -> String { bytes(Int64(bytesPerSecond)) + "/s" }
    public static func remaining(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) s left" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min left" }
        return String(format: "%.1f h left", seconds / 3600)
    }
    public static func fps(_ f: Double) -> String { f.rounded() == f ? "\(Int(f)) fps" : String(format: "%.2f fps", f) }
}

extension DownloadPlan {
    /// Short tags describing the result, e.g. ["1080p", "H.264", "AAC · English (original)", "MP4"].
    public func chips(catalogue: FormatCatalogue) -> [String] {
        var out: [String] = []
        if let v = video {
            if let t = v.tier { out.append(t.name + (v.fps.map { $0 > 31 ? " \(Int($0.rounded()))" : "" } ?? "")) }
            if let c = v.videoCodec {
                if burnsSubtitles { out.append("H.264 · subtitles on picture") }
                else if videoConverted { out.append(c == .avc ? "H.264 (re-encoded)" : "H.264 (converted from \(c == .other ? "original" : c.name))") }
                else { out.append(c.name) }
            }
            if v.dynamicRange.isHDR { out.append("HDR") }
        }
        if let s = soundFormat, kind != .videoOnly, let codec = s.audioCodec {
            var a = codec.name
            if case .convert(let to) = audioAction { a = to == .other ? "WAV" : to.name }
            if let l = s.language { a += " · " + Languages.name(Languages.base(l)) + (s.audioRole == .original || catalogue.originalLanguage?.code == Languages.base(l) ? " (original)" : "") }
            out.append(a)
        }
        let fileType = container?.name ?? outputExtension.uppercased()
        if out.last?.hasPrefix(fileType) != true { out.append(fileType) }
        return out
    }
}
