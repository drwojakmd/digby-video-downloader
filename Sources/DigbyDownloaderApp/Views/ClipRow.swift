import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// "Part of the video": download only the moments you want. Drag the two handles, type the times, or pick a
/// chapter. The rest never downloads.
struct ClipRow: View {
    @Bindable var analysis: Analysis
    var duration: Double
    var chapters: [MediaInfo.Chapter]

    var clip: ClipRange? { analysis.choices.clip }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChoiceRow(title: "Part of the video", symbol: "scissors", explanation: explanation) {
                PillButton("Whole video", selected: clip == nil) { analysis.choices.clip = nil }
                PillButton("Only a part", detail: clip.map { $0.label } , selected: clip != nil,
                           help: "Choose a start and end; only that part downloads") {
                    if clip == nil { analysis.choices.clip = ClipRange(start: 0, end: duration) }
                }
            }
            if let c = clip {
                VStack(alignment: .leading, spacing: 12) {
                    RangeSlider(start: binding(\.start), end: binding(\.end), total: duration, marks: chapters.map(\.start).filter { $0 > 0 })
                        .frame(height: 24)
                    HStack(spacing: 12) {
                        TimeField(label: "From", value: binding(\.start), range: 0...max(0, c.end - 1))
                        TimeField(label: "To", value: binding(\.end), range: min(duration, c.start + 1)...duration)
                        Text("Length \(Fmt.duration(c.length))").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if !chapters.isEmpty {
                            Menu {
                                ForEach(Array(chapters.enumerated()), id: \.offset) { i, ch in
                                    Button("\(i + 1). \(ch.title)  (\(Fmt.duration(ch.start))–\(Fmt.duration(ch.end)))") {
                                        set(ClipRange(start: ch.start, end: ch.end, exact: c.exact))
                                    }
                                }
                            } label: { Label("Chapters", systemImage: "list.bullet") }
                                .menuStyle(.borderlessButton).fixedSize()
                                .help("Pick a chapter to download just that part")
                        }
                    }
                    HStack(spacing: 7) {
                        PillButton("Quick cut", detail: "Nearest key frame", selected: !c.exact,
                                   help: "Fast, no quality change. May begin a few seconds before your start time.") { set(with(c) { $0.exact = false }) }
                        PillButton("Exact cut", detail: "To the frame", selected: c.exact,
                                   help: "Starts and ends on the exact moments. Re-encodes this part at high quality, so it takes a little longer.") { set(with(c) { $0.exact = true }) }
                    }
                }
                .padding(.leading, 2)
            }
        }
    }

    var explanation: Explanation {
        guard let c = clip else {
            return Explanation("The whole video downloads.", pros: [], cons: [])
        }
        return c.exact
            ? Explanation("Only \(c.label) downloads, cut on the exact frames.", pros: ["Starts and ends exactly where you chose"], cons: ["That part’s picture is re-encoded (a little slower, very slightly softer)"])
            : Explanation("Only \(c.label) downloads; the rest never does.", pros: ["Fast, and the picture is untouched"], cons: ["May begin a few seconds early (at the nearest key frame)"])
    }

    func binding(_ k: WritableKeyPath<ClipRange, Double>) -> Binding<Double> {
        Binding(get: { clip?[keyPath: k] ?? 0 }, set: { v in
            guard var c = clip else { return }
            c[keyPath: k] = v
            if c.end - c.start < 1 { if k == \ClipRange.start { c.start = max(0, c.end - 1) } else { c.end = min(duration, c.start + 1) } }
            analysis.choices.clip = c
        })
    }
    func set(_ c: ClipRange) { analysis.choices.clip = c }
    func with(_ c: ClipRange, _ f: (inout ClipRange) -> Void) -> ClipRange { var x = c; f(&x); return x }
}

/// Two handles on one track: the part between them is what you keep. Tick marks show chapters.
struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    var total: Double
    var marks: [Double] = []

    var body: some View {
        GeometryReader { g in
            let inset: CGFloat = 9
            let w = max(1, g.size.width - inset * 2)
            let x = { (t: Double) in inset + CGFloat(t / max(total, 1)) * w }
            let time = { (px: CGFloat) in min(total, max(0, Double((px - inset) / w) * total)) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: w, height: 6).offset(x: inset, y: 9)
                ForEach(marks, id: \.self) { m in
                    Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: 1, height: 10).offset(x: x(m), y: 7)
                }
                Capsule().fill(Brand.accent).frame(width: max(2, x(end) - x(start)), height: 6).offset(x: x(start), y: 9)
                knob.offset(x: x(start) - inset, y: 3)
                    .gesture(DragGesture(coordinateSpace: .named("range")).onChanged { v in start = min(time(v.location.x), end - 1).rounded() })
                    .accessibilityElement().accessibilityLabel("Start").accessibilityValue(Fmt.duration(start))
                    .accessibilityAdjustableAction { d in start = d == .increment ? min(start + 5, end - 1) : max(0, start - 5) }
                knob.offset(x: x(end) - inset, y: 3)
                    .gesture(DragGesture(coordinateSpace: .named("range")).onChanged { v in end = max(time(v.location.x), start + 1).rounded() })
                    .accessibilityElement().accessibilityLabel("End").accessibilityValue(Fmt.duration(end))
                    .accessibilityAdjustableAction { d in end = d == .increment ? min(total, end + 5) : max(start + 1, end - 5) }
            }
            .coordinateSpace(name: "range")
        }
    }

    var knob: some View {
        Circle().fill(Color.white).frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .overlay(Circle().strokeBorder(Brand.accent.opacity(0.6), lineWidth: 1))
            .contentShape(Circle().inset(by: -6))
    }
}

/// A time you can type: "1:20", "80" or "1:02:03".
struct TimeField: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            TextField("0:00", text: $text)
                .textFieldStyle(.roundedBorder).font(.callout.monospacedDigit()).frame(width: 74)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, f in if !f { commit() } }
        }
        .onAppear { text = Fmt.duration(value) }
        .onChange(of: value) { _, v in if !focused { text = Fmt.duration(v) } }
    }

    func commit() {
        if let t = Self.parse(text) { value = min(range.upperBound, max(range.lowerBound, t)) }
        text = Fmt.duration(value)
    }

    static func parse(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}
