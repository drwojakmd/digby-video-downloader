import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// Advanced Mode: every stream the site offers, searchable and sortable. Clicking a row picks that
/// exact stream; Digby still checks it fits the chosen file type and says what happens to it.
struct AdvancedFormatTable: View {
    @Bindable var analysis: Analysis
    var plan: DownloadPlan?
    @State private var search = ""
    @State private var sort: Column = .resolution
    @State private var ascending = false

    enum Column: String, CaseIterable {
        case id = "ID", kind = "Type", resolution = "Resolution", codec = "Format", fps = "Frame rate", range = "Range",
             bitrate = "Bitrate", size = "Size", language = "Language", ext = "File"
        var width: CGFloat {
            switch self {
            case .id: 52; case .kind: 64; case .resolution: 92; case .codec: 64; case .fps: 66; case .range: 50
            case .bitrate: 76; case .size: 74; case .language: 92; case .ext: 44
            }
        }
    }

    var rows: [MediaFormat] {
        let all = analysis.catalogue.video + analysis.catalogue.audio
        let q = search.lowercased()
        let filtered = q.isEmpty ? all : all.filter { f in
            [f.id, f.ext, f.videoCodec?.name, f.audioCodec?.name, f.tier?.name, f.language.map { Languages.name($0) }]
                .compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
        return filtered.sorted { a, b in
            let r = compare(a, b)
            return r == .orderedSame ? a.id < b.id : (ascending ? r == .orderedAscending : r == .orderedDescending)
        }
    }

    func compare(_ a: MediaFormat, _ b: MediaFormat) -> ComparisonResult {
        func c<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult { x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }
        switch sort {
        case .id: return c(a.id, b.id)
        case .kind: return c(kind(a), kind(b))
        case .resolution: return c((a.height ?? 0) * 10_000 + Int(a.totalBitrate ?? 0), (b.height ?? 0) * 10_000 + Int(b.totalBitrate ?? 0))
        case .codec: return c(codecName(a), codecName(b))
        case .fps: return c(a.fps ?? 0, b.fps ?? 0)
        case .range: return c(a.dynamicRange.rawValue, b.dynamicRange.rawValue)
        case .bitrate: return c(a.totalBitrate ?? 0, b.totalBitrate ?? 0)
        case .size: return c(a.fileSize ?? 0, b.fileSize ?? 0)
        case .language: return c(a.language ?? "", b.language ?? "")
        case .ext: return c(a.ext, b.ext)
        }
    }

    func kind(_ f: MediaFormat) -> String { f.hasVideo && f.hasAudio ? "Both" : f.hasVideo ? "Picture" : "Sound" }
    func codecName(_ f: MediaFormat) -> String { f.hasVideo ? f.videoCodec?.name ?? "?" : f.audioCodec?.name ?? "?" }

    var body: some View {
        Card(padding: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Every format", systemImage: "tablecells")
                    Text("\(rows.count) streams. Click one to choose it yourself; Digby still checks it fits your file type.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if analysis.choices.manualVideoID != nil || analysis.choices.manualAudioID != nil {
                    Button("Back to Automatic") { analysis.choices.manualVideoID = nil; analysis.choices.manualAudioID = nil }
                        .buttonStyle(QuietButtonStyle())
                }
                SearchField(text: $search, prompt: "Filter: av1, 1080p, Spanish…").frame(width: 200)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Column.allCases, id: \.self) { col in
                            Button {
                                if sort == col { ascending.toggle() } else { sort = col; ascending = col == .id || col == .language || col == .ext }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(col.rawValue)
                                    if sort == col { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                                }
                                .frame(width: col.width, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    Divider()
                    ForEach(rows) { f in
                        let chosen = f.id == plan?.video?.id || f.id == plan?.audio?.id
                        Button {
                            if f.hasVideo { analysis.choices.manualVideoID = f.id } else { analysis.choices.manualAudioID = f.id }
                        } label: {
                            HStack(spacing: 0) {
                                cell(f.id, .id, mono: true)
                                cell(kind(f), .kind)
                                cell(f.width.map { "\($0)×\(f.height ?? 0)" } ?? "—", .resolution, mono: true)
                                cell(codecName(f), .codec)
                                cell(f.fps.map { Fmt.fps($0) } ?? "—", .fps)
                                cell(f.hasVideo ? (f.dynamicRange.isHDR ? "HDR" : "SDR") : "—", .range)
                                cell(f.totalBitrate.map { "\(Int($0)) kb/s" } ?? "—", .bitrate, mono: true)
                                cell(f.fileSize.map { (f.fileSizeIsExact ? "" : "≈ ") + Fmt.bytes($0) } ?? "—", .size, mono: true)
                                cell(f.language.map { Languages.name($0) + (f.audioRole == .dubbed ? " (dub)" : "") } ?? "—", .language)
                                cell(f.ext, .ext)
                            }
                            .padding(.vertical, 4.5).padding(.horizontal, 8)
                            .background(chosen ? Brand.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(kind(f)) stream \(f.id), \(codecName(f)), \(f.tier?.name ?? "")\(chosen ? ", selected" : "")")
                    }
                }
            }
        }
    }

    func cell(_ s: String, _ col: Column, mono: Bool = false) -> some View {
        Text(s).font(.system(size: 11.5, design: mono ? .monospaced : .default)).lineLimit(1)
            .frame(width: col.width, alignment: .leading)
    }
}

/// A rounded search field drawn in SwiftUI.
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).imageScale(.small)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.callout)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.09)))
    }
}
