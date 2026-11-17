import SwiftUI

/// The Downloader's brand motif, from its icon: two chevrons coming down onto one bright line —
/// something far away, brought down to you.
///
/// `progress` 0…1 draws the line out from the middle (and lights it on arrival); `drift` lets the
/// chevrons breathe; `settled` brings them down onto the line (while a link is dragged over the window).
public struct LandfallView: View {
    public var progress: Double
    public var settled: Bool
    public var drift: Bool
    public var color: Color
    public var pointColor: Color?
    public var count: Int
    public var horizon: Bool

    public init(progress: Double = 1, settled: Bool = false, drift: Bool = false, color: Color = .white,
                pointColor: Color? = nil, count: Int = 2, horizon: Bool = true) {
        self.progress = progress; self.settled = settled; self.drift = drift; self.color = color
        self.pointColor = pointColor; self.count = count; self.horizon = horizon
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !drift)) { tl in
            let t = drift ? tl.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in Self.draw(ctx: ctx, size: size, t: t, progress: progress, settled: settled, color: color,
                                            pointColor: pointColor, count: count, horizon: horizon) }
        }
        .animation(.easeInOut(duration: 0.4), value: settled)
        .accessibilityHidden(true)
    }

    /// Where the line sits, as a fraction of the canvas.
    public static let landing = CGPoint(x: 0.5, y: 0.8)

    static func draw(ctx: GraphicsContext, size: CGSize, t: Double, progress: Double, settled: Bool, color: Color,
                     pointColor: Color?, count: Int, horizon: Bool) {
        let w = size.width, h = size.height
        let lineY = h * landing.y
        let p = max(0, min(1, progress))
        // Proportions from the icon (chevrons 388 wide, 134 deep, 84 thick, 196 apart; line 424 × 30).
        let unit = min(h / 720, w / 560)
        let halfW = 194 * unit, depth = 134 * unit, lw = max(2, 72 * unit)
        let bob = t == 0 ? 0 : (sin(t * 1.1) + 1) / 2 * 14 * unit
        let drop = settled ? 70 * unit : 0
        if horizon {
            var line = Path(); line.move(to: CGPoint(x: 0, y: lineY)); line.addLine(to: CGPoint(x: w, y: lineY))
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.16), color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: w, y: 0)), lineWidth: 1)
        }
        let n = max(1, min(3, count))
        for i in 0..<n {
            // nearest the line first; each one further up is fainter
            let tipY = lineY - 117 * unit - Double(i) * 196 * unit + drop * (1 - Double(i) * 0.3) + bob * (1 - Double(i) * 0.4)
            var c = Path()
            c.move(to: CGPoint(x: w / 2 - halfW, y: tipY - depth))
            c.addLine(to: CGPoint(x: w / 2, y: tipY))
            c.addLine(to: CGPoint(x: w / 2 + halfW, y: tipY - depth))
            ctx.stroke(c, with: .color(color.opacity(i == 0 ? 0.95 : 0.5)),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        // the line: drawn out from the middle with progress, glowing once it arrives
        let barW = 424 * unit * max(0.04, p), barH = max(2, 30 * unit)
        let bar = Path(roundedRect: CGRect(x: w / 2 - barW / 2, y: lineY - barH / 2, width: barW, height: barH), cornerRadius: barH / 2)
        let glow = p >= 0.999 ? (pointColor ?? color) : color.opacity(0.75)
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: 10 * unit + 4))
            g.fill(bar, with: .color(glow.opacity(0.8)))
        }
        ctx.fill(bar, with: .color(glow))
    }
}

/// The sky panel used for the empty, analysing and downloading states.
public struct SkyPanel<Overlay: View>: View {
    var progress: Double
    var settled: Bool
    var drift: Bool
    var pointColor: Color?
    var overlay: Overlay
    public init(progress: Double = 1, settled: Bool = false, drift: Bool = false, pointColor: Color? = .white,
                @ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.progress = progress; self.settled = settled; self.drift = drift; self.pointColor = pointColor; self.overlay = overlay()
    }
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Brand.skyGradient)
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Brand.floorGlow)
            LandfallView(progress: progress, settled: settled, drift: drift, color: .white, pointColor: pointColor)
                .padding(.horizontal, 30)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
            overlay
        }
        .shadow(color: Color.black.opacity(0.25), radius: 18, y: 10)
    }
}

/// Slim progress line for rows: a quiet track, an accent fill, and a Dawn point on arrival.
/// `fraction == nil` means the size is unknown: a soft pulse travels along the track instead.
public struct LandfallProgress: View {
    public var fraction: Double?
    public var done: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(fraction: Double?, done: Bool = false) { self.fraction = fraction; self.done = done }

    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.accent.opacity(0.12))
                if let f = fraction {
                    Capsule().fill(Brand.buttonGradient).frame(width: max(4, g.size.width * max(0, min(1, f))))
                        .animation(.linear(duration: 0.25), value: f)
                    if done {
                        Circle().fill(Brand.dawn).frame(width: 7, height: 7).offset(x: g.size.width - 6)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
                        let phase = reduceMotion ? 0.35 : (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8)) / 1.8
                        Capsule().fill(LinearGradient(colors: [Brand.accent.opacity(0), Brand.accent, Brand.accent.opacity(0)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * 0.3)
                            .offset(x: (g.size.width * 1.3) * phase - g.size.width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "Size unknown")
    }
}
