import Foundation

/// What went wrong, in plain English, with whether trying again can help.
public struct Failure: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable, Codable {
        case outdatedExtractor, botCheck, loginRequired, privateMedia, unavailable, geoRestricted, network, rateLimited,
             blocked, unsupportedSite, unsupportedFormat, missingEngine, jsRuntime, permissions, diskFull, drm,
             verificationFailed, cancelled, unknown
    }
    public var kind: Kind
    public var title: String
    public var explanation: String
    /// Worth retrying automatically (network blips, rate limits) or after an engine update.
    public var retryable: Bool
    public var suggestsEngineUpdate: Bool
    /// The engine's own words, redacted, for the diagnostic report.
    public var detail: String
    /// Nothing a browser could find on the page (it doesn't exist, or the stream is live/not started): no page-based routes.
    public var noPageRoutes = false

    public var description: String { "\(title): \(explanation)" }

    public init(kind: Kind, title: String, explanation: String, retryable: Bool, suggestsEngineUpdate: Bool, detail: String) {
        self.kind = kind; self.title = title; self.explanation = explanation
        self.retryable = retryable; self.suggestsEngineUpdate = suggestsEngineUpdate; self.detail = detail
    }
}

public enum ErrorClassifier {
    public static func classify(stderr: String, exitCode: Int32 = 1) -> Failure {
        let errorLines = stderr.split(separator: "\n").filter { $0.contains("ERROR") }.map(String.init)
        let text = (errorLines.isEmpty ? stderr : errorLines.joined(separator: "\n"))
        let lower = text.lowercased()
        let detail = Redactor.redact(String(text.suffix(1500)))
        func f(_ k: Failure.Kind, _ t: String, _ e: String, retry: Bool = false, update: Bool = false) -> Failure {
            Failure(kind: k, title: t, explanation: e, retryable: retry, suggestsEngineUpdate: update, detail: detail)
        }
        if lower.contains("drm") {
            return f(.drm, "This video is copy-protected",
                     "The site protects it with DRM (digital rights management). Digby doesn’t download copy-protected media.")
        }
        if lower.contains("cloudflare") || lower.contains("just a moment") || lower.contains("turnstile") || lower.contains("captcha") || lower.contains("challenge page") {
            return f(.botCheck, "The site wants to check you’re human",
                     "It shows an “Are you human?” check (a CAPTCHA) that only a person can pass. Open the page in Digby, pass the check yourself, and download from there.")
        }
        if lower.contains("sign in to confirm") && (lower.contains("bot") || lower.contains("not a robot")) {
            return f(.botCheck, "The site wants to check you’re a person",
                     "It has paused downloads from this connection (this often happens on VPNs and shared networks). Signing in with your browser for this site usually solves it, or try again later.")
        }
        if lower.contains("private video") || lower.contains("this video is private") {
            return f(.privateMedia, "This video is private",
                     "Its owner has limited who can watch it. If you can watch it while signed in, use your browser’s sign-in for this site.")
        }
        if lower.contains("sign in") || lower.contains("login required") || lower.contains("log in") || lower.contains("members-only")
            || lower.contains("--cookies") || lower.contains("requires authentication") || lower.contains("age-restricted") || lower.contains("confirm your age") {
            return f(.loginRequired, "You need to be signed in",
                     "The site only shows this to signed-in viewers. Digby can use your browser’s sign-in for this site if you allow it.")
        }
        if lower.contains("not available in your country") || lower.contains("geo restrict") || lower.contains("geo-restrict") || lower.contains("not available from your location") {
            return f(.geoRestricted, "Not available in your region",
                     "The site doesn’t offer this video where you are. Digby doesn’t work around regional restrictions.")
        }
        if lower.contains("http error 429") || lower.contains("too many requests") || lower.contains("rate limit") || lower.contains("rate-limit") {
            return f(.rateLimited, "The site asked Digby to slow down",
                     "Too many requests in a short time. Digby will wait and try again, one download at a time.", retry: true)
        }
        if lower.contains("ip may be blocked") || lower.contains("data center") || lower.contains("vpn") {
            return f(.blocked, "The site is blocking your network",
                     "It refuses connections from your network’s address. This is common on VPNs (like Astrill), because many people share the same address. Opening the page in Digby and passing any check there usually works.",
                     retry: true, update: true)
        }
        if lower.contains("http error 403") || lower.contains("forbidden") {
            return f(.blocked, "The site refused Digby",
                     "It answered “forbidden” (error 403). Sites do this to keep out VPNs and download programs, or because they want an “Are you human?” check first. Opening the page in Digby usually gets past it.",
                     retry: true, update: true)
        }
        if lower.contains("will begin in") || lower.contains("premieres in") || lower.contains("live event will begin") || lower.contains("this live stream recording is not available") {
            var u = f(.unavailable, "This live stream hasn’t started yet",
                      "Digby downloads videos once they exist. Try this link again when the stream has started and ended; most sites keep the recording.")
            u.noPageRoutes = true
            return u
        }
        if lower.contains("video unavailable") || lower.contains("has been removed") || lower.contains("http error 404") || lower.contains("does not exist")
            || lower.contains("no longer available") || lower.contains("not found") {
            return f(.unavailable, "This video isn’t available",
                     "It may have been removed, made private, or the link may be incomplete.")
        }
        if lower.contains("unsupported url") {
            return f(.unsupportedSite, "Digby can’t download from this page",
                     "The link doesn’t point to media Digby recognises. Try the video’s own page rather than a home page or search result.")
        }
        if lower.contains("requested format is not available") || lower.contains("format not available") {
            return f(.unsupportedFormat, "That format is no longer offered",
                     "The site changed what it offers since the link was analysed. Analyse it again to see the current choices.", retry: true)
        }
        if lower.contains("no space left") || lower.contains("disk quota") {
            return f(.diskFull, "Your disk is full", "Free up some space, then try again.")
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") || lower.contains("read-only file system") {
            return f(.permissions, "Digby can’t save there", "It doesn’t have permission to write to the download folder. Choose another folder in Settings.")
        }
        if lower.contains("js runtime") || lower.contains("javascript") || lower.contains("deno") || lower.contains("n challenge") || lower.contains("challenge solving") {
            return f(.jsRuntime, "A protection puzzle couldn’t be solved",
                     "The site’s player changed. Digby will check for an updated engine and try again.", retry: true, update: true)
        }
        if lower.contains("unable to extract") || lower.contains("unable to download webpage") || lower.contains("please report this issue")
            || lower.contains("no video formats found") || lower.contains("keyerror") || lower.contains("regexnotfound") {
            return f(.outdatedExtractor, "The website seems to have changed",
                     "The page works differently than the extraction engine expects. This happens every few weeks; an engine update usually fixes it.",
                     retry: true, update: true)
        }
        if lower.contains("timed out") || lower.contains("connection reset") || lower.contains("network is unreachable") || lower.contains("temporary failure in name resolution")
            || lower.contains("nodename nor servname") || lower.contains("urlopen error") || lower.contains("incomplete read") || lower.contains("connection refused") {
            return f(.network, "The connection dropped",
                     "Check you’re online. Digby will try again and continue where it stopped.", retry: true)
        }
        return f(.unknown, "Something went wrong",
                 "The download engine reported a problem Digby doesn’t recognise. The diagnostic report has the details.", retry: true, update: true)
    }

