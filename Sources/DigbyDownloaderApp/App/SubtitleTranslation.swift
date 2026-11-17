import SwiftUI
import AppKit
import DigbyDownloadCore
import Translation

/// Subtitles translated on this Mac by macOS's own Translation (macOS 15 and later). Nothing is sent
/// anywhere: the language packs run on the Mac. The first time a language is used, macOS asks to download
/// its pack; that request appears in a small Digby window, which also shows the progress.
enum SubtitleTranslation {
    static var isAvailable: Bool { if #available(macOS 15, *) { return true } else { return false } }

    /// Languages offered in the menu (macOS supports these pairs with English and most with each other;
    /// an unsupported pair is said plainly when the download starts).
    static let targets = ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "uk", "tr", "ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant", "vi", "th", "id"]
    static func name(_ code: String) -> String {
        switch code { case "zh-Hans": "Chinese (Simplified)"; case "zh-Hant": "Chinese (Traditional)"; default: Languages.name(code) }
    }

    static func translator() -> SubtitleTranslator? {
        guard #available(macOS 15, *) else { return nil }
        return { srt, from, to in try await TranslationRun.translate(srt: srt, from: from, to: to) }
    }

    struct Problem: LocalizedError {
        var errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }
}

@available(macOS 15, *)
@MainActor
@Observable
final class TranslationRun {
    let source: Locale.Language
    let target: Locale.Language
    let targetName: String
    let texts: [String]
    var progress: Double = 0
    var status = "Getting ready…"
    private var continuation: CheckedContinuation<[String], Error>?

    init(texts: [String], source: Locale.Language, target: Locale.Language, targetName: String) {
        self.texts = texts; self.source = source; self.target = target; self.targetName = targetName
    }

    static func translate(srt: URL, from: String, to: String) async throws -> URL {
        let data = try Data(contentsOf: srt)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let cues = SRT.parse(text)
        guard !cues.isEmpty else { throw SubtitleTranslation.Problem("the subtitles were empty") }
        let src = Locale.Language(identifier: from), dst = Locale.Language(identifier: to)
        let availability = await LanguageAvailability().status(from: src, to: dst)
        if availability == .unsupported {
            throw SubtitleTranslation.Problem("macOS can’t translate \(Languages.name(from)) into \(SubtitleTranslation.name(to))")
        }
        let run = TranslationRun(texts: cues.map(\.plainText), source: src, target: dst, targetName: SubtitleTranslation.name(to))
        let translated = try await run.start()
        var out = cues
        for i in out.indices where i < translated.count && !translated[i].isEmpty { out[i].text = translated[i] }
        let file = srt.deletingLastPathComponent().appendingPathComponent("translated.\(to).srt")
        try SRT.write(out).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Shows the small window that hosts the translation (and macOS's language-pack request), then waits.
    private func start() async throws -> [String] {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                            styleMask: [.titled, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Translating Subtitles"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: TranslationRunView(run: self))
        if let main = NSApp.windows.first(where: { $0.title.contains("Digby") && $0.isVisible }) {
            let f = main.frame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 380, y: f.maxY - 200))
        } else { panel.center() }
        panel.orderFrontRegardless()
        defer { panel.close() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func perform(_ session: TranslationSession) async {
        do {
            status = "Checking macOS has the \(targetName) language pack…"
            try await session.prepareTranslation()
            var out = Array(repeating: "", count: texts.count)
            let indices = texts.indices.filter { !texts[$0].isEmpty }
            status = "Translating \(indices.count) lines into \(targetName)…"
            for chunk in stride(from: 0, to: indices.count, by: 40) {
                let slice = indices[chunk..<min(chunk + 40, indices.count)]
                let requests = slice.map { TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0)) }
                for r in try await session.translations(from: requests) {
                    if let id = r.clientIdentifier.flatMap(Int.init), id < out.count { out[id] = r.targetText }
                }
                progress = Double(min(chunk + 40, indices.count)) / Double(max(1, indices.count))
            }
            continuation?.resume(returning: out)
        } catch {
            continuation?.resume(throwing: SubtitleTranslation.Problem(error.localizedDescription))
        }
        continuation = nil
    }
}

@available(macOS 15, *)
private struct TranslationRunView: View {
    let run: TranslationRun
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "character.bubble").font(.title2).foregroundStyle(Color.accentColor)
                Text("Translating subtitles into \(run.targetName)").font(.headline)
            }
            ProgressView(value: run.progress)
            Text(run.status).font(.callout).foregroundStyle(.secondary)
            Text("On this Mac, by macOS. Nothing is sent anywhere.").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 360)
        .onAppear { configuration = .init(source: run.source, target: run.target) }
        .translationTask(configuration) { session in await run.perform(session) }
    }
}
