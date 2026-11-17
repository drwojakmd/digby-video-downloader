import SwiftUI
import AppKit
import DigbyDesign
import DigbyDownloadCore

@main
struct DigbyVideoDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Digby Video Downloader", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
                .task { DebugRender.runIfRequested(model: model); await model.start() }
                .onAppear {
                    if Bundle.main.bundleIdentifier != nil, model.notifyWhenDone { Notifier.requestPermission() }   // asked only once you turn it on
                    GlobalHotKey.register { model.pasteFromClipboard(); NSApp.activate(ignoringOtherApps: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.checkClipboard() }
                .onOpenURL { model.open($0) }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Digby Video Downloader") { AboutWindow.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Download") { model.reset(); model.section = .download }.keyboardShortcut("n")
                Button("Go to Link Field") { model.focusLinkRequest += 1 }.keyboardShortcut("l")
                Button("Download Copied Link") { model.pasteFromClipboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Find Video on Page…") {
                    if let u = AppModel.links(in: model.urlText).first ?? model.selectedDraft?.url { model.findOnPage(u) }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Downloads") {
                Button("Show Downloads") { model.section = .queue }.keyboardShortcut("1")
                Button("Show History") { model.section = .history }.keyboardShortcut("2")
                Divider()
                Button("Clear Completed") { model.clearCompleted() }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .help) {
                Button("Digby Glossary") { GlossaryWindow.show() }.keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings { SettingsView().environment(model) }

        MenuBarExtra(isInserted: Binding(get: { model.showMenuBarIcon }, set: { model.showMenuBarIcon = $0 })) {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Render and test modes quit by themselves without asking.
        if let m = AppModel.shared, m.activeCount > 0, ProcessInfo.processInfo.environment["DIGBY_DL_RENDER"] == nil {
            let alert = NSAlert()
            alert.messageText = "Stop downloading and quit?"
            alert.informativeText = "\(m.activeCount) download\(m.activeCount == 1 ? " is" : "s are") still running. What has arrived so far is kept, and Digby offers to continue next time you open it."
            alert.addButton(withTitle: "Quit"); alert.addButton(withTitle: "Keep Downloading")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unfinished downloads are remembered (their partial data kept) and no engine keeps running.
        if let m = AppModel.shared {
            m.saveQueue()
            for item in m.leaves where item.isActive { item.token.pause() }
        }
        ProcessRegistry.shared.terminateAll()
    }
}
