import SwiftUI

/// Every colour and metric literal in the app. See
/// `agent-os/standards/ui/theme-tokens.md`.
enum Theme {
    // The shelf must read as an extension of the physical cutout, so this one is
    // true black and is never themed.
    static let notchBlack = Color.black

    static let bg = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let raised = Color(red: 0.125, green: 0.125, blue: 0.141)
    static let hairline = Color.white.opacity(0.08)

    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.60)
    static let tertiaryText = Color.white.opacity(0.36)

    static let accent = Color(red: 0.96, green: 0.51, blue: 0.36)   // warm salmon
    static let positive = Color(red: 0.30, green: 0.82, blue: 0.60)
    static let cool = Color(red: 0.44, green: 0.58, blue: 0.96)

    /// Categorical series — identity only, assigned in this fixed order and never
    /// cycled. The order *is* the colour-blindness safety mechanism, so it does not
    /// change: these eight steps are validated against this dark surface (lightness
    /// band, chroma floor, protan/deutan separation, normal-vision floor, 3:1
    /// contrast). The brand terracotta is deliberately not in here — accent and
    /// series identity are different jobs, and a warm-first ordering measured a
    /// tritan separation of 4.0 against 8.7 for this one.
    static let series: [Color] = [
        Color(hex: 0x3987E5),   // blue
        Color(hex: 0xD95926),   // orange
        Color(hex: 0x199E70),   // aqua
        Color(hex: 0xC98500),   // yellow
        Color(hex: 0xD55181),   // magenta
        Color(hex: 0x008300),   // green
        Color(hex: 0x9085E9),   // violet
        Color(hex: 0xE66767),   // red
    ]

    static func seriesColor(_ index: Int) -> Color {
        series[((index % series.count) + series.count) % series.count]
    }

    /// Sequential ramp for magnitude: one hue, monotone lightness (OKLab L 0.35 to
    /// 0.81), anchored bright-is-more because the surface is dark.
    static let heatEmpty = Color.white.opacity(0.045)
    static let heat: [Color] = [
        Color(hex: 0x1F4435),
        Color(hex: 0x2A6E52),
        Color(hex: 0x348F68),
        Color(hex: 0x43B884),
        Color(hex: 0x63DDA4),
    ]

    /// Diverging pair for change against a baseline — two hues either side of a
    /// neutral, never a hue at the midpoint.
    static let up = Color(hex: 0x43B884)
    static let down = Color(hex: 0xE66767)
    static let neutralMid = Color.white.opacity(0.34)

    /// De-emphasis grey for the "one series is the point, the rest are context" form.
    static let muted = Color.white.opacity(0.22)

    static let radius: CGFloat = 10
    static let notchRadius: CGFloat = 11

    static let expand = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let hover = Animation.easeInOut(duration: 0.18)
}

extension Color {
    /// Hex literals keep the validated palette values verbatim, so a slot can be
    /// checked against the validator output by eye.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Standard card chrome for dashboard panels.
    func perchCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
