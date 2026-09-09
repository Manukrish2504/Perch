import Foundation
import CoreGraphics

/// The macOS widget size families, at their real point sizes. A widget is not
/// freely resizable on macOS — you pick a family — so Perch matches that rather
/// than inventing arbitrary rectangles.
enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var icon: String {
        switch self {
        case .small: "square.fill"
        case .medium: "rectangle.fill"
        case .large: "square.grid.2x2.fill"
        }
    }

    var points: CGSize {
        switch self {
        case .small: CGSize(width: 155, height: 155)
        case .medium: CGSize(width: 329, height: 155)
        case .large: CGSize(width: 329, height: 329)
        }
    }

    /// macOS widgets use one continuous radius regardless of family.
    static let cornerRadius: CGFloat = 24
}

/// The pinnable desktop widgets.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case usage
    case heatmap
    case models
    case trend
    case limits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: "Usage"
        case .heatmap: "Activity"
        case .models: "Top Models"
        case .trend: "Usage Trend"
        case .limits: "Limits"
        }
    }

    var blurb: String {
        switch self {
        case .usage: "Today and the last 7 days, with a running trace."
        case .heatmap: "Six months of activity, flat or extruded."
        case .models: "Which models are actually spending your tokens."
        case .trend: "Daily volume, split by tool."
        case .limits: "Quota windows the tools report to disk."
        }
    }

    /// Families that have enough room to say something useful.
    var sizes: [WidgetSize] {
        switch self {
        case .usage: [.small, .medium, .large]
        case .limits: [.medium, .large]
        case .heatmap, .models, .trend: [.medium, .large]
        }
    }

    var defaultSize: WidgetSize { sizes.contains(.medium) ? .medium : .small }
}

/// Where a widget sits, how big it is, and whether it is shown. Positions are the
/// window's bottom-left in screen coordinates, so they survive relaunch.
struct WidgetPlacement: Codable, Equatable {
    var enabled: Bool = false
    var size: WidgetSize = .medium
    var x: Double?
    var y: Double?

    enum CodingKeys: String, CodingKey {
        case enabled, size, x, y
    }
}
