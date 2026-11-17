import Foundation
import CryptoKit
import Security

/// The engines Digby manages. None are bundled; each comes from its official source.
public enum ToolID: String, CaseIterable, Codable, Sendable {
    case ytdlp = "yt-dlp", deno = "deno", ffmpeg = "ffmpeg", ffprobe = "ffprobe"

    public var displayName: String {
        switch self { case .ytdlp: "yt-dlp"; case .deno: "Deno"; case .ffmpeg: "FFmpeg"; case .ffprobe: "FFprobe" }
    }
    public var role: String {
        switch self {
        case .ytdlp: "Finds and downloads the video on each website"
        case .deno: "Solves the puzzles some sites (like YouTube) use to protect their streams"
        case .ffmpeg: "Joins picture and sound into one file, and converts when you ask"
        case .ffprobe: "Checks every finished file before it’s called done"
        }
    }
    /// Executable inside an installed version folder.
    var executable: String {
        switch self { case .ytdlp: "yt-dlp_macos"; case .deno: "deno"; case .ffmpeg: "ffmpeg"; case .ffprobe: "ffprobe" }
    }
    /// Apple Developer ID team that must have signed the binary (nil: verified by signed checksums instead).
    var pinnedTeam: String? {
        switch self { case .ytdlp: nil; case .deno: "2H4KBF436B"; case .ffmpeg, .ffprobe: "KU3N25YGLU" }
    }
    var versionArguments: [String] { self == .ffmpeg || self == .ffprobe ? ["-version"] : ["--version"] }
    /// The first launch of a freshly unpacked yt-dlp can take ~30 s while macOS checks its files once.
    var smokeTimeout: TimeInterval { self == .ytdlp ? 180 : 60 }
}

public enum UpdateChannel: String, CaseIterable, Codable, Sendable {
    case stable, nightly, experimental
    public var label: String { rawValue.capitalized }
    var ytdlpRepository: String {
        switch self { case .stable: "yt-dlp/yt-dlp"; case .nightly: "yt-dlp/yt-dlp-nightly-builds"; case .experimental: "yt-dlp/yt-dlp-master-builds" }
    }
}

/// A specific downloadable version and how to prove it's genuine.
public struct ToolRelease: Sendable, Hashable {
    public var tool: ToolID
    public var version: String
    public var archive: URL
    public var sha256: String          // expected, from a verified source
    public var source: String          // human-readable origin
    public init(tool: ToolID, version: String, archive: URL, sha256: String, source: String) {
        self.tool = tool; self.version = version; self.archive = archive; self.sha256 = sha256; self.source = source
    }
}

public enum DependencyError: Error, CustomStringConvertible {
    case network(String), verification(String), install(String), notInstalled(ToolID)
    public var description: String {
        switch self {
        case .network(let s): "Couldn’t reach the update server: \(s)"
        case .verification(let s): "An engine download failed its authenticity check, so it wasn’t installed: \(s)"
        case .install(let s): "Couldn’t install an engine: \(s)"
        case .notInstalled(let t): "\(t.displayName) isn’t installed yet"
        }
    }
}

