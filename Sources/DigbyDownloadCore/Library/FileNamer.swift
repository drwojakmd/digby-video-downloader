import Foundation

/// File names from a template, made safe for macOS, never overwriting anything.
public enum FileNamer {
    /// Tokens: {title} {uploader} {date} {resolution} {site} {id} {playlist} {index}
    public static func render(_ template: String, media: MediaInfo, plan: DownloadPlan?, playlist: String? = nil, index: Int? = nil) -> String {
        var date = ""
        if let d = media.uploadDate { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); date = f.string(from: d) }
        let resolution: String = {
            guard let p = plan else { return "" }
            if p.kind == .audioOnly { return "audio" }
            return p.video?.tier?.name ?? ""
        }()
        let values = ["title": media.title, "uploader": media.uploader ?? "", "date": date, "resolution": resolution,
                      "site": media.site, "id": media.id, "playlist": playlist ?? "", "index": index.map { String(format: "%02d", $0) } ?? ""]
        var out = template
        for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        // Tidy what empty tokens leave behind: "()", "[]", doubled separators.
        out = out.replacingOccurrences(of: "()", with: "").replacingOccurrences(of: "[]", with: "")
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        for (doubled, single) in [(" - - ", " - "), (" · · ", " · "), ("__", "_"), ("_ _", "_")] {
            while out.contains(doubled) { out = out.replacingOccurrences(of: doubled, with: single) }
        }
        let s = sanitize(out)
        return s.isEmpty ? sanitize(media.title.isEmpty ? "Download" : media.title) : s
    }

    /// Removes characters macOS (or a later copy to another system) can't handle; limits length.
    public static func sanitize(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "/", with: "–").replacingOccurrences(of: ":", with: " –")
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !"\\<>|\"?*".unicodeScalars.contains($0) })
        s = s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".-–·_")))
        // 200 bytes leaves room for " (99).ext" and subtitle suffixes within the 255-byte limit.
        while s.utf8.count > 200 { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `name.ext` in `folder`, or `name (2).ext`, `name (3).ext`… if taken.
    public static func unique(_ name: String, ext: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) (\(n)).\(ext)"); n += 1
        }
        return candidate
    }
}

/// A file-name template as building blocks: the parts in order, how each is written, and what goes between
/// them. Settings builds names with these instead of typed `{tokens}`; any template it can't express (typed
/// text of your own) stays editable as text.
public struct NameParts: Equatable, Sendable {
    public enum Token: String, CaseIterable, Sendable {
        case title, uploader, date, resolution, site, id
        public var label: String {
            switch self {
            case .title: "Title"; case .uploader: "Channel"; case .date: "Upload Date"
            case .resolution: "Quality"; case .site: "Site"; case .id: "Video ID"
            }
        }
        public var help: String {
            switch self {
            case .title: "The video’s title"
            case .uploader: "Who posted it (channel or account name)"
            case .date: "When it was posted, as 2026-11-15 (sorts in order)"
            case .resolution: "The picture size you chose, like 1080p, or “audio”"
            case .site: "The website, like YouTube"
            case .id: "The site’s own code for the video (always unique)"
            }
        }
    }
    public enum Wrap: String, CaseIterable, Sendable {
        case none, round, square
        public var label: String { switch self { case .none: "Plain"; case .round: "In (brackets)"; case .square: "In [square brackets]" } }
    }
    public struct Part: Equatable, Sendable, Identifiable {
        public var token: Token
        public var wrap: Wrap
        public var id: String { token.rawValue }
        public init(_ token: Token, _ wrap: Wrap = .none) { self.token = token; self.wrap = wrap }
    }
    public static let separators: [(name: String, value: String)] = [("Dash", " - "), ("Dot", " · "), ("Space", " "), ("Underscore", "_")]

    public var parts: [Part]
    public var separator: String

    public init(parts: [Part], separator: String = " - ") { self.parts = parts; self.separator = separator }

    public var template: String {
        var out = ""
        for (i, p) in parts.enumerated() {
            if i > 0 { out += p.wrap == .none ? separator : (separator == "_" ? "_" : " ") }
            switch p.wrap {
            case .none: out += "{\(p.token.rawValue)}"
            case .round: out += "({\(p.token.rawValue)})"
            case .square: out += "[{\(p.token.rawValue)}]"
            }
        }
        return out
    }

