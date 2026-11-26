import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// "After downloading": keep the file as it is, or have Digby Video Compressor make it smaller straight away.
/// The choice is remembered for every later download (it lives in Settings).
struct CompressAfterRow: View {
    @Environment(AppModel.self) private var model
    /// The download this applies to (size and picture format), for the size estimates. nil: no estimates (playlists).
    var downloadBytes: Int64? = nil
    var codec: VideoCodec? = nil

    var body: some View {
        @Bindable var model = model
        let c = model.compressAfter
        let installed = model.compressorInstalled
        let on = c.on && installed
        VStack(alignment: .leading, spacing: 14) {
            ChoiceRow(title: "After downloading", symbol: "rectangle.compress.vertical", explanation: explanation(on: on, installed: installed)) {
                PillButton("Keep as Downloaded", detail: "As the site sent it", selected: !on) { model.compressAfter.on = false }
                PillButton("Compress with Digby", detail: !installed ? "Not installed" : (downloadBytes.flatMap { b in c.size.estimate(downloadBytes: b, codec: codec) }.map(CompressAfter.rangeLabel) ?? "A smaller file"), selected: on, enabled: installed,
                           help: installed ? "Digby Video Compressor starts on it as soon as it's downloaded"
                                           : "Install Digby Video Compressor to use this") { model.compressAfter.on = true }
            }
            if on {
                ChoiceRow(title: "How small", symbol: "dial.medium", explanation: sizeExplanation(c)) {
                    ForEach(CompressAfter.Size.allCases) { s in
                        PillButton(s.label, detail: detail(s, c), selected: c.size == s, help: s.blurb) { model.compressAfter.size = s }
                    }
                }
                if c.size == .fitSize {
                    HStack(spacing: 8) {
                        Text("Aim for").foregroundStyle(.secondary)
                        TextField("MB", value: $model.compressAfter.targetMB, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        Text("MB").foregroundStyle(.secondary)
                        Stepper("", value: $model.compressAfter.targetMB, in: 1...100_000, step: 25).labelsHidden()
                    }
                    .font(.callout)
                }
                Toggle(isOn: Binding(get: { !model.compressAfter.keepOriginal }, set: { model.compressAfter.keepOriginal = !$0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move the big download to the Trash when the smaller copy is ready")
                        Text("Only once the smaller copy has been made and checked. You can still get the big one back from the Trash.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    /// The likely size under each option ("≈ 150–250 MB"), when this download's size is known.
    func detail(_ s: CompressAfter.Size, _ c: CompressAfter) -> String? {
        if s == .fitSize { return "About \(c.targetMB) MB" }
        if s == .compressorSettings { return downloadBytes == nil ? nil : "Size varies" }
        guard let b = downloadBytes, let r = s.estimate(downloadBytes: b, codec: codec) else { return nil }
        return CompressAfter.rangeLabel(r)
    }

    func sizeExplanation(_ c: CompressAfter) -> Explanation {
        guard let b = downloadBytes else { return Explanation(c.size.blurb) }
        return Explanation(c.size.blurb + " Sizes are a rough guide from this \(Fmt.bytes(b)) download.",
                           pros: ["Digby Video Compressor measures the real size once it has the file"],
                           cons: ["Busy, detailed footage stays bigger than these ranges; talks, slides and cartoons often end up smaller",
                                  "If it can't save much, the Compressor keeps the original as it is"])
    }

    func explanation(on: Bool, installed: Bool) -> Explanation {
        if !installed {
            return Explanation("Digby Video Compressor can make downloads much smaller with no visible loss. Install it to use this.")
        }
        if on {
            return Explanation("Digby Video Compressor shrinks each video as soon as it's downloaded, in the background, and checks the result still plays properly.",
                               pros: ["Saves disk space with no extra steps", "Remembered for your next downloads"],
                               cons: ["Your Mac works for a while after each download"])
        }
        return Explanation("The file stays exactly as the site sent it. You can still compress it later from Downloaded.")
    }
}

extension CompressionRecord {
    var tint: Color {
        switch state {
        case .done: Brand.good
        case .sent, .compressing: Brand.accent
        case .skipped: .secondary
        case .failed, .cancelled: Brand.warn
        }
    }
}
