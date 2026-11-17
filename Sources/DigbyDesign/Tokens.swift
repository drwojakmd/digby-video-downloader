import SwiftUI
import AppKit

/// The Digby palette (the landing pages' tokens), shared with Digby Video Compressor ("Convergence"), plus the
/// Downloader's own deeper sky ("Landfall"). Every interface colour adapts to dark mode.
public enum Brand {
    /// Sky: the accent (buttons, selection, progress). Same values as the Compressor.
    public static let accent = dynamic(light: (0.227, 0.416, 0.682), dark: (0.561, 0.714, 0.910))
    /// Dawn: arrival only — the landing point, a finished download. Never a warning colour.
    public static let dawn = dynamic(light: (0.851, 0.557, 0.384), dark: (0.941, 0.698, 0.549))

    // Fixed sky colours (icon, empty-state panel).
    /// Dusk Navy: the Downloader's higher, deeper sky top. Downloader only.
    public static let duskNavy = Color(red: 0.059, green: 0.122, blue: 0.239)
    public static let altitude = Color(red: 0.078, green: 0.161, blue: 0.302)
    public static let sky = Color(red: 0.302, green: 0.490, blue: 0.722)
    public static let haze = Color(red: 0.749, green: 0.827, blue: 0.918)
    public static let dawnFixed = Color(red: 0.949, green: 0.761, blue: 0.627)

    /// The prominent-button fill (identical to the Compressor's).
    public static let buttonGradient = LinearGradient(
        colors: [dynamic(light: (0.247, 0.447, 0.722), dark: (0.494, 0.651, 0.871)),
                 dynamic(light: (0.180, 0.341, 0.588), dark: (0.388, 0.553, 0.800))],
        startPoint: .top, endPoint: .bottom)

    /// The panel behind the chevrons: the app icon's colours, deep teal down to an amber glow.
    public static let skyGradient = LinearGradient(
        stops: [.init(color: Color(red: 0.016, green: 0.043, blue: 0.051), location: 0),
                .init(color: Color(red: 0.047, green: 0.149, blue: 0.165), location: 0.5),
                .init(color: Color(red: 0.090, green: 0.341, blue: 0.361), location: 0.82),
                .init(color: Color(red: 0.788, green: 0.549, blue: 0.298), location: 1)],
        startPoint: .top, endPoint: .bottom)
    /// Warm light rising from below the line (the icon's "floor").
    public static let floorGlow = RadialGradient(colors: [Color(red: 0.910, green: 0.702, blue: 0.416).opacity(0.42), .clear],
                                                 center: .bottom, startRadius: 0, endRadius: 190)

    /// Status colours, from the site's tokens (--good / --warn, light and dark).
    public static let good = dynamic(light: (0.184, 0.490, 0.357), dark: (0.435, 0.780, 0.620))
    public static let warn = dynamic(light: (0.706, 0.380, 0.165), dark: (0.941, 0.698, 0.549))

    public static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let c = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Spacing and shape, on a 4-pt grid. Values match the Compressor where both apps have the element.
public enum Metrics {
    public static let cardRadius: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    public static let sectionGap: CGFloat = 14
    public static let buttonRadius: CGFloat = 10
    public static let fieldRadius: CGFloat = 12
    public static let panelRadius: CGFloat = 22
    public static let thumbnailRadius: CGFloat = 10
    public static let contentMaxWidth: CGFloat = 760
}

/// Type styles. SF Pro throughout (as in the Compressor); display text uses the light weight.
public enum TypeStyle {
    public static let display = Font.system(size: 28, weight: .light)
    public static let title = Font.system(size: 19, weight: .semibold)
    public static let headline = Font.system(size: 14, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let caption = Font.system(size: 11.5)
    public static let sectionLabel = Font.system(size: 11, weight: .semibold)
    public static let field = Font.system(size: 17)
}

/// The Digby wordmark lockup, as on the landing pages (`.digby-lockup`): "Digby" in Schibsted Grotesk 800 at
/// −0.05em, a thin divider, then the product name in a lighter, slightly dimmed face. Falls back to SF Pro Heavy
/// with the same tracking when Schibsted Grotesk isn't installed.
public struct DigbyLockup: View {
    var product: String
    var size: CGFloat
    var color: Color
    public init(product: String = "Video Downloader", size: CGFloat = 25, color: Color = .white) {
        self.product = product; self.size = size; self.color = color
    }
    static func mark(_ size: CGFloat) -> Font {
        NSFont(name: "SchibstedGrotesk-ExtraBold", size: size) != nil ? .custom("SchibstedGrotesk-ExtraBold", size: size)
            : .system(size: size, weight: .heavy)
    }
    static func product(_ size: CGFloat) -> Font {
        NSFont(name: "HankenGrotesk-Regular", size: size) != nil ? .custom("HankenGrotesk-Regular", size: size)
            : .system(size: size, weight: .regular)
    }
    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Digby").font(Self.mark(size)).tracking(-0.05 * size).foregroundStyle(color)
            Rectangle().fill(color.opacity(0.32)).frame(width: 1, height: size * 0.72)
                .padding(.leading, size * 0.6).padding(.trailing, size * 0.56)
            Text(product).font(Self.product(size * 0.68)).tracking(0.005 * size * 0.68).foregroundStyle(color.opacity(0.78))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("Digby \(product)")
    }
}
