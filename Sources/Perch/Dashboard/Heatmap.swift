import SwiftUI

/// GitHub-style contribution grid: one column per week, one row per weekday.
struct ActivityHeatmap: View {
    let days: [DayStat]
    var cell: CGFloat = 12
    var spacing: CGFloat = 3
    @Local private var hovered: Date?

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(HeatGrid.columns(days).enumerated()), id: \.offset) { _, week in
                VStack(spacing: spacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: max(1.5, cell * 0.22))
                            .fill(HeatGrid.color(day, in: days))
                            .frame(width: cell, height: cell)
                            .overlay(
                                RoundedRectangle(cornerRadius: max(1.5, cell * 0.22))
                                    .strokeBorder(
                                        Theme.primaryText,
                                        lineWidth: day != nil && hovered == day?.day ? 1 : 0
                                    )
                            )
                            .onHover { inside in hovered = inside ? day?.day : nil }
                            .help(HeatGrid.tooltip(day))
                    }
                }
            }
        }
    }
}

/// The same data extruded into isometric cubes — each day's height is its volume,
/// so a heavy week reads as a ridge rather than a slightly darker square.
struct ActivityHeatmap3D: View {
    let days: [DayStat]
    /// Half-width and half-height of a tile's diamond top face.
    var tile: CGSize = CGSize(width: 7, height: 3.4)
    var maxLift: CGFloat = 34

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(context, size)
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let columns = HeatGrid.columns(days)
        guard !columns.isEmpty else { return }
        let peak = max(days.map(\.totals.total).max() ?? 1, 1)
        let w = tile.width, h = tile.height

        // Weeks push right-and-up, weekdays right-and-down, so the grid reads as a
        // band climbing to the right the way an isometric calendar should.
        let span = CGFloat(columns.count + 7)
        let originX = (size.width - span * w) / 2 + CGFloat(columns.count) * 0
        let originY = size.height - maxLift * 0.35

        struct Cube {
            let x: CGFloat, y: CGFloat, lift: CGFloat, depth: Int, value: Int
        }
        var cubes: [Cube] = []
        for (c, week) in columns.enumerated() {
            for (r, day) in week.enumerated() {
                let value = day?.totals.total ?? 0
                // A cube root keeps a single huge day from flattening every other.
                let ratio = value > 0 ? pow(Double(value) / Double(peak), 1.0 / 2.4) : 0
                cubes.append(Cube(
                    x: originX + CGFloat(c + r) * w,
                    y: originY + CGFloat(r - c) * h,
                    lift: CGFloat(ratio) * maxLift,
                    depth: r - c,
                    value: value
                ))
            }
        }
        // Painter's algorithm: larger `depth` is nearer the viewer, so draw last.
        cubes.sort { $0.depth < $1.depth }

        // Tiles are inset by a hair so neighbouring cells stay legible instead of
        // fusing into one slab — most days in a six-month window are empty.
        let iw = w * 0.88, ih = h * 0.88
        for cube in cubes {
            let base = HeatGrid.rampColor(cube.value, peak: peak)
            let top = cube.y - cube.lift
            // Top face.
            var face = Path()
            face.move(to: CGPoint(x: cube.x, y: top))
            face.addLine(to: CGPoint(x: cube.x + iw, y: top + ih))
            face.addLine(to: CGPoint(x: cube.x, y: top + 2 * ih))
            face.addLine(to: CGPoint(x: cube.x - iw, y: top + ih))
            face.closeSubpath()
            context.fill(face, with: .color(base))

            guard cube.lift > 0.4 else { continue }
            // Left and right walls, shaded so the extrusion reads as solid.
            var left = Path()
            left.move(to: CGPoint(x: cube.x - iw, y: top + ih))
            left.addLine(to: CGPoint(x: cube.x, y: top + 2 * ih))
            left.addLine(to: CGPoint(x: cube.x, y: top + 2 * ih + cube.lift))
            left.addLine(to: CGPoint(x: cube.x - iw, y: top + ih + cube.lift))
            left.closeSubpath()
            context.fill(left, with: .color(base.opacity(0.5)))

            var right = Path()
            right.move(to: CGPoint(x: cube.x + iw, y: top + ih))
            right.addLine(to: CGPoint(x: cube.x, y: top + 2 * ih))
            right.addLine(to: CGPoint(x: cube.x, y: top + 2 * ih + cube.lift))
            right.addLine(to: CGPoint(x: cube.x + iw, y: top + ih + cube.lift))
            right.closeSubpath()
            context.fill(right, with: .color(base.opacity(0.75)))
        }
    }
}

