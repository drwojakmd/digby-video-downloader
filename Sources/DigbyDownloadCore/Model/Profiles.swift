import Foundation

/// A named set of choices. Built-ins can't be deleted; user profiles are stored with the settings.
public struct DownloadProfile: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var symbol: String
    public var choices: Choices
    public var embedMetadata: Bool
    public var embedChapters: Bool
    public var isBuiltIn: Bool

    public init(id: String, name: String, summary: String, symbol: String, choices: Choices,
                embedMetadata: Bool = true, embedChapters: Bool = true, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.summary = summary; self.symbol = symbol; self.choices = choices
        self.embedMetadata = embedMetadata; self.embedChapters = embedChapters; self.isBuiltIn = isBuiltIn
    }

    public static let maximumQuality = DownloadProfile(
        id: "max", name: "Maximum Quality", summary: "The sharpest picture and best sound offered, copied without conversion.",
        symbol: "sparkles", choices: { var c = Choices(); c.container = .mkv; c.preferPlayableOnThisMac = false; return c }(),
        embedMetadata: true, embedChapters: true, isBuiltIn: true)
    public static let universal = DownloadProfile(
        id: "universal", name: "Universal Compatibility", summary: "MP4 with H.264 and AAC: plays on practically any device.",
        symbol: "checkmark.seal", choices: { var c = Choices(); c.codec = .specific(.avc); c.container = .mp4; return c }(),
        embedMetadata: true, embedChapters: true, isBuiltIn: true)
    public static let archive = DownloadProfile(
        id: "archive", name: "Archive", summary: "Highest quality, original sound, chapters, metadata and every subtitle in one MKV.",
        symbol: "archivebox", choices: { var c = Choices(); c.container = .mkv; c.preferPlayableOnThisMac = false
            c.subtitles = SubtitleChoice(mode: .embed, all: true); return c }(),
        embedMetadata: true, embedChapters: true, isBuiltIn: true)
    public static let audioArchive = DownloadProfile(
        id: "audio-archive", name: "Audio Archive", summary: "The best sound, kept as it is (or as FLAC if you prefer a lossless library).",
        symbol: "waveform", choices: { var c = Choices(); c.kind = .audioOnly; c.audioOutput = .original; return c }(),
        embedMetadata: true, embedChapters: true, isBuiltIn: true)
    public static let smallFile = DownloadProfile(
        id: "small", name: "Small File", summary: "720p in an efficient format, for phones and saving space.",
        symbol: "arrow.down.right.and.arrow.up.left", choices: { var c = Choices(); c.resolution = .tier(.p720); return c }(),
        embedMetadata: true, embedChapters: false, isBuiltIn: true)

    public static let builtIns = [maximumQuality, universal, archive, audioArchive, smallFile]
}
