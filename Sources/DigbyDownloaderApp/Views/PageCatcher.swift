import SwiftUI
import WebKit
import DigbyDesign
import DigbyDownloadCore

/// "Find the video on the page": the page opens in Digby's own browser; you play the video (signing in or
/// passing any check yourself, as in any browser) and Digby catches the stream the player loads.
@MainActor @Observable final class PageCatcher {
    let startURL: URL
    var currentURL: URL
    var title: String?
    var thumbnail: URL?
    var siteName: String?
    var streams: [CaughtStream] = []
    var loading = true
    var canGoBack = false
    var canGoForward = false
    weak var webView: WKWebView?
    /// Why the page didn't load, in plain words (nil while loading or loaded).
    var loadProblem: LoadProblem?
    private var seen = Set<String>()

    struct LoadProblem: Equatable {
        var title: String
        var detail: String
        /// The site went round in circles: almost always a saved sign-in that has gone stale.
        var redirectLoop: Bool
    }

    /// A failed page load, explained. Nil for the harmless "load was replaced by another" cases.
    static func problem(for error: Error, site: String) -> LoadProblem? {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return nil }
        if e.domain == "WebKitErrorDomain" && [102, 204].contains(e.code) { return nil }   // interrupted by policy / plug-in handled
        switch (e.domain, e.code) {
        case (NSURLErrorDomain, NSURLErrorHTTPTooManyRedirects):
            return LoadProblem(title: "\(site) keeps sending the page back and forth",
                               detail: "This usually means a sign-in saved in Digby’s browser has gone stale. Clearing what Digby’s browser keeps for \(site) fixes it; you may need to sign in again.",
                               redirectLoop: true)
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet), (NSURLErrorDomain, NSURLErrorNetworkConnectionLost):
            return LoadProblem(title: "No internet connection", detail: "Check your connection or VPN, then reload.", redirectLoop: false)
        case (NSURLErrorDomain, NSURLErrorTimedOut), (NSURLErrorDomain, NSURLErrorCannotConnectToHost), (NSURLErrorDomain, NSURLErrorCannotFindHost):
            return LoadProblem(title: "\(site) didn’t answer", detail: "The site may be blocked on this network or slow right now. Check your VPN, then reload.", redirectLoop: false)
        case (NSURLErrorDomain, let c) where (-1206 ... -1200).contains(c):
            return LoadProblem(title: "The secure connection to \(site) failed", detail: "Something between this Mac and the site (often a VPN or network filter) interfered with the connection.", redirectLoop: false)
        default:
            return LoadProblem(title: "The page didn’t load", detail: e.localizedDescription, redirectLoop: false)
        }
    }

    /// Forgets only what Digby's browser keeps for this page's site (sign-in, cookies, storage), then reloads.
    func clearSiteAndReload() async {
        let store = Self.dataStore, site = SiteKey.of(startURL) ?? (startURL.host ?? "")
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let mine = records.filter { r in r.displayName == site || r.displayName.hasSuffix("." + site) }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: mine)
        loadProblem = nil
        webView?.load(URLRequest(url: startURL))
    }
    /// Playlists still being read (to tell a master playlist from a single quality).
    var pending = 0

    /// One private, persistent browser profile for Digby: sign-ins and site checks are remembered between
    /// uses, and nothing is shared with your other browsers.
    static let dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "C1A0D0E5-0000-4C1A-9D0E-C1A0D0E50001")!)
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    init(url: URL) { startURL = url; currentURL = url }

    var best: CaughtStream? { CaughtStream.best(streams) }

    /// A request the page made, reported by the watcher script.
    func noticed(_ raw: String) {
        guard var url = URL(string: raw) else { return }
        if let whole = CaughtStream.wholeFile(url) { url = whole }        // a piece → the file it belongs to
        let key = url.absoluteString
        guard !seen.contains(key), var kind = CaughtStream.classify(url) else { return }
        seen.insert(key)
        var s = CaughtStream(url: url, kind: kind)
        streams.append(s)
        let page = currentURL
        pending += 1
        Task {
            defer { pending -= 1 }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
            if kind == .stream, url.path.lowercased().hasSuffix(".m3u8") || url.query?.contains("m3u8") == true {
                if let (d, _) = try? await URLSession.shared.data(for: req) {
                    let info = CaughtStream.inspectPlaylist(String(decoding: d.prefix(200_000), as: UTF8.self))
                    if info.isMaster { kind = .adaptive }
                    s.kind = kind; s.maxHeight = info.maxHeight ?? s.maxHeight
                }
            } else if kind == .file || kind == .audio {
                req.httpMethod = "HEAD"
                if let (_, r) = try? await URLSession.shared.data(for: req), let n = (r as? HTTPURLResponse)?.expectedContentLength, n > 0 { s.bytes = n }
            }
            if let i = streams.firstIndex(where: { $0.id == s.id }) { streams[i] = s }
            // A master playlist makes its own quality playlists redundant: keep the list short.
            if streams.contains(where: { $0.kind == .adaptive }) { streams.removeAll { $0.kind == .stream && $0.url.host == url.host && $0.id != s.id && kind == .adaptive } }
        }
    }

    /// The player's own source address when it has no telling extension (e.g. "/api/video/123/src"): follow it,
    /// read what the server says it is, and catch the real stream or file behind it.
    func noticedElement(_ raw: String) {
        guard let url = URL(string: raw), CaughtStream.classify(url) == nil, !seen.contains("element:" + raw) else { return }
        seen.insert("element:" + raw)
        let page = currentURL
        pending += 1
        Task {
            defer { pending -= 1 }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
            req.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
            if let cookies = await Self.dataStore.httpCookieStore.allCookies().filter({ c in SignInSite.site(for: url)?.keeps(domain: c.domain) == true }) as [HTTPCookie]?,
               !cookies.isEmpty { HTTPCookie.requestHeaderFields(with: cookies).forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) } }
            guard let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), let final = http.url else { return }
            let mime = http.value(forHTTPHeaderField: "Content-Type")
            guard var kind = CaughtStream.classify(mimeType: mime) ?? CaughtStream.classify(final) else { return }
            var s = CaughtStream(url: final, kind: kind)
            if kind == .stream {
                let info = CaughtStream.inspectPlaylist(String(decoding: data.prefix(200_000), as: UTF8.self))
                if info.isMaster { kind = .adaptive }
                s.kind = kind; s.maxHeight = info.maxHeight
            } else if let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                s.bytes = total
            }
            guard !seen.contains(final.absoluteString) else { return }
            seen.insert(final.absoluteString)
            streams.append(s)
        }
    }

    /// The playing video's size, to label whole files.
    func playing(src: String?, width: Int, height: Int) {
        guard height > 0 else { return }
        if let src, let i = streams.firstIndex(where: { $0.url.absoluteString == src }) { streams[i].maxHeight = height }
        else if let i = streams.firstIndex(where: { $0.kind == .file && $0.maxHeight == nil }) { streams[i].maxHeight = height }
    }

    /// The page's cookies for the page's and the stream's sites, as a private cookie file for the engine.
    func cookieFile(for stream: CaughtStream) async -> URL? { await Self.cookieFile(for: [currentURL, stream.url]) }

    /// Digby's browser cookies for the given addresses' sites only, as a private cookie file (nil if none).
    static func cookieFile(for urls: [URL]) async -> URL? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let sites = urls.compactMap { SignInSite.site(for: $0) }
        let mine = cookies.filter { c in sites.contains { $0.keeps(domain: c.domain) } }
        guard !mine.isEmpty else { return nil }
        let f = Paths.home.appendingPathComponent("Sign-in/page-\(UUID().uuidString.prefix(8)).txt")
        var lines = ["# Netscape HTTP Cookie File"]
        for c in mine {
            let d = (c.domain.hasPrefix(".") ? "" : ".") + c.domain
            let exp = Int(c.expiresDate?.timeIntervalSince1970 ?? Date().addingTimeInterval(86_400).timeIntervalSince1970)
            lines.append([(c.isHTTPOnly ? "#HttpOnly_" : "") + d, "TRUE", c.path, c.isSecure ? "TRUE" : "FALSE", "\(exp)", c.name, c.value].joined(separator: "\t"))
        }
        try? Paths.ensure(f.deletingLastPathComponent())
        guard (try? (lines.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8)) != nil else { return nil }
        chmod(f.path, 0o600)
        return f
    }

    /// Reads the page's title, picture and site name now (a page that keeps streaming may never "finish" loading).
    func refreshMeta() async {
        guard let w = webView else { return }
        if let u = w.url { currentURL = u }
        if let meta = try? await w.evaluateJavaScript(Self.metaScript) as? [String: Any] {
            if let t = meta["title"] as? String, !t.isEmpty { title = t }
            if let i = (meta["image"] as? String).flatMap({ URL(string: $0, relativeTo: w.url)?.absoluteURL }) { thumbnail = i }
            if let n = meta["site"] as? String, !n.isEmpty { siteName = n }
        }
        if title == nil, let t = w.title, !t.isEmpty { title = t }
    }

    /// The page itself, with this browser's session for its site.
    func sessionPage() async -> CaughtPage {
        await refreshMeta()
        return CaughtPage(pageURL: currentURL, title: title, thumbnail: thumbnail, siteName: siteName,
                          userAgent: Self.userAgent, cookieFile: await Self.cookieFile(for: [currentURL]))
    }
    /// A remembered session for a link's site, if the person has used it in Digby's browser before.
    static func rememberedSession(for url: URL) async -> CaughtPage? {
        guard let f = await cookieFile(for: [url]) else { return nil }
        return CaughtPage(pageURL: url, title: nil, thumbnail: nil, siteName: nil, userAgent: userAgent, cookieFile: f)
    }

    func page(for stream: CaughtStream) async -> CaughtPage {
        await refreshMeta()
        return CaughtPage(pageURL: currentURL, title: title, thumbnail: thumbnail, siteName: siteName,
                   userAgent: Self.userAgent, cookieFile: await cookieFile(for: stream))
    }

    /// Removes everything the Digby browser remembers (sign-ins, site checks, caches).
    static func forgetEverything() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    /// Watches what the page loads, in every frame, from the start: playlist and file addresses only.
    static let watcherScript = #"""
    (() => {
      const media = /\.(m3u8|mpd|mp4|m4v|webm|mov|m4a|mp3|ogg|opus)(\?|#|$)/i;
      const send = (u) => { try { if (!u || typeof u !== 'string' || u.startsWith('blob:') || u.startsWith('data:')) return;
        const abs = new URL(u, location.href).href; if (media.test(abs) || /m3u8/i.test(abs)) window.webkit.messageHandlers.digbyCatch.postMessage({url: abs}); } catch (e) {} };
      try { new PerformanceObserver(l => l.getEntries().forEach(e => send(e.name))).observe({type: 'resource', buffered: true}); } catch (e) {}
      const f = window.fetch; if (f) window.fetch = function (i) { try { send(typeof i === 'string' ? i : i && i.url); } catch (e) {} return f.apply(this, arguments); };
      const o = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function (m, u) { try { send(String(u)); } catch (e) {} return o.apply(this, arguments); };
      const seen = (e) => { const v = e.target; if (!v || !('videoWidth' in v || 'currentSrc' in v)) return; send(v.currentSrc || v.src);
        try { const s = v.currentSrc || v.src; if (s && !s.startsWith('blob:') && !s.startsWith('data:')) window.webkit.messageHandlers.digbyCatch.postMessage({element: new URL(s, location.href).href}); } catch (e) {}
        try { window.webkit.messageHandlers.digbyCatch.postMessage({playing: v.currentSrc || v.src || '', w: v.videoWidth || 0, h: v.videoHeight || 0}); } catch (e) {} };
      ['play', 'playing', 'loadedmetadata'].forEach(t => document.addEventListener(t, seen, true));
      // Addresses written into the page itself (video/source attributes, known upload endpoints): the player may
      // switch to a streaming playlist and never "play" them, yet they're often the complete file.
      const post = (s) => { try { if (s && !s.startsWith('blob:') && !s.startsWith('data:')) window.webkit.messageHandlers.digbyCatch.postMessage({element: new URL(s, location.href).href}); } catch (e) {} };
      const scan = () => { try {
        document.querySelectorAll('video,source,[data-src],[data-video-src]').forEach(el => ['src', 'data-src', 'data-video-src'].forEach(a => post(el.getAttribute && el.getAttribute(a))));
        (document.documentElement.innerHTML.match(/\/api\/v1\/video\/upload\/[0-9a-f-]+\/src[^"'\s<]*/g) || []).slice(0, 4).forEach(p => post(p.replace(/&amp;/g, '&')));
      } catch (e) {} };
      let scans = 0; const iv = setInterval(() => { scan(); if (++scans > 15) clearInterval(iv); }, 2000);
      document.addEventListener('DOMContentLoaded', scan);
    })();
    """#
    static let metaScript = #"""
    (() => { const m = n => { const e = document.querySelector(`meta[property="${n}"],meta[name="${n}"]`); return e ? e.content : null; };
      return {title: m('og:title') || m('twitter:title') || document.title, image: m('og:image') || m('twitter:image'), site: m('og:site_name')}; })()
    """#
}

/// The catcher's window: browser on top, the catch tray below.
struct PageCatcherView: View {
    @Environment(AppModel.self) private var model
    @Bindable var catcher: PageCatcher
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The caught videos you've ticked.
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { catcher.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!catcher.canGoBack).help("Back")
                Button { catcher.webView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!catcher.canGoForward).help("Forward")
                Button { catcher.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    Text(catcher.currentURL.host ?? catcher.currentURL.absoluteString).lineLimit(1)
                    if catcher.loading { ProgressView().controlSize(.mini) }
                }
                .font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider()
            CatcherWebView(catcher: catcher)
                .overlay { if let p = catcher.loadProblem { problemCard(p) } }
            Divider()
            tray
        }
        .frame(minWidth: 820, minHeight: 640)
    }

    /// Shown over the page when it couldn't load, with the fix that fits.
    func problemCard(_ p: PageCatcher.LoadProblem) -> some View {
        let site = SiteKey.of(catcher.startURL) ?? "this site"
        return ZStack {
            Color(nsColor: .windowBackgroundColor)
            Card(padding: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: p.redirectLoop ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                        .font(.system(size: 22)).foregroundStyle(Brand.warn).frame(width: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.title).font(TypeStyle.title)
                        Text(p.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            if p.redirectLoop {
                                Button("Clear \(site) in Digby’s Browser and Reload") { Task { await catcher.clearSiteAndReload() } }
                                    .buttonStyle(ProminentButtonStyle())
                                    .help("Removes only what Digby’s browser keeps for \(site): its sign-in, cookies and stored data. Other sites and your own browsers aren’t touched.")
                                Button("Reload") { catcher.loadProblem = nil; catcher.webView?.load(URLRequest(url: catcher.startURL)) }
                                    .buttonStyle(QuietButtonStyle())
                            } else {
                                Button("Reload") { catcher.loadProblem = nil; catcher.webView?.load(URLRequest(url: catcher.startURL)) }
                                    .buttonStyle(ProminentButtonStyle())
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(24)
        }
    }

    /// What was caught, best first.
    var sortedStreams: [CaughtStream] {
        catcher.streams.sorted { a, b in a.kind != b.kind ? a.kind < b.kind : (a.maxHeight ?? 0) > (b.maxHeight ?? 0) }
    }

    /// Step 1 is always "play the video"; what was caught appears below it to tick (one or several). Reading the
    /// page again with this window's sign-in is the fallback, at the bottom, for when nothing gets caught.
    @ViewBuilder var tray: some View {
        VStack(alignment: .leading, spacing: 0) {
            if catcher.streams.isEmpty { playStep } else { caughtList }
            Divider().padding(.horizontal, 16)
            readAgainRow
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The most dependable video is ticked for you; tick others too if you're not sure which is the one.
        .onChange(of: catcher.streams.count, initial: true) { _, _ in
            if selected.isEmpty, let b = catcher.best { selected = [b.id] }
        }
    }

    var playStep: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.skyGradient)
                LandfallView(progress: 1, drift: !reduceMotion, color: .white, pointColor: Brand.dawnFixed, count: 5)
                    .padding(.horizontal, 8).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(width: 92, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text("Play the video").font(TypeStyle.headline)
                Text("Press play on the page above. Digby catches the video as soon as it starts and lists it here. If the page asks you to sign in or prove you’re human, do that first: this window remembers it next time.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
    }

    var caughtList: some View {
        let streams = sortedStreams
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Caught on this page: tick one or more", systemImage: "scope")
                Spacer(minLength: 8)
                Text("Keep playing, or play other videos, to catch more.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(streams) { s in caughtRow(s) }
                }
            }
            .frame(maxHeight: streams.count > 4 ? 220 : nil)
            .fixedSize(horizontal: false, vertical: streams.count <= 4)
            HStack(spacing: 10) {
                Text(selected.isEmpty ? "Tick the videos you want." : "Each ticked video opens as its own tab in New Download, where you choose the quality.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if streams.count > 1 {
                    Button(selected.count == streams.count ? "Untick All" : "Tick All") {
                        selected = selected.count == streams.count ? [] : Set(streams.map(\.id))
                    }
                    .buttonStyle(QuietButtonStyle(tint: .secondary))
                }
                Button(selected.count > 1 ? "Use \(selected.count) Videos" : "Use This Video") { useSelected() }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(selected.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    func caughtRow(_ s: CaughtStream) -> some View {
        let on = selected.contains(s.id)
        return Button {
            if on { selected.remove(s.id) } else { selected.insert(s.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 16))
                    .foregroundStyle(on ? Brand.accent : .secondary)
                Image(systemName: s.kind == .audio ? "waveform" : s.kind == .file ? "film" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(Brand.accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(s.label).font(.callout.weight(.semibold))
                        if s.id == catcher.best?.id { Chip("Best guess", tint: Brand.good) }
                    }
                    Text("\(s.explanation) · \(s.url.host ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Brand.accent.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The fallback: no playing needed. For pages that turned Digby away until you signed in or passed a check here.
    var readAgainRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.key").foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(catcher.streams.isEmpty ? "Video won’t play, or nothing gets caught?" : "None of these is right?").font(.callout.weight(.semibold))
                Text("Sign in or pass the page’s check here, then let Digby read the page again as you. No need to play anything; you’ll get the usual choices.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Read Page Again as Me") { usePage() }
                .buttonStyle(QuietButtonStyle())
                .help("Digby reads this page’s address again, using what you’ve done in this window (signed in, passed a check), just like your browser would")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    func usePage() {
        Task { @MainActor in
            let page = await catcher.sessionPage()
            let fallback = catcher.streams
            var pages: [CaughtPage] = []
            for s in fallback.prefix(3) { pages.append(await catcher.page(for: s)) }
            model.analyse(pageWithSession: page, fallback: Array(zip(fallback.prefix(3), pages)))
            close()
        }
    }

    /// Every ticked video opens as its own tab (the best one shown first).
    func useSelected() {
        let chosen = sortedStreams.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        Task { @MainActor in
            for (i, s) in chosen.enumerated() {
                let page = await catcher.page(for: s)
                model.analyse(caught: s, on: page, replacing: i == 0, label: chosen.count > 1 ? s.label : nil, focus: i == 0)
            }
            close()
        }
    }
}

struct CatcherWebView: NSViewRepresentable {
    var catcher: PageCatcher
    func makeCoordinator() -> Coordinator { Coordinator(catcher) }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = PageCatcher.dataStore
        cfg.userContentController.addUserScript(WKUserScript(source: PageCatcher.watcherScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController.add(context.coordinator, name: "digbyCatch")
        cfg.preferences.isElementFullscreenEnabled = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = PageCatcher.userAgent
        v.navigationDelegate = context.coordinator
        v.uiDelegate = context.coordinator
        v.allowsBackForwardNavigationGestures = true
        catcher.webView = v
        v.load(URLRequest(url: catcher.startURL))
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
    static func dismantleNSView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "digbyCatch")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let catcher: PageCatcher
        init(_ c: PageCatcher) { catcher = c }
        func userContentController(_ u: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            Task { @MainActor in
                if let url = body["url"] as? String { catcher.noticed(url) }
                if let el = body["element"] as? String { catcher.noticedElement(el) }
                if let w = body["w"] as? Int, let h = body["h"] as? Int { catcher.playing(src: body["playing"] as? String, width: w, height: h) }
            }
        }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { Task { @MainActor in catcher.loading = true; catcher.loadProblem = nil } }
        /// The page never arrived (redirect loop, no connection, blocked): stop the spinner and say why.
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
            Task { @MainActor in
                catcher.loading = w.isLoading
                if let p = PageCatcher.problem(for: e, site: SiteKey.of(catcher.startURL) ?? (catcher.startURL.host ?? "The site")) { catcher.loadProblem = p }
            }
        }
        /// App links (fb://, intent://, itms://) can't open here; the page carries on without them.
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let scheme = a.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(["http", "https", "about", "blob", "data", "javascript"].contains(scheme) || scheme.isEmpty ? .allow : .cancel)
        }
        /// Links and sign-in windows that would open a new window open here instead.
        func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
            if a.targetFrame == nil { w.load(a.request) }
            return nil
        }
        func webViewWebContentProcessDidTerminate(_ w: WKWebView) { w.reload() }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            Task { @MainActor in
                catcher.loading = false
                catcher.currentURL = w.url ?? catcher.currentURL
                catcher.canGoBack = w.canGoBack; catcher.canGoForward = w.canGoForward
                if let meta = try? await w.evaluateJavaScript(PageCatcher.metaScript) as? [String: Any] {
                    catcher.title = (meta["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? w.title
                    catcher.thumbnail = (meta["image"] as? String).flatMap { URL(string: $0, relativeTo: w.url)?.absoluteURL }
                    catcher.siteName = meta["site"] as? String
                }
            }
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { Task { @MainActor in catcher.loading = w.isLoading } }
    }
}

enum PageCatcherWindow {
    @MainActor static var window: NSWindow?
    @MainActor static weak var current: PageCatcher?
    @MainActor static var closeObserver: NSObjectProtocol?

    /// Stops sound and picture at once and frees the page, so nothing keeps playing after the window goes.
    @MainActor static func silence(_ catcher: PageCatcher?) {
        guard let web = catcher?.webView else { return }
        web.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(v=>{try{v.pause();v.muted=true;}catch(e){}})", completionHandler: nil)
        web.pauseAllMediaPlayback(completionHandler: nil)
        web.closeAllMediaPresentations(completionHandler: nil)
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)
    }

    @MainActor static func show(_ url: URL, model: AppModel) {
        window?.close()
        let catcher = PageCatcher(url: url)
        current = catcher
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Find the Video — Digby"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: PageCatcherView(catcher: catcher) { [weak w] in w?.close() }.environment(model))
        w.setContentSize(NSSize(width: 1060, height: 780))
        window = w
        if let o = closeObserver { NotificationCenter.default.removeObserver(o) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak catcher] _ in
            MainActor.assumeIsolated {
                silence(catcher)
                w.contentViewController = nil
                if window === w { window = nil }
            }
        }
        w.center(); w.makeKeyAndOrderFront(nil)
    }
}

/// The automatic version: the catcher runs invisibly (off-screen), starts the page's video muted, and returns
/// what it caught. Used when the engine can't read a page, before asking the person to do anything.
enum HiddenCatch {
    static let nudgeScript = #"""
    (() => {
      document.querySelectorAll('video,audio').forEach(v => { try { v.muted = true; const p = v.play && v.play(); p && p.catch && p.catch(() => {}); } catch (e) {} });
      const looksLikePlay = el => /(^|\b)play(\b|$)/i.test([el.getAttribute('aria-label'), el.title, el.className && el.className.toString(), (el.textContent || '').slice(0, 20)].join(' '));
      const cand = [...document.querySelectorAll('button,[role="button"],div[class*="play" i],span[class*="play" i]')].filter(looksLikePlay).slice(0, 2);
      cand.forEach(el => { try { el.click(); } catch (e) {} });
      return cand.length;
    })()
    """#

    @MainActor static func run(_ url: URL, timeout: TimeInterval = 25) async -> ([CaughtStream], CaughtPage)? {
        let catcher = PageCatcher(url: url)
        let coordinator = CatcherWebView.Coordinator(catcher)
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = PageCatcher.dataStore
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.addUserScript(WKUserScript(source: PageCatcher.watcherScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController.add(coordinator, name: "digbyCatch")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: cfg)
        web.customUserAgent = PageCatcher.userAgent
        web.navigationDelegate = coordinator
        catcher.webView = web
        // Off-screen, never shown, never focused: just enough of a window for the page's player to run.
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.contentView = web
        window.orderFrontRegardless()
        defer {
            web.stopLoading()
            cfg.userContentController.removeScriptMessageHandler(forName: "digbyCatch")
            window.orderOut(nil); window.contentView = nil
        }
        web.load(URLRequest(url: url))
        let start = Date()
        var lastNudge = Date.distantPast, nudges = 0, firstVideoAt: Date?
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if nudges < 5, Date().timeIntervalSince(lastNudge) > 3, Date().timeIntervalSince(start) > 2 {
                _ = try? await web.evaluateJavaScript(nudgeScript); lastNudge = Date(); nudges += 1
            }
            if firstVideoAt == nil, catcher.streams.contains(where: { $0.kind != .audio }) { firstVideoAt = Date() }
            // Stop once a master playlist (every quality) is known, or a few seconds after the first stream once
            // every noticed playlist has been read.
            guard catcher.pending == 0 else { continue }
            if catcher.streams.contains(where: { $0.kind == .adaptive }) { break }
            if let t = firstVideoAt, Date().timeIntervalSince(t) > 4 { break }
        }
        withExtendedLifetime(coordinator) {}
        guard !catcher.streams.isEmpty else { return nil }
        // Best first; the caller tries the next if one turns out to be sound only.
        let ordered = catcher.streams.sorted { a, b in a.kind != b.kind ? a.kind < b.kind : (a.maxHeight ?? 0) > (b.maxHeight ?? 0) }
        return (ordered, await catcher.page(for: ordered[0]))
    }
}
