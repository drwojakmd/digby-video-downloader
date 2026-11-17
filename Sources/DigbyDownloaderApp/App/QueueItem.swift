import Foundation
import DigbyDownloadCore

/// A queued download (or a playlist group of them). Holds its own settings snapshot, so changing
/// defaults never alters it.
@Observable final class QueueItem: Identifiable {
    enum State: Equatable {
        case waiting
        case analysing
        case downloading(fraction: Double?, speed: Double, remaining: Double?)
        case processing(String)
        case verifying
        case paused(Double)
        case done(URL)
        case failed(String)
        case cancelled
    }
    let id = UUID()
    var title: String
    var site: String
    var summary: String
    var size: SizeEstimate?
    var state: State
    var children: [QueueItem]
    var isPlaylist: Bool { !children.isEmpty }
    /// The picture to show for this download (the site's thumbnail, once known).
    var thumbnail: URL? { media?.thumbnailURL ?? children.first?.media?.thumbnailURL ?? entryThumbnail }
    var entryThumbnail: URL?

    /// What to do: an already planned download, or a link (playlist entry) to analyse and plan when its turn comes.
    enum Work {
        case planned(DownloadRequest)
        case unplanned(url: URL, choices: Choices, playlist: String?, index: Int)
    }
    var work: Work?
    var token = CancelToken()
    var failure: Failure?
    var notes: [String] = []
    var phase: String = ""
    var media: MediaInfo?
    var startedAt: Date?
    var choices: Choices?
    var attempts = 0
    /// The original, the choices and (once done) the verified result: shown in Details, saved with History.
    var details: DownloadDetails?
    var engineUpdateTried = false
    /// Names the hidden work folder, so Pause/Resume (and restarts) continue the same partial download.
    var workID = String(UUID().uuidString.prefix(8))
    /// Saved into this folder instead of the usual one (a project's folder).
    var destination: URL?
    /// Waits for the overnight hours before starting.
    var overnight = false

    init(title: String, site: String, summary: String, size: SizeEstimate? = nil, state: State = .waiting, children: [QueueItem] = []) {
        self.title = title; self.site = site; self.summary = summary; self.size = size; self.state = state; self.children = children
    }

    var isActive: Bool {
        switch state { case .downloading, .processing, .verifying, .analysing: true; default: false }
    }
    var fraction: Double? {
        switch state {
        case .downloading(let f, _, _): f
        case .paused(let f): f
        case .done: 1
        case .processing, .verifying: 1
        default: nil
        }
    }
    /// Playlist progress: finished children over all children.
    var groupFraction: Double {
        guard !children.isEmpty else { return fraction ?? 0 }
        return children.reduce(0) { $0 + ($1.fraction ?? 0) } / Double(children.count)
    }
    var doneCount: Int { children.filter { if case .done = $0.state { true } else { false } }.count }
    var failedCount: Int { children.filter { if case .failed = $0.state { true } else { false } }.count }
}

/// One pasted link in New Download: analysing, ready, downloading, done or failed. Several can exist at once.
@Observable final class Draft: Identifiable {
    let id = UUID()
    let url: URL
    var state: ComposerState
    var title: String?
    /// The project this link was opened for (new links follow the project you're in).
    var projectID: String?
    let token = CancelToken()
    init(url: URL, state: ComposerState) { self.url = url; self.state = state }
    var label: String { title ?? url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString }
}