/// Finds the latest genuine release of each tool.
enum ReleaseSources {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpAdditionalHeaders = ["User-Agent": "DigbyVideoDownloader"]
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL) async throws -> Data {
        do {
            let (d, r) = try await session.data(from: url)
            guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
                throw DependencyError.network("HTTP \((r as? HTTPURLResponse)?.statusCode ?? 0) from \(url.host ?? "")")
            }
            return d
        } catch let e as DependencyError { throw e } catch { throw DependencyError.network(error.localizedDescription) }
    }

    struct GitHubRelease: Decodable {
        struct Asset: Decodable { var name: String; var browser_download_url: URL }
        var tag_name: String; var assets: [Asset]
        func asset(_ n: String) throws -> URL {
            guard let a = assets.first(where: { $0.name == n }) else { throw DependencyError.network("release has no \(n)") }
            return a.browser_download_url
        }
    }
    static func github(_ repo: String) async throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: await get(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!))
    }

    /// The newest release's name only (one small request), for the frequent check.
    static func latestTag(_ tool: ToolID, channel: UpdateChannel) async throws -> String {
        guard tool == .ytdlp else { return try await latest(tool, channel: channel).version }
        return try await github(channel.ytdlpRepository).tag_name
    }

    static func latest(_ tool: ToolID, channel: UpdateChannel) async throws -> ToolRelease {
        switch tool {
        case .ytdlp:
            let r = try await github(channel.ytdlpRepository)
            let sums = try await get(r.asset("SHA2-256SUMS")), sig = try await get(r.asset("SHA2-256SUMS.sig"))
            let key = try OpenPGP.publicKey(armored: PinnedKeys.ytDlp)
            guard key.fingerprint.hex == PinnedKeys.ytDlpFingerprint else { throw DependencyError.verification("pinned key mismatch") }
            do { try OpenPGP.verify(data: sums, signature: sig, key: key) }
            catch { throw DependencyError.verification("yt-dlp checksum signature: \(error)") }
            guard let hash = checksum(in: sums, for: "yt-dlp_macos.zip") else { throw DependencyError.verification("no checksum for yt-dlp_macos.zip") }
            return ToolRelease(tool: tool, version: r.tag_name, archive: try r.asset("yt-dlp_macos.zip"), sha256: hash,
                               source: "github.com/\(channel.ytdlpRepository) (signed checksums)")
        case .deno:
            let r = try await github("denoland/deno")
            let name = "deno-aarch64-apple-darwin.zip"
            let sums = try await get(r.asset(name + ".sha256sum"))
            guard let hash = checksum(in: sums, for: name) else { throw DependencyError.verification("no checksum for Deno") }
            return ToolRelease(tool: tool, version: r.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v")), archive: try r.asset(name),
                               sha256: hash, source: "github.com/denoland/deno + Developer ID check")
        case .ffmpeg, .ffprobe:
            let redirect = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/\(tool.rawValue).zip")!
            let real = try await resolveRedirect(redirect)
            // …/download/macos/arm64/<timestamp>_<version>/ffmpeg.zip
            let folder = real.deletingLastPathComponent().lastPathComponent
            let version = folder.split(separator: "_", maxSplits: 1).last.map(String.init) ?? folder
            let sums = try await get(URL(string: real.absoluteString + ".sha256")!)
            guard let hash = checksum(in: sums, for: "\(tool.rawValue).zip") else { throw DependencyError.verification("no checksum for \(tool.displayName)") }
            return ToolRelease(tool: tool, version: version, archive: real, sha256: hash, source: "ffmpeg.martin-riedl.de + Developer ID check")
        }
    }

    /// "hash  filename" lines → the hash for `file`.
    static func checksum(in data: Data, for file: String) -> String? {
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts.last.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "*")) }) == file,
               parts[0].count == 64 { return String(parts[0]).lowercased() }
        }
        return nil
    }

    /// The URL a redirect points to, without downloading the target.
    static func resolveRedirect(_ url: URL) async throws -> URL {
        final class Stop: NSObject, URLSessionTaskDelegate {
            var location: URL?
            func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse,
                            newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                location = newRequest.url; completionHandler(nil)
            }
        }
        let stop = Stop()
        var req = URLRequest(url: url); req.setValue("DigbyVideoDownloader", forHTTPHeaderField: "User-Agent")
        do {
            _ = try await URLSession.shared.data(for: req, delegate: stop)
        } catch { throw DependencyError.network(error.localizedDescription) }
        guard let loc = stop.location else { throw DependencyError.network("no redirect from \(url.host ?? "")") }
        return loc
    }
}

enum Verify {
    static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return Data(hasher.finalize()).hex
    }

    /// Valid Apple Developer ID signature by `team`.
    static func developerID(_ file: URL, team: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code else {
            throw DependencyError.verification("\(file.lastPathComponent) has no code signature")
        }
        var req: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
        guard SecRequirementCreateWithString(text, [], &req) == errSecSuccess, let req else { throw DependencyError.verification("requirement") }
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), req)
        guard status == errSecSuccess else {
            throw DependencyError.verification("\(file.lastPathComponent) isn’t signed by the expected developer (code \(status))")
        }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
