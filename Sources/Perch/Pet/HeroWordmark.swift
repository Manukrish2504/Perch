import SwiftUI

/// The word PERCH, drawn as dashes.
///
/// A 5x7 pixel grid per letter, but each lit cell is rendered as a short
/// horizontal dash rather than a square — the same construction as the mascot,
/// read at a different rhythm. Used for the README's hero animation, where the
/// mascot lays the word down as it runs past.
struct HeroWordmark: View {
    /// 0...1 — how much of the word has been laid down.
    let reveal: Double
    var cell: CGFloat = 7
    var color: Color = Theme.accent

    private static let glyphs: [[String]] = [
        [   // P
            "####.",
            "#...#",
            "#...#",
            "####.",
            "#....",
            "#....",
            "#....",
        ],
        [   // E
            "#####",
            "#....",
            "#....",
            "####.",
            "#....",
            "#....",
            "#####",
        ],
        [   // R
            "####.",
            "#...#",
            "#...#",
            "####.",
            "#..#.",
            "#...#",
            "#...#",
        ],
        [   // C
            ".####",
            "#....",
            "#....",
            "#....",
            "#....",
            "#....",
            ".####",
        ],
        [   // H
            "#...#",
            "#...#",
            "#...#",
            "#####",
            "#...#",
            "#...#",
            "#...#",
        ],
    ]

    private static let glyphWidth = 5
    private static let glyphHeight = 7
    private static let letterGap = 2

    static func width(cell: CGFloat) -> CGFloat {
        let columns = glyphs.count * glyphWidth + (glyphs.count - 1) * letterGap
        return CGFloat(columns) * cell
    }

    static func height(cell: CGFloat) -> CGFloat {
        CGFloat(glyphHeight) * cell
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let totalColumns = Self.glyphs.count * Self.glyphWidth
                + (Self.glyphs.count - 1) * Self.letterGap
            // Reveal by column, so the word is written left to right in step with
            // whatever is moving across it.
            let revealed = Double(totalColumns) * min(max(reveal, 0), 1)

            var columnOffset = 0
            for glyph in Self.glyphs {
                for (row, line) in glyph.enumerated() {
                    for (column, mark) in line.enumerated() where mark == "#" {
                        let absolute = columnOffset + column
                        guard Double(absolute) < revealed else { continue }
                        // Each cell is a dash: wide, short, and rounded, with the
                        // gap doing the separating.
                        let rect = CGRect(
                            x: CGFloat(absolute) * cell,
                            y: CGFloat(row) * cell + cell * 0.24,
                            width: cell * 0.86,
                            height: cell * 0.5
                        )
                        // The newest columns arrive at full strength and settle.
                        let age = revealed - Double(absolute)
                        let opacity = age < 1.4 ? 0.55 + 0.45 * (age / 1.4) : 1
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cell * 0.22),
                            with: .color(color.opacity(opacity))
                        )
                    }
                }
                columnOffset += Self.glyphWidth + Self.letterGap
            }
            _ = size
        }
        .frame(
            width: Self.width(cell: cell),
            height: Self.height(cell: cell)
        )
    }
}
