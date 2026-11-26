import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// After a download: the original as the site offered it, what you chose, and what Digby checked.
struct DetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var details: DownloadDetails

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    original
                    chosen
                    result
                    if let c = details.compression { compressed(c) }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Open Page") { NSWorkspace.shared.open(details.pageURL) }
                Button("Download Again…") {
                    dismiss(); model.urlText = details.pageURL.absoluteString; model.analyse()
                }
                .help("Reads the page again so you can choose; your earlier choices aren’t changed")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 640, height: 680)
    }

    var stillGoing: Bool {
        model.leaves.contains { i in
            guard i.details?.id == details.id else { return false }
            switch i.state { case .failed, .cancelled, .done: return false; default: return true }
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Thumbnail(url: details.thumbnail, seed: details.title).frame(width: 160, height: 90)
            VStack(alignment: .leading, spacing: 5) {
                Text(details.title).font(TypeStyle.title).lineLimit(3).textSelection(.enabled)
                Text([details.uploader, details.site, details.duration.map { Fmt.duration($0) },
                      details.uploadDate?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SourceLink(site: "Open the original", url: details.pageURL).font(.callout)
                    Text(details.pageURL.absoluteString).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    var original: some View {
        Card {
            SectionLabel("What the site offered", systemImage: "square.stack.3d.up")
            if details.offered.isEmpty {
                Text("Sound only.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Resolution"); Text("Video formats"); Text("Frame rate"); Text("")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(details.offered) { o in
                        GridRow {
                            Text(o.resolution).monospacedDigit()
                            Text(o.formats.joined(separator: ", "))
                            Text(o.frameRate.map { Fmt.fps($0) } ?? "—").monospacedDigit()
                            Text(o.hdr ? "HDR available" : "").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if !details.soundLanguages.isEmpty { InfoRow("Sound: " + details.soundLanguages.joined(separator: ", "), systemImage: "speaker.wave.2") }
                if !details.subtitles.isEmpty { InfoRow("Subtitles: " + details.subtitles.joined(separator: ", "), systemImage: "captions.bubble") }
                if details.chapters > 0 { InfoRow("\(details.chapters) chapters", systemImage: "list.bullet") }
                InfoRow("\(details.formatCount) streams in total", systemImage: "tablecells")
            }
            if let d = details.description, !d.isEmpty {
                Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
            }
        }
    }

    var chosen: some View {
        Card {
            SectionLabel("What you chose", systemImage: "slider.horizontal.3")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                ForEach(details.choices) { c in
                    GridRow {
                        Text(c.label).foregroundStyle(.secondary)
                        Text(c.value)
                    }
                    .font(.callout)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(details.chips, id: \.self) { Chip($0, tint: Brand.accent) }
                if let b = details.expectedBytes { Chip((details.expectedExact ? "" : "≈ ") + Fmt.bytes(b), systemImage: "internaldrive") }
            }
            InfoRow(details.converted ? "The sound was converted to fit the file type; the picture was copied untouched."
                                      : "Picture and sound were copied exactly as the site provided them.",
                    systemImage: details.converted ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill",
                    tint: details.converted ? Brand.warn : Brand.good)
            ForEach(details.notes, id: \.self) { InfoRow($0, systemImage: "info.circle", tint: .secondary) }
            Text("Streams: \(details.streams)").font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder var result: some View {
        Card {
            SectionLabel("What you got", systemImage: "checkmark.seal")
            if let v = details.verified, let f = details.file {
                InfoRow("Checked: \(v)", systemImage: "checkmark.seal.fill", tint: Brand.good)
                HStack {
                    Text(f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let b = details.bytes { Text(Fmt.bytes(b)).font(.callout).monospacedDigit() }
                }
                if FileManager.default.fileExists(atPath: f.path) {
                    HStack {
                        Button("Show in Finder") { model.reveal(f) }.buttonStyle(QuietButtonStyle())
                        Button("Open") { NSWorkspace.shared.open(f) }.buttonStyle(QuietButtonStyle(tint: .secondary))
                    }
                } else if details.compression?.originalTrashed == true {
                    InfoRow("Replaced by the smaller copy below. This download went to the Trash.", systemImage: "trash", tint: .secondary)
                } else {
                    InfoRow("The file has been moved or deleted since.", systemImage: "questionmark.folder", tint: .secondary)
                }
                if let when = details.completedAt { Text("Downloaded \(when.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary) }
            } else if stillGoing {
                InfoRow("Still downloading. Once it finishes, Digby checks the file and the result appears here.", systemImage: "arrow.down.circle", tint: Brand.accent)
            } else {
                InfoRow("This download didn’t finish, so there’s no file.", systemImage: "xmark.circle", tint: .secondary)
            }
        }
    }

    /// What Digby Video Compressor did with it.
    @ViewBuilder func compressed(_ c: CompressionRecord) -> some View {
        Card {
            SectionLabel("Made smaller", systemImage: "rectangle.compress.vertical")
            switch c.state {
            case .sent:
                InfoRow("Sent to Digby Video Compressor (\(c.setting)). It hasn’t reported back yet.", systemImage: "paperplane", tint: Brand.accent)
            case .compressing:
                InfoRow("Digby Video Compressor is making it smaller now (\(c.setting)).", systemImage: "hourglass", tint: Brand.accent)
            case .skipped:
                InfoRow("Kept as downloaded: \(c.note ?? "compressing wouldn’t have saved enough to be worth it")", systemImage: "equal.circle", tint: .secondary)
            case .failed:
                InfoRow("Couldn’t be compressed: \(c.note ?? "Digby Video Compressor reported a problem"). The download is untouched.", systemImage: "exclamationmark.triangle.fill", tint: Brand.warn)
            case .cancelled:
                InfoRow("Compression was cancelled. The download is untouched.", systemImage: "xmark.circle", tint: .secondary)
            case .done:
                if let o = c.originalBytes, let n = c.outputBytes {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.bytes(o)).foregroundStyle(.secondary).strikethrough()
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(Fmt.bytes(n)).font(.title3.weight(.semibold))
                        if let r = c.reduction { Chip("\(Int((r * 100).rounded())) % smaller", tint: Brand.good) }
                    }
                }
                if let q = c.quality {
                    InfoRow("Quality check: \(q)" + (c.vmaf.map { String(format: " (%.0f out of 100)", $0) } ?? "") + ". " + qualityWords(q),
                            systemImage: "eye", tint: Brand.good)
                }
                Text(["Setting: \(c.setting)", c.format].compactMap { $0 }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                if let out = c.output {
                    HStack {
                        Text(out.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if FileManager.default.fileExists(atPath: out.path) {
                            Button("Show in Finder") { model.reveal(out) }.buttonStyle(QuietButtonStyle())
                            Button("Open") { NSWorkspace.shared.open(out) }.buttonStyle(QuietButtonStyle(tint: .secondary))
                        }
                    }
                }
                if c.originalTrashed {
                    InfoRow("The original download went to the Trash once the smaller copy was checked. You can still put it back from the Trash.", systemImage: "trash", tint: .secondary)
                } else {
                    InfoRow("The original download was kept" + (FileManager.default.fileExists(atPath: c.originalFile.path) ? " next to it." : ", but has since been moved or deleted.")
                            + (c.note.map { " \($0)" } ?? ""), systemImage: "doc.on.doc", tint: .secondary)
                }
            }
            Text("\(c.state == .done ? "Compressed" : "Updated") \(c.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
        }
    }

    func qualityWords(_ q: String) -> String {
        switch q {
        case "Excellent": "Looks the same as the download."
        case "Very Good": "Differences are very hard to spot."
        case "Good": "Small differences in fine detail."
        default: "Some visible loss: fine when only the content matters."
        }
    }
}
