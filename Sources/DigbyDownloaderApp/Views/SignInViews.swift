import SwiftUI
import WebKit
import DigbyDesign
import DigbyDownloadCore

/// Explains why a sign-in helps, and sets one up: borrow a browser's sign-in, or sign in inside Digby.
struct SignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var site: SignInSite
    var retry: URL?
    @State private var browser: Browser = Browser.systemDefault.flatMap { $0.isInstalled ? $0 : nil } ?? .chrome
    @State private var working = false
    @State private var everywhere = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key").font(.system(size: 26)).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use your \(site.displayName) sign-in").font(TypeStyle.title)
                    Text("\(site.displayName) checks for robots more strictly on VPNs and shared networks. Downloading as you, signed in, solves this.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Card {
                SectionLabel("Recommended", systemImage: "star")
                HStack {
                    Picker("Browser you’re signed in with", selection: $browser) {
                        ForEach(Browser.allCases.filter(\.isInstalled), id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Use \(browser.displayName)") { useBrowser() }.buttonStyle(ProminentButtonStyle()).disabled(working)
                }
                InfoRow(browser.permissionNote, systemImage: "info.circle")
                Toggle(isOn: $everywhere) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also use it for any other site that turns Digby away")
                        Text("Digby tries once more as you, only after a site refuses, and only sends each site its own cookies.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Card {
                SectionLabel("Or", systemImage: "macwindow")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in inside Digby").font(.callout.weight(.semibold))
                        Text("A separate sign-in just for Digby, like Downie’s. Your browser isn’t touched.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Sign-in Window") { SignInWindow.show(site: site) { ok in if ok { finish() } } }.buttonStyle(QuietButtonStyle())
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                InfoRow("With your browser’s sign-in, Digby reads it fresh for each download and stores nothing. A sign-in made inside Digby is kept on this Mac, readable only by you. Either way it’s sent only to \(site.displayName) and Google’s sign-in service.", systemImage: "lock.shield", tint: Brand.good)
                InfoRow("Digby never sees or stores your password. Remove it any time in Settings → Privacy.", systemImage: "hand.raised", tint: .secondary)
            }
            HStack { Spacer(); Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 560)
    }

    func useBrowser() {
        var s = SignInSettings.load()
        s.sites[site] = .browser(browser)
        if everywhere { s.anySite = browser }
        try? FileManager.default.removeItem(at: SignInStore.jar(for: site))
        try? s.save()
        finish()
    }

    func finish() {
        model.refreshSignIns()
        dismiss()
        if let retry { model.urlText = retry.absoluteString; model.analyse() }
    }
}

/// Digby's own sign-in window (a private web view, nothing shared with your browsers). When the
/// site shows you as signed in, the site's cookies are saved to Digby's sign-in file and the window closes.
enum SignInWindow {
    @MainActor static var window: NSWindow?
    @MainActor static func show(site: SignInSite, done: @escaping (Bool) -> Void) {
        let store = WKWebsiteDataStore.nonPersistent()
        let finish: (Bool) -> Void = { ok in window?.close(); window = nil; done(ok) }
        let controller = NSHostingController(rootView: VStack(spacing: 0) {
            SignInWebView(site: site, store: store, done: finish)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(Brand.good)
                Text(site.isYouTubeSite ? "Sign in as usual; this window closes by itself when you’re done."
                                        : "Sign in as usual, then click I’m Signed In. Digby keeps only \(site.displayName)’s cookies.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !site.isYouTubeSite {
                    Button("I’m Signed In") {
                        store.httpCookieStore.getAllCookies { cookies in
                            var s = SignInSettings.load(); s.sites[site] = .digbyWindow
                            let ok = (try? SignInStore.write(cookies, for: site)) != nil && (try? s.save()) != nil
                            Task { @MainActor in finish(ok) }
                        }
                    }
                    .buttonStyle(ProminentButtonStyle())
                }
            }
            .padding(12)
        })
        let w = NSWindow(contentViewController: controller)
        w.title = "Sign in to \(site.displayName) — Digby"
        w.setContentSize(NSSize(width: 520, height: 700))
        w.styleMask = [.titled, .closable, .resizable]
        w.isReleasedWhenClosed = false
        window = w
        w.center(); w.makeKeyAndOrderFront(nil)
    }
}

struct SignInWebView: NSViewRepresentable {
    var site: SignInSite
    var store: WKWebsiteDataStore
    var done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(site: site, done: done) }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store                     // private; nothing kept beyond the saved sign-in file
        let v = WKWebView(frame: .zero, configuration: cfg)
        // Google refuses sign-in in apps that identify as embedded browsers; present as Safari.
        v.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: site.signInPage))
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let site: SignInSite; let done: (Bool) -> Void; var finished = false
        init(site: SignInSite, done: @escaping (Bool) -> Void) { self.site = site; self.done = done }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished, let host = webView.url?.host, host.hasSuffix("youtube.com") else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                // Signed in once YouTube has issued its login cookie.
                guard cookies.contains(where: { $0.name == "LOGIN_INFO" || $0.name == "__Secure-3PSID" }) else { return }
                self.finished = true
                var s = SignInSettings.load(); s.sites[self.site] = .digbyWindow
                do { try SignInStore.write(cookies, for: self.site); try s.save(); Task { @MainActor in self.done(true) } }
                catch { Task { @MainActor in self.done(false) } }
            }
        }
    }
}
