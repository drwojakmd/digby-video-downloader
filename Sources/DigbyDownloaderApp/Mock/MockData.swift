import Foundation
import DigbyDownloadCore

/// Design-phase stand-ins for the queue, history and engines. Replaced by real data in Phases 3–5.
enum MockData {
    @MainActor static func populate(_ m: AppModel) {
        let movies = NSHomeDirectory() + "/Movies/Digby/"
        m.queue = [
            QueueItem(title: "Reading the sky: tomorrow’s weather today", site: "YouTube", summary: "1080p · H.264 · AAC · MP4",
                      size: SizeEstimate(bytes: 248_000_000, isExact: true),
                      state: .downloading(fraction: 0.62, speed: 9_400_000, remaining: 11)),
            QueueItem(title: "Mountain Weather, Explained", site: "YouTube", summary: "Playlist · 1080p · MP4",
                      state: .downloading(fraction: nil, speed: 0, remaining: nil), children: [
                        QueueItem(title: "Why clouds form above mountains", site: "YouTube", summary: "1080p · MP4",
                                  size: SizeEstimate(bytes: 201_000_000, isExact: true), state: .done(URL(fileURLWithPath: movies + "a.mp4"))),
                        QueueItem(title: "Temperature inversions: the sea of clouds", site: "YouTube", summary: "1080p · MP4",
                                  size: SizeEstimate(bytes: 233_000_000, isExact: true), state: .processing("Merging picture and sound")),
                        QueueItem(title: "Föhn winds and lenticular clouds", site: "YouTube", summary: "1080p · MP4",
                                  state: .failed("This video is private")),
                        QueueItem(title: "Noctilucent clouds at midsummer", site: "YouTube", summary: "1080p · MP4", state: .waiting),
                      ]),
            QueueItem(title: "Morning Fog, Short Film", site: "Vimeo", summary: "1080p · H.264 · MP4",
                      size: SizeEstimate(bytes: 112_000_000, isExact: false), state: .waiting),
            QueueItem(title: "Studio session — live recording", site: "SoundCloud", summary: "Audio · Original (Opus)",
                      size: SizeEstimate(bytes: 54_000_000, isExact: true), state: .paused(0.31)),
            QueueItem(title: "Above the Clouds — A Year of Light", site: "YouTube", summary: "4K · AV1 · AAC · MP4",
                      size: SizeEstimate(bytes: 1_260_000_000, isExact: true), state: .done(URL(fileURLWithPath: movies + "b.mp4"))),
        ]
        do {   // the first download carries real details, as a planned one does
            var ch = Choices(); ch.resolution = .tier(.p1080)
            let cat = FormatCatalogue(SampleMedia.video)
            if let p = FormatSelector.select(cat, ch, playback: m.playback).plan {
                m.queue[0].details = DownloadDetails.make(catalogue: cat, choices: ch, plan: p)
                m.queue[0].work = .planned(DownloadRequest(media: SampleMedia.video, plan: p, folder: m.videoFolder,
                                                           fileName: FileNamer.render(m.nameTemplate, media: SampleMedia.video, plan: p)))
            }
        }
        m.settings.folderSorting = .month
        let kids = Project(name: "Kids’ Cartoons", folder: movies + "Kids’ Cartoons", symbol: "figure.and.child.holdinghands")
        m.settings.projects = [kids, Project(name: "Weather Talk Research", folder: movies + "Weather Talk Research", symbol: "graduationcap.fill")]
        m.watches = [Watch(url: URL(string: "https://www.youtube.com/@highlandskies/videos")!, title: "Highland Skies Studio", site: "YouTube",
                           choices: { var c = Choices(); c.resolution = .tier(.p1080); return c }(), projectID: nil, known: ["a"],
                           lastChecked: Date().addingTimeInterval(-2400), downloadedCount: 4),
                     Watch(url: URL(string: "https://www.youtube.com/playlist?list=cartoons")!, title: "Saturday Morning Cartoons", site: "YouTube",
                           choices: Choices(), projectID: kids.id, known: ["b"], lastChecked: Date().addingTimeInterval(-9000), downloadedCount: 12)]
        let day: TimeInterval = 86_400, now = Date()
        m.history = [
            HistoryEntry(title: "Above the Clouds — A Year of Light", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=x1")!,
                          date: now.addingTimeInterval(-600), file: URL(fileURLWithPath: movies + "Above the Clouds.mp4"),
                          kind: .videoAndAudio, detail: "4K · AV1 · MP4", bytes: 1_260_000_000, succeeded: true),
            HistoryEntry(title: "Why clouds form above mountains", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=e1")!,
                          date: now.addingTimeInterval(-3_000), file: URL(fileURLWithPath: movies + "Why clouds form.mp4"),
                          kind: .videoAndAudio, detail: "1080p · H.264 · MP4", bytes: 201_000_000, succeeded: true),
            HistoryEntry(title: "The Little Cloud Who Couldn’t Rain — Episode 4", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=k4")!,
                          date: now.addingTimeInterval(-4_000), file: URL(fileURLWithPath: movies + "Kids’ Cartoons/Episode 4.mp4"),
                          kind: .videoAndAudio, detail: "1080p · H.264 · MP4", bytes: 180_000_000, succeeded: true),
            HistoryEntry(title: "The Little Cloud Who Couldn’t Rain — Episode 3", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=k3")!,
                          date: now.addingTimeInterval(-day * 9), file: URL(fileURLWithPath: movies + "Kids’ Cartoons/Episode 3.mp4"),
                          kind: .videoAndAudio, detail: "1080p · H.264 · MP4", bytes: 176_000_000, succeeded: true),
            HistoryEntry(title: "Ambient piano for focus", site: "Bandcamp", url: URL(string: "https://bandcamp.com/x")!,
                          date: now.addingTimeInterval(-day), file: URL(fileURLWithPath: NSHomeDirectory() + "/Music/Digby/Ambient piano.flac"),
                          kind: .audioOnly, detail: "Audio · FLAC", bytes: 312_000_000, succeeded: true),
            HistoryEntry(title: "City timelapse at night", site: "Vimeo", url: URL(string: "https://vimeo.com/1")!,
                          date: now.addingTimeInterval(-day * 3), file: URL(fileURLWithPath: movies + "City timelapse.mkv"),
                          kind: .videoAndAudio, detail: "4K · VP9 · MKV", bytes: 2_040_000_000, succeeded: true),
            HistoryEntry(title: "Föhn winds and lenticular clouds", site: "YouTube", url: URL(string: "https://youtube.com/watch?v=e4")!,
                          date: now.addingTimeInterval(-day * 40), file: nil,
                          kind: .videoAndAudio, detail: "Private video", bytes: 0, succeeded: false),
        ]
        m.engines = [
            EngineStatus(name: "yt-dlp", role: "Finds and downloads the video on each website", installed: "2026.10.26",
                         latest: "2026.10.26", state: .upToDate, lastChecked: now.addingTimeInterval(-3_600)),
            EngineStatus(name: "Deno", role: "Solves the puzzles some sites (like YouTube) use to protect their streams", installed: "2.9.8",
                         latest: "2.9.8", state: .upToDate, lastChecked: now.addingTimeInterval(-3_600)),
            EngineStatus(name: "FFmpeg", role: "Joins picture and sound into one file, and converts when you ask", installed: "9.0.1",
                         latest: "9.0.2", state: .updateAvailable, lastChecked: now.addingTimeInterval(-3_600)),
        ]
        m.engineHistory = [UpdateRecord(date: now.addingTimeInterval(-day * 2), tool: .ytdlp, from: "2026.10.09", to: "2026.10.26", outcome: "installed")]
        func tries(_ site: String, ok: Int, _ fails: [Failure.Kind], engine: String = "2026.10.26") -> [SiteAttempt] {
            (0..<ok).map { SiteAttempt(site: site, date: now.addingTimeInterval(-Double($0) * 3_600), succeeded: true, engine: engine) }
                + fails.map { SiteAttempt(site: site, date: now.addingTimeInterval(-day), succeeded: false, failure: $0, engine: engine) }
        }
        m.mockSiteAttempts = tries("youtube.com", ok: 41, [.botCheck, .botCheck, .outdatedExtractor]) + tries("archive.org", ok: 12, [])
            + tries("vimeo.com", ok: 3, [.botCheck, .botCheck, .botCheck, .blocked]) + tries("bbc.co.uk", ok: 5, [.geoRestricted])
            + tries("commons.wikimedia.org", ok: 4, [])
    }

