import SwiftUI
import DigbyDesign
import DigbyDownloadCore

struct MediaPreviewCard: View {
    @Environment(AppModel.self) private var model
    var media: MediaInfo
    var catalogue: FormatCatalogue
    @State private var showDescription = false

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                Thumbnail(url: media.thumbnailURL, seed: media.id)
                    .frame(width: 192, height: 108)
                    .overlay(alignment: .bottomTrailing) {
                        if let d = media.duration {
                            Text(Fmt.duration(d)).font(.caption2.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(media.title).font(TypeStyle.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        if let u = media.uploader { Text(u).foregroundStyle(.secondary); Text("·").foregroundStyle(.secondary) }
                        SourceLink(site: media.site, url: media.webpageURL)
                    }
                    .font(.callout)
                    FlowLayout(spacing: 6) {
                        if let top = catalogue.tiers.first { Chip("Up to \(top.name)", systemImage: "rectangle.on.rectangle") }
                        if catalogue.hasHDR { Chip("HDR", systemImage: "sun.max") }
                        if let fps = catalogue.highestFrameRate, fps > 31 { Chip(Fmt.fps(fps), systemImage: "speedometer") }
                        if catalogue.languages.count > 1 { Chip("\(catalogue.languages.count) languages", systemImage: "globe") }
                        if !catalogue.humanSubtitles.isEmpty || !catalogue.automaticSubtitles.isEmpty {
                            Chip("Subtitles", systemImage: "captions.bubble")
                        }
                        if media.chapterCount > 0 { Chip("\(media.chapterCount) chapters", systemImage: "list.bullet") }
                    }
                    .padding(.top, 2)
                }
            }
            if let e = model.alreadyDownloaded(media), let file = e.file {
                HStack(spacing: 10) {
                    InfoRow("You already downloaded this \(e.date.formatted(.relative(presentation: .named))) (\(e.detail)). Downloading again makes a second copy.",
                            systemImage: "checkmark.circle.fill", tint: Brand.good)
                    Spacer(minLength: 8)
                    Button("Show in Finder") { model.reveal(file) }.buttonStyle(QuietButtonStyle())
                }
            }
            if let n = media.notice {
                let good = n.hasPrefix("Fixed")
                InfoRow(n, systemImage: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill", tint: good ? Brand.good : Brand.warn)
            }
            if media.engineURL == nil {
                Button { model.findOnPage(media.webpageURL) } label: {
                    Label("Not what the page shows? Find the video on the page", systemImage: "scope").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain).foregroundStyle(Brand.accent)
                .help("Opens the page in Digby’s browser; play the video and Digby catches exactly that")
            }
            if let d = media.description, !d.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(showDescription ? nil : 1)
                    Button(showDescription ? "Show less" : "Show description") { showDescription.toggle() }
                        .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Thumbnail with a calm placeholder (sample data has no image; real thumbnails load from the site).
struct Thumbnail: View {
    var url: URL?
    var seed: String
    /// The downloaded file, if any: its own frame is used when the site's picture is unavailable.
    var file: URL? = nil
    @State private var loaded: NSImage?

    /// Always exactly the frame it's given: the whole picture shown over a soft blur of itself, so tall
    /// (phone) or unusual pictures never spill over their surroundings. Pictures come from `ThumbnailStore`,
    /// so anything seen before appears at once.
    var body: some View {
        let image = loaded ?? ThumbnailStore.shared.immediate(url: url, file: file)
        Color.clear
            .overlay {
                if let image {
                    ZStack {
                        Image(nsImage: image).resizable().scaledToFill().blur(radius: 14).opacity(0.85)
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                    .transition(.opacity)
                } else { placeholder }
            }
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Metrics.thumbnailRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.thumbnailRadius, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: ThumbnailStore.key(url: url, file: nil).map { $0 + (file?.path ?? "") } ?? file?.path ?? "") {
            loaded = nil
            guard url != nil || file != nil, ThumbnailStore.shared.immediate(url: url, file: file) == nil else { return }
            loaded = await ThumbnailStore.shared.load(url: url, file: file)
        }
    }

    var placeholder: some View {
        let hue = Double(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 100) / 100   // stable across launches
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hue: 0.62, saturation: 0.55, brightness: 0.32), Color(hue: 0.6 + hue * 0.05, saturation: 0.35, brightness: 0.7),
                                  Color(hue: 0.06, saturation: 0.35, brightness: 0.95)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            var far = Path(); far.move(to: CGPoint(x: 0, y: h * 0.72))
            far.addLine(to: CGPoint(x: w * 0.22, y: h * 0.5)); far.addLine(to: CGPoint(x: w * 0.38, y: h * 0.64))
            far.addLine(to: CGPoint(x: w * 0.6, y: h * 0.42)); far.addLine(to: CGPoint(x: w * 0.82, y: h * 0.62))
            far.addLine(to: CGPoint(x: w, y: h * 0.55)); far.addLine(to: CGPoint(x: w, y: h)); far.addLine(to: CGPoint(x: 0, y: h))
            ctx.fill(far, with: .color(Color(hue: 0.63, saturation: 0.45, brightness: 0.35).opacity(0.75)))
            var near = Path(); near.move(to: CGPoint(x: 0, y: h * 0.86))
            near.addLine(to: CGPoint(x: w * 0.3, y: h * 0.68)); near.addLine(to: CGPoint(x: w * 0.55, y: h * 0.84))
            near.addLine(to: CGPoint(x: w * 0.75, y: h * 0.7)); near.addLine(to: CGPoint(x: w, y: h * 0.88))
            near.addLine(to: CGPoint(x: w, y: h)); near.addLine(to: CGPoint(x: 0, y: h))
            ctx.fill(near, with: .color(Color(hue: 0.64, saturation: 0.5, brightness: 0.18)))
        }
    }
}