    /// Reads a template back into parts; nil when it has text of its own the blocks can't show.
    public init?(template: String) {
        var parts: [Part] = [], gaps: [String] = [], literal = ""
        var rest = Substring(template)
        func token(_ s: Substring, open: String, close: String) -> (Token, Int)? {
            guard s.hasPrefix(open + "{"), let end = s.range(of: "}" + close) else { return nil }
            let name = s[s.index(s.startIndex, offsetBy: open.count + 1)..<end.lowerBound]
            guard let t = Token(rawValue: String(name)) else { return nil }
            return (t, s.distance(from: s.startIndex, to: end.upperBound))
        }
        while !rest.isEmpty {
            var hit: (Token, Wrap, Int)?
            if let (t, n) = token(rest, open: "(", close: ")") { hit = (t, .round, n) }
            else if let (t, n) = token(rest, open: "[", close: "]") { hit = (t, .square, n) }
            else if let (t, n) = token(rest, open: "", close: "") { hit = (t, .none, n) }
            if let (t, w, n) = hit {
                if parts.isEmpty { guard literal.isEmpty else { return nil } } else { gaps.append(literal) }
                literal = ""; parts.append(Part(t, w)); rest = rest.dropFirst(n)
            } else { literal.append(rest.removeFirst()) }
        }
        guard !parts.isEmpty, literal.isEmpty, Set(parts.map(\.token)).count == parts.count else { return nil }
        // The gap before a plain part is the separator; before a bracketed part, a space (or "_").
        let plainGaps = zip(parts.dropFirst(), gaps).filter { $0.0.wrap == .none }.map(\.1)
        let sep = plainGaps.first ?? (gaps.contains("_") ? "_" : " - ")
        guard Self.separators.contains(where: { $0.value == sep }), plainGaps.allSatisfy({ $0 == sep }) else { return nil }
        for (p, g) in zip(parts.dropFirst(), gaps) where p.wrap != .none {
            guard g == (sep == "_" ? "_" : " ") else { return nil }
        }
        self.init(parts: parts, separator: sep)
    }

    /// Ready-made arrangements.
    public static let presets: [(name: String, parts: NameParts)] = [
        ("Title (Quality)", NameParts(parts: [Part(.title), Part(.resolution, .round)])),
        ("Title", NameParts(parts: [Part(.title)])),
        ("Channel - Title", NameParts(parts: [Part(.uploader), Part(.title)])),
        ("Date - Title", NameParts(parts: [Part(.date), Part(.title)])),
        ("Date - Channel - Title [ID]", NameParts(parts: [Part(.date), Part(.uploader), Part(.title), Part(.id, .square)])),
    ]
}

/// Optional sorting of downloads into subfolders of the usual Videos and Music folders.
public enum FolderSorting: String, CaseIterable, Codable, Sendable {
    case none, month, day, site, channel

    public var label: String {
        switch self {
        case .none: "Don’t sort"; case .month: "By month"; case .day: "By day"
        case .site: "By website"; case .channel: "By channel"
        }
    }
    public var help: String {
        switch self {
        case .none: "Everything goes straight into the folder."
        case .month: "A folder for each month you download in, like “2026-11 November”. Tidy without too many folders."
        case .day: "A folder for each day you download on, like “2026-11-15”. Can mean many small folders."
        case .site: "A folder for each website, like “YouTube”."
        case .channel: "A folder for each channel or account, like “Highland Skies Studio”."
        }
    }

    /// The subfolder name for a download made on `date` (nil: none). Names sort in date order.
    public func subfolder(media: MediaInfo, date: Date = Date()) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, d = c.day ?? 1
        switch self {
        case .none: return nil
        case .month:
            let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "LLLL"
            return String(format: "%04d-%02d ", y, m) + f.string(from: date)
        case .day: return String(format: "%04d-%02d-%02d", y, m, d)
        case .site: return FileNamer.sanitize(media.site.isEmpty ? "Other sites" : media.site)
        case .channel:
            let n = FileNamer.sanitize(media.uploader ?? "")
            return n.isEmpty ? FileNamer.sanitize(media.site.isEmpty ? "Unknown" : media.site) : n
        }
    }
}