/// Shared bucketing and colour ramp for both heatmaps.
enum HeatGrid {
    /// Weeks as columns of seven, padded so every row is a consistent weekday.
    static func columns(_ days: [DayStat]) -> [[DayStat?]] {
        guard let first = days.first else { return [] }
        let leading = Calendar.current.component(.weekday, from: first.day) - 1
        var flat: [DayStat?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while flat.count % 7 != 0 { flat.append(nil) }
        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<$0 + 7]) }
    }

    /// Quartiles over non-empty days, so a few huge days don't flatten the rest
    /// into the lightest bucket.
    static func thresholds(_ days: [DayStat]) -> [Int] {
        let values = days.map(\.totals.total).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [1, 2, 3, 4] }
        func quantile(_ q: Double) -> Int {
            values[min(values.count - 1, max(0, Int(Double(values.count - 1) * q)))]
        }
        return [quantile(0.25), quantile(0.50), quantile(0.75), values[values.count - 1]]
    }

    static func color(_ day: DayStat?, in days: [DayStat]) -> Color {
        guard let day, day.totals.total > 0 else { return Theme.heatEmpty }
        let steps = thresholds(days)
        for (index, limit) in steps.enumerated() where day.totals.total <= limit {
            return Theme.heat[min(index, Theme.heat.count - 1)]
        }
        return Theme.heat[Theme.heat.count - 1]
    }

    /// Continuous ramp for the 3D view, where height already carries magnitude
    /// and colour only needs to reinforce it.
    static func rampColor(_ value: Int, peak: Int) -> Color {
        guard value > 0 else { return Theme.heatEmpty }
        let ratio = pow(Double(value) / Double(max(peak, 1)), 1.0 / 2.4)
        let index = min(Theme.heat.count - 1, Int(ratio * Double(Theme.heat.count)))
        return Theme.heat[index]
    }

    static func tooltip(_ day: DayStat?) -> String {
        guard let day else { return "" }
        return "\(Format.day.string(from: day.day)) · \(Format.full(day.totals.total)) tokens"
    }
}

/// The heatmap card: 2D grid or extruded 3D, with the toggle the reference has.
struct HeatmapCard: View {
    let days: [DayStat]
    var title: String = "ACTIVITY HEATMAP"
    var cell: CGFloat = 11
    @Local private var isThreeD = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                HStack(spacing: 0) {
                    toggle("2D", on: !isThreeD) { isThreeD = false }
                    toggle("3D", on: isThreeD) { isThreeD = true }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
            }

            if isThreeD {
                ActivityHeatmap3D(days: days)
                    .frame(height: 132)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    ActivityHeatmap(days: days, cell: cell, spacing: 2.5)
                        .padding(.vertical, 2)
                }
                .frame(height: 132)
            }

            legend
        }
    }

    private func toggle(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(on ? Theme.primaryText : Theme.tertiaryText)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(on ? Color.white.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
            RoundedRectangle(cornerRadius: 2).fill(Theme.heatEmpty).frame(width: 10, height: 10)
            ForEach(Array(Theme.heat.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
            Spacer()
            Text("\(days.filter { $0.totals.total > 0 }.count) active days")
                .font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
        }
    }
}
