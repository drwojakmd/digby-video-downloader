import Foundation
import AppKit

/// Browsers whose sign-in yt-dlp can use.
public enum Browser: String, CaseIterable, Codable, Sendable {
    case brave, chrome, edge, firefox, safari, opera, vivaldi, chromium
    public var displayName: String {
        switch self {
        case .brave: "Brave"; case .chrome: "Google Chrome"; case .edge: "Microsoft Edge"; case .firefox: "Firefox"
        case .safari: "Safari"; case .opera: "Opera"; case .vivaldi: "Vivaldi"; case .chromium: "Chromium"
        }
    }
    var bundleID: String {
        switch self {
        case .brave: "com.brave.Browser"; case .chrome: "com.google.Chrome"; case .edge: "com.microsoft.edgemac"
        case .firefox: "org.mozilla.firefox"; case .safari: "com.apple.Safari"; case .opera: "com.operasoftware.Opera"
        case .vivaldi: "com.vivaldi.Vivaldi"; case .chromium: "org.chromium.Chromium"
        }
    }
    public var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    /// What the person will see the first time (plain English, shown before it happens).
    public var permissionNote: String {
        switch self {
        case .safari: "macOS protects Safari’s sign-ins: Digby needs Full Disk Access (System Settings → Privacy & Security) to read them."
        case .firefox: "Firefox’s sign-ins can be read without any extra permission."
        default: "macOS will ask to let Digby’s engine use the “\(displayName) Safe Storage” key. Click Always Allow (it asks again after an engine update)."
        }
    }
    /// The browser macOS opens links with, if Digby knows it.
    public static var systemDefault: Browser? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let id = Bundle(url: app)?.bundleIdentifier else { return nil }
        return allCases.first { $0.bundleID.lowercased() == id.lowercased() }
    }
}

/// A site that can use your sign-in: YouTube (with Google's account cookies), or any other site by its
/// domain ("vimeo.com", "rumble.com"). Cookies are only ever sent to that site's own domains.
/// Saved as its plain name ("youtube" or the domain), so earlier settings keep working.
public struct SignInSite: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
    public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    public var id: String { rawValue }

    public static let youtube = SignInSite(rawValue: "youtube")
    var isYouTube: Bool { rawValue == "youtube" }
    public var isYouTubeSite: Bool { isYouTube }
    /// Sites always listed in Settings, even before they're set up.
    public static let known: [SignInSite] = [.youtube]

    public var displayName: String { isYouTube ? "YouTube" : rawValue }
    var hosts: [String] { isYouTube ? ["youtube.com", "youtu.be", "youtube-nocookie.com"] : [rawValue] }
    /// Which cookies the site's jar keeps. YouTube: its own plus Google's account sign-in cookies only
    /// (never Gmail, Drive, Pay…). Other sites: that domain and its subdomains only.
    public func keeps(domain raw: String) -> Bool {
        let d = raw.replacingOccurrences(of: "#HttpOnly_", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        if isYouTube { return d == "youtube.com" || d.hasSuffix(".youtube.com") || d == "google.com" || d == "accounts.google.com" }
        return d == rawValue || d.hasSuffix("." + rawValue)
    }
    public var signInPage: URL {
        isYouTube ? URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!
                  : URL(string: "https://\(rawValue)/")!
    }

    /// YouTube for its hosts; otherwise the link's site domain ("www.vimeo.com" → "vimeo.com", "x.co.uk" kept whole).
    public static func site(for url: URL) -> SignInSite? {
        guard let host = url.host?.lowercased(), host.contains(".") else { return nil }
        if youtube.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .youtube }
        let parts = host.split(separator: ".").map(String.init)
        let twoPartSuffixes: Set<String> = ["co.uk", "com.au", "co.jp", "com.br", "co.nz", "com.cn", "co.in", "org.uk"]
        let take = parts.count >= 3 && twoPartSuffixes.contains(parts.suffix(2).joined(separator: ".")) ? 3 : 2
        return SignInSite(rawValue: parts.suffix(take).joined(separator: "."))
    }
}

/// How each site's sign-in is obtained. Stored in Application Support/Sign-in/settings.json.
public struct SignInSettings: Codable, Sendable, Equatable {
    public enum Source: Codable, Sendable, Equatable { case browser(Browser), digbyWindow }
    public var sites: [SignInSite: Source] = [:]
    /// "Use my browser's sign-in for any site that needs it": tried automatically when a site refuses.
    public var anySite: Browser? = nil
    public init() {}