    static let privateDiagnosis = Diagnosis(
        kind: .privateMedia, title: "This video is private",
        explanation: "Its owner has limited who can watch it. Digby can only download videos you can open in your browser. If you can watch it while signed in, turn on “Use my browser’s sign-in for this site”.",
        whatDigbyDid: [("Checked the link opens a real video page", true), ("Confirmed the extraction engine is up to date (2026.10.26)", true)],
        inProgress: false, actions: ["Use My Browser’s Sign-in", "Open in Browser", "Copy Report"])

    static let outdatedDiagnosis = Diagnosis(
        kind: .outdatedExtractor, title: "The website seems to have changed",
        explanation: "Your download couldn’t start because the site’s page works differently than the extraction engine expects. This happens every few weeks; an update usually fixes it.",
        whatDigbyDid: [("Recognised the problem", true), ("Checking for an updated extraction engine", false), ("Trying again", false)],
        inProgress: true, actions: [])

    static let rateLimitedDiagnosis = Diagnosis(
        kind: .rateLimited, title: "The site asked Digby to slow down",
        explanation: "Too many requests were made in a short time, so the site paused downloads. Digby will try again in 5 minutes, one video at a time.",
        whatDigbyDid: [("Paused the queue for this site", true), ("Will retry at 14:35", false)],
        inProgress: false, actions: ["Retry Now", "Copy Report"])
}
