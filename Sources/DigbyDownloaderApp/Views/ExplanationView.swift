import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// One-line plain-English meaning of the current choice, with pros and cons on request.
struct ExplanationLine: View {
    var explanation: Explanation
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(explanation.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !explanation.pros.isEmpty || !explanation.cons.isEmpty {
                    Button(open ? "Less" : "Pros & cons") { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
                        .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(Brand.accent)
                        .accessibilityHint("Shows what you gain and give up")
                }
            }
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(explanation.pros, id: \.self) { Bullet(symbol: "checkmark", tint: Brand.good, text: $0) }
                    ForEach(explanation.cons, id: \.self) { Bullet(symbol: "minus", tint: Brand.warn, text: $0) }
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
        .onChange(of: explanation.summary) { _, _ in open = false }
    }

    struct Bullet: View {
        var symbol: String; var tint: Color; var text: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint).frame(width: 10)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A labelled row of choices with its explanation underneath.
struct ChoiceRow<Content: View>: View {
    var title: String
    var symbol: String
    var explanation: Explanation?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title, systemImage: symbol)
            FlowLayout(spacing: 7) { content }
            if let explanation { ExplanationLine(explanation: explanation) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a video came from, as a link to the original page ("YouTube ↗"). The full address shows on hover.
struct SourceLink: View {
    var site: String
    var url: URL?
    var body: some View {
        if let url {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 3) {
                    Text(site.isEmpty ? (url.host ?? "Original") : site)
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                }
            }
            .buttonStyle(.plain).foregroundStyle(Brand.accent)
            .help("Open the original: \(url.absoluteString)")
            .accessibilityLabel("Open the original on \(site)")
        } else {
            Text(site)
        }
    }
}
