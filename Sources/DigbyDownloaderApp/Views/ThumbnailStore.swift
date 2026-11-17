import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import DigbyDownloadCore

/// Video pictures, shown instantly the second time.
///
/// Why: sites serve full-size pictures (often 1280×720, 100–300 KB), many with "don't cache" headers, and
/// some links expire within days (Facebook, X). Fetching them fresh on every screen, over a VPN, took
/// seconds and left old Downloaded rows blank. Now each picture is fetched once, shrunk to 480 px and
/// saved as a small JPEG (≈ 20–40 KB) in the Caches folder, and kept decoded in memory while the app runs.
/// The cache stays under 60 MB (oldest removed first) and can be deleted at any time; nothing is lost.
/// If a site's picture is gone, a frame from the downloaded file itself is used instead.
final class ThumbnailStore: @unchecked Sendable {
    static let shared = ThumbnailStore()

    static let maxPixels = 480
    static let quality = 0.72
    static let diskLimit: Int64 = 60_000_000

    private let memory: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 400; return c }()
    private let lock = NSLock()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var misses: Set<String> = []          // failed this run: don't ask the site again until relaunch
    private let session: URLSession = {
        let c = URLSessionConfiguration.default    // the Mac's proxy settings apply
        c.timeoutIntervalForRequest = 20
        c.urlCache = nil                           // this store is the cache
        c.httpAdditionalHeaders = ["Accept": "image/avif,image/webp,image/jpeg,image/png,image/*;q=0.8"]
        return URLSession(configuration: c)
    }()

    let folder: URL = {
        if let h = ProcessInfo.processInfo.environment["DIGBY_DL_HOME"] {
            return URL(fileURLWithPath: h, isDirectory: true).appendingPathComponent("Thumbnails", isDirectory: true)
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Digby Video Downloader/Thumbnails", isDirectory: true)
    }()

    private init() {
        Task.detached(priority: .background) { [self] in prune() }
    }

    // MARK: Keys

    static func key(url: URL?, file: URL?) -> String? {
        if let url { return "u:" + url.absoluteString }
        if let file {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            return "f:\(file.path)@\(Int(modified))"
        }
        return nil
    }
    private func diskURL(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(String(hash.prefix(32)) + ".jpg")
    }

    // MARK: Reading

    /// What can be shown right now without waiting: from memory, or the small file on disk (≈ 1 ms).
    func immediate(url: URL?, file: URL?) -> NSImage? {
        for k in [Self.key(url: url, file: nil), Self.key(url: nil, file: file)].compactMap({ $0 }) {
            if let m = memory.object(forKey: k as NSString) { return m }
            if let img = readDisk(k) { return img }
        }
        return nil
    }

    /// Fetches (once), shrinks and stores the site's picture; falls back to a frame of the downloaded file.
    func load(url: URL?, file: URL?) async -> NSImage? {
        if let img = immediate(url: url, file: file) { return img }
        if let url, let k = Self.key(url: url, file: nil), let img = await once(k, { await self.fetch(url) }) { return img }
        if let file, let k = Self.key(url: nil, file: file), let img = await once(k, { await self.frame(of: file) }) { return img }
        return nil
    }

    /// Warms the cache ahead of time (e.g. when a link's details arrive), so the picture is there when shown.
    func prefetch(_ url: URL?) {
        guard let url else { return }
        Task.detached(priority: .utility) { _ = await self.load(url: url, file: nil) }
    }

    private func once(_ key: String, _ make: @escaping @Sendable () async -> CGImage?) async -> NSImage? {
        let task: Task<NSImage?, Never> = lock.withLock {
            if misses.contains(key) { return Task { nil } }
            if let t = inFlight[key] { return t }
            let t = Task.detached(priority: .userInitiated) { [self] () -> NSImage? in
                guard let cg = await make() else { lock.withLock { _ = misses.insert(key) }; return nil }
                writeDisk(cg, key)
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                memory.setObject(img, forKey: key as NSString)
                return img
            }
            inFlight[key] = t
            return t
        }
        let img = await task.value
        lock.withLock { inFlight[key] = nil }
        return img
    }

    private func readDisk(_ key: String) -> NSImage? {
        let u = diskURL(key)
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(img, forKey: key as NSString)
        return img
    }

    private func writeDisk(_ cg: CGImage, _ key: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let u = diskURL(key)
        guard let dest = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: Self.quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    // MARK: Making pictures

    /// Downloads the site's picture and shrinks it (decoding only what's needed).
    private func fetch(_ url: URL) async -> CGImage? {
        let data: Data
        if url.isFileURL {
            guard let d = try? Data(contentsOf: url) else { return nil }
            data = d
        } else {
            guard let (d, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
            data = d
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixels,
        ] as CFDictionary)
    }

    /// A frame from early in the downloaded video (past any fade-in), for when the site's picture is gone.
    private func frame(of file: URL) async -> CGImage? {
        let asset = AVURLAsset(url: file)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: Self.maxPixels, height: Self.maxPixels)
        let at = CMTime(seconds: min(duration.seconds * 0.1, 5), preferredTimescale: 600)
        return try? await gen.image(at: at).image
    }

    // MARK: Housekeeping

    /// Keeps the folder under its limit, removing the oldest pictures first.
    private func prune() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { u -> (URL, Int64, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > Self.diskLimit else { return }
        entries.sort { $0.2 < $1.2 }
        for (u, size, _) in entries where total > Self.diskLimit * 8 / 10 {
            try? fm.removeItem(at: u); total -= size
        }
    }
}
