import SwiftUI

/// The mascot, drawn from rectangles and animated per part.
///
/// Every frame samples the current mood's timeline and applies each part's
/// transform independently, which is what allows a lean to bend the legs, a walk
/// to swing them from the hip, and a jump to squash the body on landing.
struct PetView: View {
    let status: PetStatus
    var species: PetSpecies = .pip
    /// Draw the flag, confetti and sleep marks. Off at the smallest sizes, where
    /// they collapse into noise.
    var showsExtras: Bool = true
    /// Overrides the mood-derived timeline. Used by the dashboard's opening run,
    /// where the animation is driven by the app's state rather than the pet's.
    var animation: MascotTimeline?

    private var showsFlag: Bool { showsExtras && status.carriesFlag }
    private var showsConfetti: Bool { showsExtras && status.hasConfetti }

    /// Drawing bounds.
    ///
    /// The base headroom covers the jump: the character lifts 20 units off the
    /// floor, and without room for it the head is clipped off mid-hop. Headroom is
    /// otherwise constant across moods on purpose — deriving it per mood makes the
    /// pet visibly resize whenever it starts or stops working.
    private var bounds: CGRect {
        let top: CGFloat = showsFlag ? -50 : (showsConfetti ? -54 : -32)
        return CGRect(x: -14, y: top, width: 142, height: 82 - top)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            frame(at: timeline.date.timeIntervalSince1970)
        }
        .allowsHitTesting(false)
    }

    /// The mascot at one instant.
    ///
    /// Split out from the `TimelineView` so it can also be rendered offscreen at
    /// chosen times — `TimelineView` does not advance under `ImageRenderer`, so a
    /// live view cannot produce a deterministic frame sequence.
    func frame(at clock: TimeInterval) -> some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(context, size, clock: clock)
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, clock: TimeInterval) {
        let box = bounds
        let scale = min(size.width / box.width, size.height / box.height)
        guard scale > 0 else { return }
        let offsetX = (size.width - box.width * scale) / 2 - box.minX * scale
        let offsetY = (size.height - box.height * scale) / 2 - box.minY * scale

        let line = animation ?? MascotAnimations.timeline(for: status.mood)
        let time = clock.truncatingRemainder(dividingBy: line.duration)
        let root = line.transform(.root, at: time)

        var canvas = context
        canvas.translateBy(x: offsetX, y: offsetY)
        canvas.scaleBy(x: scale, y: scale)
        canvas.translateBy(x: root.x, y: root.y)

        drawLegs(canvas, line: line, time: time)
        drawBody(canvas, line: line, time: time, clock: clock)
        drawHands(canvas, line: line, time: time)
        if showsFlag { drawFlag(canvas, line: line, time: time, clock: clock) }
        if showsConfetti { drawConfetti(canvas, clock: clock) }
        if status.mood == .rest, showsExtras { drawSleep(canvas, clock: clock) }
    }

    // MARK: - Parts

    /// Legs are clipped to the floor. Stretching a rectangle does not care where
    /// the ground is, so without this the legs push straight through it during a
    /// lean — the single detail that decides whether the lean reads as weight.
    private func drawLegs(_ context: GraphicsContext, line: MascotTimeline, time: Double) {
        var floor = context
        floor.clip(to: Path(CGRect(x: -40, y: -90, width: 220, height: Mascot.ground + 90)))
        for index in 0..<4 {
            let transform = line.transform(.leg(index), at: time)
            apply(floor, transform, pivot: Mascot.legPivot(index)) { layer in
                layer.fill(Path(Mascot.leg(index)), with: .color(species.shade.color))
            }
        }
    }

    private func drawBody(
        _ context: GraphicsContext, line: MascotTimeline, time: Double, clock: TimeInterval
    ) {
        let transform = line.transform(.body, at: time)
        apply(context, transform, pivot: Mascot.bodyPivot) { layer in
            layer.fill(Path(Mascot.body), with: .color(species.body.color))
            drawMark(layer)
            let eyes = line.transform(.eyes, at: time)
            var eyeLayer = layer
            eyeLayer.translateBy(x: eyes.x, y: eyes.y)
            drawEyes(eyeLayer, clock: clock)
        }
    }

    private func drawEyes(_ context: GraphicsContext, clock: TimeInterval) {
        // A blink every ~4.4s; eyes stay shut while resting.
        let blinking = clock.truncatingRemainder(dividingBy: 4.4) < 0.14
        let closed = status.mood == .rest || blinking
        for x in Mascot.eyeX {
            let origin = CGPoint(x: x, y: Mascot.eyeY)
            let rects = closed
                ? Mascot.closedEyeRects(at: origin)
                : Mascot.eyeRects(at: origin)
            for rect in rects {
                context.fill(Path(rect), with: .color(species.dark.color))
            }
        }
    }

    private func drawHands(_ context: GraphicsContext, line: MascotTimeline, time: Double) {
        for (part, rect) in [
            (MascotPart.leftHand, Mascot.leftHand),
            (MascotPart.rightHand, Mascot.rightHand),
        ] {
            // The raised hand carries the flag, so it sits higher when there is one.
            var frame = rect
            if showsFlag, part == .rightHand { frame.origin.y -= 16 }
            let transform = line.transform(part, at: time)
            apply(context, transform, pivot: CGPoint(x: frame.midX, y: frame.minY)) { layer in
                layer.fill(Path(frame), with: .color(species.shade.color))
            }
        }
    }

    /// The streak flag: a pole out of the raised hand and a checkered cloth whose
    /// columns ride a travelling sine, rather than twelve hand-drawn frames.
    private func drawFlag(
        _ context: GraphicsContext, line: MascotTimeline, time: Double, clock: TimeInterval
    ) {
        let hand = line.transform(.rightHand, at: time)
        var layer = context
        layer.translateBy(x: hand.x, y: hand.y)

        let poleX = Mascot.rightHand.midX
        let poleTop = Mascot.rightHand.minY - 16 - Mascot.poleHeight
        layer.fill(
            Path(CGRect(
                x: poleX, y: poleTop,
                width: Mascot.poleWidth, height: Mascot.poleHeight + 22
            )),
            with: .color(species.dark.color)
        )

        let cell = Mascot.flagCell
        for column in 0..<Mascot.flagColumns {
            let phase = clock * 5.2 - Double(column) * 0.72
            let lift = CGFloat(sin(phase)) * cell * 0.62
            for row in 0..<Mascot.flagRows {
                // Checkerboard, like the original's racing flag.
                let dark = (row + column) % 2 == 0
                let rect = CGRect(
                    x: poleX - cell * CGFloat(Mascot.flagColumns) + CGFloat(column) * cell,
                    y: poleTop + CGFloat(row) * cell + lift,
                    width: cell + 0.4, height: cell + 0.4
                )
                layer.fill(
                    Path(rect),
                    with: .color(dark ? species.dark.color : species.accent.color)
                )
            }
        }
    }

    /// Confetti for a multi-model day: a burst that rises, peaks and falls, using
    /// the original's per-frame vertical offsets.
    private func drawConfetti(_ context: GraphicsContext, clock: TimeInterval) {
        let lift: [CGFloat] = [-65, -72, -76, -70, -58, -42, -22, 0]
        let period = 1.6
        let phase = clock.truncatingRemainder(dividingBy: period) / period
        let step = min(lift.count - 1, Int(phase * Double(lift.count)))
        let rise = lift[step] * 0.42
        let fade = 1 - phase

        for index in 0..<10 {
            // Deterministic scatter: the same burst every loop, like a sprite sheet.
            let angle = Double(index) * 2.399
            let spread = 26.0 * (0.35 + phase)
            let x = Mascot.body.midX + CGFloat(cos(angle) * spread)
            let y = Mascot.body.minY - 6 + rise + CGFloat(sin(angle * 1.7) * spread * 0.4)
            let side: CGFloat = index % 3 == 0 ? 5 : 3.5
            context.fill(
                Path(CGRect(x: x, y: y, width: side, height: side)),
                with: .color(Theme.seriesColor(index).opacity(fade * 0.95))
            )
        }
    }

    private func drawSleep(_ context: GraphicsContext, clock: TimeInterval) {
        for index in 0..<2 {
            let phase = (clock * 0.34 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
            let side = 5.0 + Double(index) * 2.5
            let rect = CGRect(
                x: Mascot.body.maxX - 4 + CGFloat(index) * 7,
                y: Mascot.body.minY - CGFloat(phase) * 26,
                width: side, height: side
            )
            context.fill(Path(rect), with: .color(species.dark.color.opacity((1 - phase) * 0.5)))
        }
    }

    /// The one mark that tells the species apart, drawn on the body.
    private func drawMark(_ context: GraphicsContext) {
        let top = Mascot.body.minY
        let midX = Mascot.body.midX
        switch species.mark {
        case .none:
            return
        case .leaf:
            for side in [-1.0, 1.0] {
                context.fill(
                    Path(CGRect(x: midX + side * 12 - 5, y: top - 13, width: 10, height: 13)),
                    with: .color(species.accent.color)
                )
            }
        case .antenna:
            context.fill(
                Path(CGRect(x: midX - 2, y: top - 16, width: 4, height: 16)),
                with: .color(species.shade.color)
            )
            context.fill(
                Path(CGRect(x: midX - 5, y: top - 22, width: 10, height: 8)),
                with: .color(species.accent.color)
            )
        case .tuft:
            for (index, width) in [18.0, 11.0, 5.0].enumerated() {
                context.fill(
                    Path(CGRect(
                        x: midX - width / 2, y: top - 6 - Double(index) * 6,
                        width: width, height: 6
                    )),
                    with: .color(species.accent.color)
                )
            }
        case .cloud:
            for (dx, width) in [(-22.0, 26.0), (0.0, 34.0), (18.0, 26.0)] {
                context.fill(
                    Path(CGRect(
                        x: midX + dx - width / 2, y: Mascot.ground - 4,
                        width: width, height: 11
                    )),
                    with: .color(species.accent.color.opacity(0.9))
                )
            }
        }
    }

    // MARK: - Transform

    /// Applies a part transform about a pivot, matching GSAP's order: translate,
    /// then rotate and scale about the origin.
    private func apply(
        _ context: GraphicsContext,
        _ transform: MascotTransform,
        pivot: CGPoint,
        _ body: (GraphicsContext) -> Void
    ) {
        var layer = context
        layer.translateBy(x: transform.x, y: transform.y)
        layer.translateBy(x: pivot.x, y: pivot.y)
        layer.rotate(by: .degrees(transform.rotation))
        layer.scaleBy(x: transform.scaleX, y: transform.scaleY)
        layer.translateBy(x: -pivot.x, y: -pivot.y)
        body(layer)
    }
}
