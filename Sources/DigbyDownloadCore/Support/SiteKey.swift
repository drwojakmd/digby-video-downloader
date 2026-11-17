import Foundation

/// The site a page belongs to, for choices remembered per site: "substack.com" for any Substack author's page,
/// "bbc.co.uk" for "www.bbc.co.uk". Asking once per site rather than once per address keeps questions rare.
public enum SiteKey {
    /// Second-level labels used under two-letter country endings ("co.uk", "com.au", "ne.jp").
    static let countrySecondLevels: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gv"]

    public static func of(_ url: URL) -> String? {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty else { return nil }
        // IP addresses (and IPv6) are their own site.
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let top = labels[labels.count - 1], second = labels[labels.count - 2]
        let keep = top.count == 2 && countrySecondLevels.contains(second) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