    static var folder: URL { Paths.home.appendingPathComponent("Sign-in", isDirectory: true) }
    static var file: URL { folder.appendingPathComponent("settings.json") }
    public static func load() -> SignInSettings {
        (try? JSONDecoder().decode(SignInSettings.self, from: Data(contentsOf: file))) ?? SignInSettings()
    }
    public func save() throws {
        try SignInStore.ensureFolder()
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }
}

/// The per-site cookie files (Netscape format, readable only by you, never logged).
public enum SignInStore {
    static func ensureFolder() throws {
        try Paths.ensure(SignInSettings.folder)
        chmod(SignInSettings.folder.path, 0o700)
    }
    public static func jar(for site: SignInSite) -> URL { SignInSettings.folder.appendingPathComponent("\(site.rawValue)-cookies.txt") }
    public static func hasJar(_ site: SignInSite) -> Bool { FileManager.default.fileExists(atPath: jar(for: site).path) }
    public static func forget(_ site: SignInSite) {
        try? FileManager.default.removeItem(at: jar(for: site))
        var s = SignInSettings.load(); s.sites[site] = nil; try? s.save()
    }

    /// Keeps only cookies for the site's own domains (a browser export contains every site) and locks the file.
    public static func restrict(_ file: URL, to site: SignInSite) throws {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            if line.hasPrefix("# Netscape") { return true }
            if line.isEmpty || (line.hasPrefix("#") && !line.hasPrefix("#HttpOnly_")) { return false }
            return site.keeps(domain: line.split(separator: "\t").first.map(String.init) ?? "")
        }
        try (kept.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        chmod(file.path, 0o600)
    }

    /// Writes a Netscape cookie file from cookies captured in Digby's own sign-in window.
    public static func write(_ cookies: [HTTPCookie], for site: SignInSite) throws {
        try ensureFolder()
        var lines = ["# Netscape HTTP Cookie File"]
        for c in cookies {
            guard site.keeps(domain: c.domain) else { continue }
            let d = (c.domain.hasPrefix(".") ? "" : ".") + c.domain
            let expiry = Int(c.expiresDate?.timeIntervalSince1970 ?? Date().addingTimeInterval(86_400 * 30).timeIntervalSince1970)
            lines.append([(c.isHTTPOnly ? "#HttpOnly_" : "") + d, "TRUE", c.path, c.isSecure ? "TRUE" : "FALSE", "\(expiry)", c.name, c.value].joined(separator: "\t"))
        }
        let f = jar(for: site)
        try (lines.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8)
        chmod(f.path, 0o600)
    }
}

extension YtDlpEngine {
    /// Cookie options for a link: none unless you've set up sign-in for its site.
    /// `refresh` re-copies the sign-in from the browser (used once after the site rejects the saved copy).
    func signInArguments(for url: URL, refresh: Bool = false) -> [String] {
        guard let site = SignInSite.site(for: url), let source = SignInSettings.load().sites[site] else { return [] }
        let jar = SignInStore.jar(for: site)
        try? SignInStore.ensureFolder()
        switch source {
        case .browser(let b):
            // Read fresh from the browser every time and keep no copy: YouTube rotates session cookies, and a
            // saved copy goes stale silently (fewer formats, no error). Fresh is reliable and stores nothing.
            try? FileManager.default.removeItem(at: jar)
            return ["--cookies-from-browser", b.rawValue]
        case .digbyWindow:
            return SignInStore.hasJar(site) ? ["--cookies", jar.path] : []
        }
    }

    func afterRun(_ url: URL) {
        if let site = SignInSite.site(for: url), SignInStore.hasJar(site) { try? SignInStore.restrict(SignInStore.jar(for: site), to: site) }
    }

    public static func needsSignIn(_ f: Failure) -> Bool { f.kind == .botCheck || f.kind == .loginRequired || f.kind == .privateMedia }
    /// Failures a signed-in visit can fix (X answers "No video formats found" to visitors it won't serve).
    static func signInMightHelp(_ f: Failure) -> Bool {
        needsSignIn(f) || f.kind == .blocked || f.detail.lowercased().contains("no video formats found")
    }
    /// Browser sign-ins are always read fresh, so there's nothing to refresh; kept for future sources.
    func canRefreshSignIn(_ url: URL) -> Bool { false }
}
