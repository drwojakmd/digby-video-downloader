import Foundation

/// The HTTP status of a web page, read the way a browser would (Mac's proxy, normal redirects), without
/// downloading the page. Used to tell a missing page (404) from one the engine couldn't understand.
public enum PageStatus {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    public static func of(_ url: URL, timeout: TimeInterval = 10) async -> Int? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        // Only the headers are needed; the body is never read.
        guard let (_, response) = try? await session.bytes(for: req) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    /// The engine's failure, corrected when the page itself is missing.
    public static func correct(_ f: Failure, for url: URL) async -> Failure {
        guard [.outdatedExtractor, .unknown, .unsupportedFormat, .jsRuntime].contains(f.kind), let status = await of(url) else { return f }
        return ErrorClassifier.missingPage(status: status, after: f) ?? f
    }
}
