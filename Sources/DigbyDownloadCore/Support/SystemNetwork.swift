import Foundation
import Security
import CFNetwork

/// Lets the bundled FFmpeg tools (which use their own TLS library) reach the network the way macOS does:
/// through the Mac's configured proxy, trusting the same certificates (Apple's roots plus any the user or
/// their organisation added, as offices and security software often do).
public enum SystemNetwork {
    /// The HTTPS proxy from System Settings (or HTTPS_PROXY), as http://host:port.
    public static var httpsProxy: String? {
        if let env = ProcessInfo.processInfo.environment["HTTPS_PROXY"] ?? ProcessInfo.processInfo.environment["https_proxy"], !env.isEmpty { return env }
        guard let s = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              (s[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 1,
              let host = s[kCFNetworkProxiesHTTPSProxy as String] as? String, !host.isEmpty else { return nil }
        let port = s[kCFNetworkProxiesHTTPSPort as String] as? Int ?? 443
        return "http://\(host):\(port)"
    }

    private static let bundleLock = NSLock()
    private static var cachedBundle: URL?

    /// A PEM file of every certificate macOS trusts, rebuilt once per launch.
    public static func trustBundle() -> URL? {
        bundleLock.lock(); defer { bundleLock.unlock() }
        if let c = cachedBundle { return c }
        var certs: [SecCertificate] = []
        var anchors: CFArray?
        if SecTrustCopyAnchorCertificates(&anchors) == errSecSuccess, let a = anchors as? [SecCertificate] { certs += a }
        for domain in [SecTrustSettingsDomain.admin, .user] {
            var list: CFArray?
            if SecTrustSettingsCopyCertificates(domain, &list) == errSecSuccess, let l = list as? [SecCertificate] { certs += l }
        }
        guard !certs.isEmpty else { return nil }
        var pem = ""
        for c in certs {
            let der = SecCertificateCopyData(c) as Data
            let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            pem += "-----BEGIN CERTIFICATE-----\n\(b64)\n-----END CERTIFICATE-----\n"
        }
        guard let dir = try? Paths.ensure(Paths.home) else { return nil }
        let file = dir.appendingPathComponent("trusted-certificates.pem")
        guard (try? Data(pem.utf8).write(to: file, options: .atomic)) != nil else { return nil }
        cachedBundle = file
        return file
    }

    /// FFmpeg/FFprobe options for network input.
    public static var ffmpegNetworkOptions: [String] {
        var o: [String] = []
        if let p = httpsProxy { o += ["-http_proxy", p] }
        if let b = trustBundle() { o += ["-ca_file", b.path] }
        return o
    }
}