    /// The engine often can't tell "this page doesn't exist" from "this page changed" (both read as "unable to
    /// extract"). The page's own HTTP status can: a 404/410 means there's nothing to download, not a site change.
    public static func missingPage(status: Int, after f: Failure) -> Failure? {
        guard [404, 410].contains(status), [.outdatedExtractor, .unknown, .unsupportedFormat, .jsRuntime].contains(f.kind) else { return nil }
        var m = Failure(kind: .unavailable, title: "This page doesn’t exist",
                        explanation: "The site says there’s nothing at this address (error \(status)). Check the link is complete; the video may have been deleted or moved.",
                        retryable: false, suggestsEngineUpdate: false, detail: f.detail)
        m.noPageRoutes = true
        return m
    }

    /// A stream that's live right now: Digby downloads finished videos, not live recordings (yet).
    public static func liveNow(detail: String = "") -> Failure {
        var f = Failure(kind: .unavailable, title: "This is live right now",
                        explanation: "Digby downloads finished videos. Most sites keep the recording when the stream ends; try this link again then.",
                        retryable: false, suggestsEngineUpdate: false, detail: detail)
        f.noPageRoutes = true
        return f
    }

    public static func cancelled() -> Failure {
        Failure(kind: .cancelled, title: "Cancelled", explanation: "Nothing half-finished was kept.", retryable: false, suggestsEngineUpdate: false, detail: "")
    }
}
