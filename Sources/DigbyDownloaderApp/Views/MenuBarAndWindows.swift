import SwiftUI
import AppKit
import DigbyDesign
import DigbyDownloadCore

/// The menu bar window: paste a link, see what's downloading.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Digby").font(TypeStyle.headline)
                Spacer()
                Text(model.activeCount > 0 ? "\(model.activeCount) downloading" : "Idle").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                model.pasteFromClipboard(); openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Download Copied Link", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
            }
            .buttonStyle(ProminentButtonStyle())
            let active = model.queue.flatMap { $0.isPlaylist ? $0.children : [$0] }.filter(\.isActive).prefix(4)
            if !active.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(active)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.callout).lineLimit(1)
                            LandfallProgress(fraction: item.fraction)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Open Digby") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Every term in plain English.
struct GlossaryView: View {
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Glossary").font(TypeStyle.title)
                Spacer()
                SearchField(text: $search, prompt: "Search").frame(width: 180)
            }
            Text("What the technical words mean, in plain English.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Glossary.terms.filter { search.isEmpty || $0.term.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) }) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.term).font(TypeStyle.headline)
                            Text(t.meaning).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .frame(width: 480, height: 540)
    }
}

enum GlossaryWindow {
    @MainActor static var window: NSWindow?
    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: GlossaryView()))
            w.title = "Digby Glossary"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            window = w
        }
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Brand.skyGradient
                LandfallView(progress: 1, color: .white, pointColor: Brand.dawnFixed).padding(.horizontal, 40).opacity(0.75)
                DigbyLockup(size: 27).frame(maxHeight: .infinity, alignment: .top).padding(.top, 44)
            }
            .frame(height: 190)
            VStack(spacing: 6) {
                Text("Anything you find. Yours to keep.").foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
                Text("© 2026 Digby · MIT licence").font(.caption).foregroundStyle(.tertiary)
                DisclosureGroup("Acknowledgements") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Digby downloads these from their publishers on first use and runs them as separate programs:")
                        Text("• yt-dlp — The Unlicense (its macOS build bundles GPLv3+ components)")
                        Text("• FFmpeg and FFprobe — GPLv3 or later (builds by Martin Riedl)")
                        Text("• Deno — MIT licence")
                        Text("Full notices: Digby Video Downloader.app/Contents/Resources/Licenses")
                    }
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                .font(.caption).padding(.top, 8)
            }
            .padding(22)
        }
        .frame(width: 380)
    }
}

enum AboutWindow {
    @MainActor static var window: NSWindow?
    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.styleMask = [.titled, .closable, .fullSizeContentView]; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
}
