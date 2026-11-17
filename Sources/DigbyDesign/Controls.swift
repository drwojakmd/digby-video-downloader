import SwiftUI
import AppKit

/// Rounded, softly outlined container for every section (same construction as the Compressor's `Card`).
public struct Card<Content: View>: View {
    var padding: CGFloat
    var content: Content
    public init(padding: CGFloat = Metrics.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

public struct SectionLabel: View {
    var title: String
    var systemImage: String?
    public init(_ title: String, systemImage: String? = nil) { self.title = title; self.systemImage = systemImage }
    public var body: some View {
        HStack(spacing: 5) {
            if let s = systemImage { Image(systemName: s) }
            Text(title)
        }
        .font(TypeStyle.sectionLabel)
        .textCase(.uppercase)
        .kerning(0.3)
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
    }
}

public struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color
    public init(_ text: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.text = text; self.systemImage = systemImage; self.tint = tint
    }
    public var body: some View {
        HStack(spacing: 4) {
            if let s = systemImage { Image(systemName: s).imageScale(.small) }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

/// A selectable option. `title` is the plain-English name ("Full HD"), `detail` the technical
/// name or figure ("1080p", "≈ 312 MB"). Unavailable options are not drawn at all; `enabled == false`
/// is only for options that exist but need something else first.
public struct PillButton: View {
    var title: String
    var detail: String?
    var selected: Bool
    var enabled: Bool
    var help: String?
    var action: () -> Void
    @State private var hover = false

    public init(_ title: String, detail: String? = nil, selected: Bool, enabled: Bool = true, help: String? = nil,
                action: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.selected = selected; self.enabled = enabled; self.help = help; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1).fixedSize()
                if let detail {
                    Text(detail).font(.system(size: 10.5)).monospacedDigit()
                        .opacity(selected ? 0.85 : 0.6)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, detail == nil ? 6 : 5)
            .frame(minWidth: 54)
            .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(RoundedRectangle(cornerRadius: detail == nil ? 20 : 9, style: .continuous)
                .fill(selected ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(hover ? 0.16 : 0.09))))
            .contentShape(Rectangle())
            .opacity(enabled || selected ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !selected)
        .onHover { hover = $0 }
        .help(help ?? "")
        .animation(.easeOut(duration: 0.12), value: selected)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row of pills that wraps onto further lines when the window is narrow.
public struct FlowLayout: Layout {
    var spacing: CGFloat
    public init(spacing: CGFloat = 8) { self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// The primary call to action (same as the Compressor's).
public struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1).fixedSize()          // a button's words never break across lines
            .padding(.horizontal, 22).padding(.vertical, 10)
            .foregroundStyle(Color.white)
            .background(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                .fill(enabled ? AnyShapeStyle(Brand.buttonGradient) : AnyShapeStyle(Color.gray.opacity(0.35))))
            .shadow(color: Brand.accent.opacity(enabled ? 0.28 : 0), radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Secondary action: quiet tinted capsule.
public struct QuietButtonStyle: ButtonStyle {
    var tint: Color
    public init(tint: Color = Brand.accent) { self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1).fixedSize()          // a button's words never break across lines
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(configuration.isPressed ? 0.2 : 0.1)))
    }
}

/// A small round icon button for rows (Pause, Resume, Details…); the help text says what it does.
public struct RoundIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hover = false
    public init(_ symbol: String, help: String, action: @escaping () -> Void) { self.symbol = symbol; self.help = help; self.action = action }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
                .background(Circle().fill(Color.secondary.opacity(hover ? 0.18 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hover = $0 }
    }
}

public struct InfoRow: View {
    var systemImage: String
    var text: String
    var tint: Color
    public init(_ text: String, systemImage: String, tint: Color = .secondary) {
        self.text = text; self.systemImage = systemImage; self.tint = tint
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint).frame(width: 16)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
