import SwiftUI

/// The mascot's parts, each independently transformable.
///
/// The character is built the way the original is — entirely from rectangles, no
/// paths and no curves — so that rotation, stretch and offset can be applied per
/// part rather than baked into a sprite. That is what makes the walk, the lean and
/// the jump possible at all.
enum MascotPart: Hashable {
    case body
    case eyes
    case leftHand
    case rightHand
    case leg(Int)
    case flag
    /// The whole character, for jumps and horizontal travel.
    case root
}

/// Geometry in the mascot's own coordinate space. Values follow the original
/// artwork: legs 11pt wide and 26 tall standing on a floor at y = 86, hands
/// 21.66 x 22.64, and the body pivoting about (53, 65) — down near the hips,
/// which is why a lean reads as weight on the legs rather than a spinning box.
enum Mascot {
    // Proportions are measured off the original artwork rather than taken from
    // one animation's markup: the body is wider than tall (85 x 68) and the legs
    // are short, about a fifth of the body's height. Long legs turn the character
    // into a spider.
    static let ground: CGFloat = 76
    static let bodyPivot = CGPoint(x: 53, y: 64)

    static let body = CGRect(x: 11, y: -8, width: 85, height: 68)

    static let legWidth: CGFloat = 11
    static let legHeight: CGFloat = 16
    static let legTop: CGFloat = 60
    /// Two pairs, with a wider gap between them than within them.
    static let legX: [CGFloat] = [11, 32, 64, 85]

    static let handSize = CGSize(width: 21.66, height: 24)
    static let leftHand = CGRect(
        x: body.minX - handSize.width + 2, y: 24,
        width: handSize.width, height: handSize.height
    )
    static let rightHand = CGRect(
        x: body.maxX - 2, y: 24,
        width: handSize.width, height: handSize.height
    )

    static func leg(_ index: Int) -> CGRect {
        CGRect(x: legX[index], y: legTop, width: legWidth, height: legHeight)
    }

    /// Each leg pivots from the hip, not the foot — the article's `svgOrigin`
    /// switch mid-timeline. Rotating about the foot makes a walk look like a
    /// windscreen wiper.
    static func legPivot(_ index: Int) -> CGPoint {
        CGPoint(x: legX[index] + legWidth / 2, y: legTop)
    }

    // MARK: - Eyes

    /// One eye is three rectangles: a bar across the top and a single block under
    /// each outer corner, which together read as a contented arch.
    static let eyeSize = CGSize(width: 22, height: 13)
    static let eyeY: CGFloat = 3
    static let eyeX: [CGFloat] = [17, 70]

    static func eyeRects(at origin: CGPoint) -> [CGRect] {
        let cell = CGSize(width: eyeSize.width / 4, height: eyeSize.height / 2)
        return [
            CGRect(x: origin.x + cell.width, y: origin.y, width: cell.width * 2, height: cell.height),
            CGRect(x: origin.x, y: origin.y + cell.height, width: cell.width, height: cell.height),
            CGRect(
                x: origin.x + cell.width * 3, y: origin.y + cell.height,
                width: cell.width, height: cell.height
            ),
        ]
    }

    /// Closed eyes are a single flat bar — used for sleeping and for blinks.
    static func closedEyeRects(at origin: CGPoint) -> [CGRect] {
        let cell = CGSize(width: eyeSize.width / 4, height: eyeSize.height / 2)
        return [CGRect(
            x: origin.x, y: origin.y + cell.height,
            width: eyeSize.width, height: cell.height
        )]
    }

    // MARK: - Flag

    /// A pole rising from the raised hand, with a checkered cloth. The cloth waves
    /// by offsetting each column on a travelling sine rather than by swapping
    /// hand-drawn frames.
    static let poleWidth: CGFloat = 4
    static let poleHeight: CGFloat = 46
    static let flagColumns = 6
    static let flagRows = 4
    static let flagCell: CGFloat = 5.5
}
