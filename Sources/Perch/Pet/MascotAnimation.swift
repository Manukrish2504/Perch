import SwiftUI

/// Easing curves, matching the ones the original animations are built on.
/// GSAP's `power1` is quadratic, `power2` cubic, `power3` quartic.
enum Ease {
    case linear
    case sineIn, sineOut, sineInOut
    case power1InOut
    case power2In, power2Out
    case power3In, power3Out
    case backOut

    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .sineIn: return 1 - cos(t * .pi / 2)
        case .sineOut: return sin(t * .pi / 2)
        case .sineInOut: return -(cos(.pi * t) - 1) / 2
        case .power1InOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .power2In: return t * t * t
        case .power2Out: return 1 - pow(1 - t, 3)
        case .power3In: return t * t * t * t
        case .power3Out: return 1 - pow(1 - t, 4)
        case .backOut:
            let c1 = 1.70158, c3 = 1.70158 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        }
    }
}

/// A part's animatable properties.
enum MascotProperty: Hashable {
    case x, y, rotation, scaleX, scaleY

    var identity: Double {
        switch self {
        case .x, .y, .rotation: 0
        case .scaleX, .scaleY: 1
        }
    }
}

struct MascotTransform {
    var x: Double = 0
    var y: Double = 0
    var rotation: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
}

/// One property of one part moving to a value over a window of the timeline.
struct Tween {
    let part: MascotPart
    let property: MascotProperty
    let to: Double
    let start: Double
    let duration: Double
    let ease: Ease

    init(
        _ part: MascotPart, _ property: MascotProperty, to: Double,
        at start: Double, _ duration: Double, _ ease: Ease = .power2Out
    ) {
        self.part = part
        self.property = property
        self.to = to
        self.start = start
        self.duration = duration
        self.ease = ease
    }
}

/// A loop of tweens, sampled at a time rather than stepped.
///
/// Sampling is stateless: for each property, tweens are replayed in order from the
/// identity value, so each one starts wherever the previous ended. That means an
/// animation can be evaluated at any instant — which matters because the pet is
/// drawn from a `TimelineView` clock that may skip frames when a window is hidden.
struct MascotTimeline {
    let duration: Double
    private let tracks: [Key: [Tween]]

    private struct Key: Hashable {
        let part: MascotPart
        let property: MascotProperty
    }

    init(duration: Double, tweens: [Tween]) {
        self.duration = duration
        var tracks: [Key: [Tween]] = [:]
        for tween in tweens {
            tracks[Key(part: tween.part, property: tween.property), default: []].append(tween)
        }
        self.tracks = tracks.mapValues { $0.sorted { $0.start < $1.start } }
    }

    func value(_ part: MascotPart, _ property: MascotProperty, at time: Double) -> Double {
        guard let track = tracks[Key(part: part, property: property)] else {
            return property.identity
        }
        var value = property.identity
        for tween in track {
            if time >= tween.start + tween.duration {
                value = tween.to
            } else if time > tween.start {
                let progress = tween.ease.apply((time - tween.start) / tween.duration)
                value += (tween.to - value) * progress
                break
            } else {
                break
            }
        }
        return value
    }

    func transform(_ part: MascotPart, at time: Double) -> MascotTransform {
        MascotTransform(
            x: value(part, .x, at: time),
            y: value(part, .y, at: time),
            rotation: value(part, .rotation, at: time),
            scaleX: value(part, .scaleX, at: time),
            scaleY: value(part, .scaleY, at: time)
        )
    }
}

// MARK: - The animations

enum MascotAnimations {
    /// Calm: the character leans left, looks, returns, leans right, returns.
    ///
    /// The lean is one beat, not three — body, eyes and legs all start together
    /// with the same easing, and the legs nearest the lean stretch most, so the
    /// weight reads as going into the ground.
    static let lookAround: MascotTimeline = {
        var tweens: [Tween] = []
        let legLean: [Double] = [-6, -7, -7, -8]
        let legStretch: [Double] = [1.30, 1.26, 1.18, 1.12]

        func lean(_ at: Double, direction: Double) {
            let d = direction
            tweens.append(Tween(.eyes, .x, to: -3 * d, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .rotation, to: -3 * d, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .x, to: -3 * d, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .y, to: -5, at: at, 0.4, .power2Out))
            for i in 0..<4 {
                tweens.append(Tween(.leg(i), .rotation, to: legLean[i] * d, at: at, 0.4, .power2Out))
                tweens.append(Tween(.leg(i), .scaleY, to: legStretch[i], at: at, 0.4, .power2Out))
            }
        }

        func settle(_ at: Double) {
            tweens.append(Tween(.eyes, .x, to: 0, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .rotation, to: 0, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .x, to: 0, at: at, 0.4, .power2Out))
            tweens.append(Tween(.body, .y, to: 0, at: at, 0.4, .power2Out))
            for i in 0..<4 {
                tweens.append(Tween(.leg(i), .rotation, to: 0, at: at, 0.4, .power2Out))
                tweens.append(Tween(.leg(i), .scaleY, to: 1, at: at, 0.4, .power2Out))
            }
        }

        lean(0.6, direction: 1)
        settle(1.9)
        lean(2.8, direction: -1)
        settle(4.1)
        return MascotTimeline(duration: 5.4, tweens: tweens)
    }()

    /// Focus: a four-beat walk. Legs swing from the hip and the body bobs twice
    /// per cycle, once for each pair of legs planting.
    static let walk: MascotTimeline = {
        var tweens: [Tween] = []
        let cycle = 0.72
        let swing = 11.0
        for i in 0..<4 {
            // Diagonal pairs move together, the way a four-legged gait works.
            let phase: Double = (i == 0 || i == 3) ? 0 : cycle / 2
            for step in 0..<2 {
                let at = phase + Double(step) * cycle
                tweens.append(Tween(.leg(i), .rotation, to: swing, at: at, cycle / 2, .sineInOut))
                tweens.append(
                    Tween(.leg(i), .rotation, to: -swing, at: at + cycle / 2, cycle / 2, .sineInOut)
                )
            }
        }
        for step in 0..<4 {
            let at = Double(step) * cycle / 2
            tweens.append(Tween(.body, .y, to: -2.5, at: at, cycle / 4, .sineOut))
            tweens.append(Tween(.body, .y, to: 0, at: at + cycle / 4, cycle / 4, .sineIn))
        }
        return MascotTimeline(duration: cycle * 2, tweens: tweens)
    }()

    /// Working: crouch, launch, land with a bounce. The arc is `sine.out` going up
    /// and `power3.in` coming down — the asymmetry is what reads as gravity.
    static let hop: MascotTimeline = {
        var tweens: [Tween] = []
        // Crouch — quick, to gather momentum.
        tweens.append(Tween(.body, .y, to: 8, at: 0, 0.1, .power3In))
        tweens.append(Tween(.leftHand, .y, to: 10, at: 0, 0.1, .power3In))
        tweens.append(Tween(.rightHand, .y, to: 10, at: 0, 0.1, .power3In))
        for i in 0..<4 { tweens.append(Tween(.leg(i), .scaleY, to: 0.72, at: 0, 0.1, .power3In)) }

        // Launch.
        tweens.append(Tween(.root, .y, to: -20, at: 0.1, 0.32, .sineOut))
        tweens.append(Tween(.body, .y, to: -4, at: 0.1, 0.2, .power2Out))
        tweens.append(Tween(.leftHand, .y, to: -8, at: 0.1, 0.24, .power2Out))
        tweens.append(Tween(.rightHand, .y, to: -8, at: 0.1, 0.24, .power2Out))
        for i in 0..<4 { tweens.append(Tween(.leg(i), .scaleY, to: 1.12, at: 0.1, 0.24, .power2Out)) }

        // Fall.
        tweens.append(Tween(.root, .y, to: 0, at: 0.46, 0.2, .power3In))

        // Land: the hands overshoot down and settle, or the landing reads as stiff.
        tweens.append(Tween(.leftHand, .y, to: 7, at: 0.66, 0.05, .power2In))
        tweens.append(Tween(.rightHand, .y, to: 7, at: 0.66, 0.05, .power2In))
        tweens.append(Tween(.leftHand, .y, to: 0, at: 0.71, 0.18, .backOut))
        tweens.append(Tween(.rightHand, .y, to: 0, at: 0.71, 0.18, .backOut))
        tweens.append(Tween(.body, .scaleY, to: 0.9, at: 0.66, 0.05, .power2In))
        tweens.append(Tween(.body, .scaleY, to: 1, at: 0.71, 0.2, .backOut))
        tweens.append(Tween(.body, .y, to: 0, at: 0.66, 0.16, .power2Out))
        for i in 0..<4 {
            tweens.append(Tween(.leg(i), .scaleY, to: 0.86, at: 0.66, 0.05, .power2In))
            tweens.append(Tween(.leg(i), .scaleY, to: 1, at: 0.71, 0.2, .backOut))
        }
        return MascotTimeline(duration: 1.5, tweens: tweens)
    }()

    /// Running: the walk at pace, with the body pitched forward and a longer
    /// stride. Used for the dashboard's opening run, where the character is
    /// actually going somewhere rather than pacing on the spot.
    static let run: MascotTimeline = {
        var tweens: [Tween] = []
        let cycle = 0.34
        let swing = 26.0

        // Legs alternate in diagonal pairs, twice per loop.
        for i in 0..<4 {
            let phase: Double = (i == 0 || i == 3) ? 0 : cycle / 2
            for step in 0..<2 {
                let at = phase + Double(step) * cycle
                tweens.append(Tween(.leg(i), .rotation, to: swing, at: at, cycle / 2, .sineInOut))
                tweens.append(
                    Tween(.leg(i), .rotation, to: -swing, at: at + cycle / 2, cycle / 2, .sineInOut)
                )
            }
        }

        // A forward pitch held for the whole run — this is what separates a run
        // from a brisk walk far more than leg speed does.
        tweens.append(Tween(.body, .rotation, to: 7, at: 0, 0.18, .power2Out))

        // Two bounds per loop, and the hands pump against them.
        for step in 0..<4 {
            let at = Double(step) * cycle / 2
            tweens.append(Tween(.body, .y, to: -5, at: at, cycle / 4, .sineOut))
            tweens.append(Tween(.body, .y, to: 0, at: at + cycle / 4, cycle / 4, .sineIn))
            let forward = step % 2 == 0
            tweens.append(Tween(.leftHand, .y, to: forward ? -6 : 4, at: at, cycle / 2, .sineInOut))
            tweens.append(Tween(.rightHand, .y, to: forward ? 4 : -6, at: at, cycle / 2, .sineInOut))
        }
        return MascotTimeline(duration: cycle * 2, tweens: tweens)
    }()

    /// Resting: slow breathing, nothing else.
    static let sleep: MascotTimeline = {
        var tweens: [Tween] = []
        tweens.append(Tween(.body, .scaleY, to: 0.965, at: 0, 1.6, .sineInOut))
        tweens.append(Tween(.body, .y, to: 2, at: 0, 1.6, .sineInOut))
        tweens.append(Tween(.body, .scaleY, to: 1, at: 1.6, 1.6, .sineInOut))
        tweens.append(Tween(.body, .y, to: 0, at: 1.6, 1.6, .sineInOut))
        return MascotTimeline(duration: 3.2, tweens: tweens)
    }()

    static func timeline(for mood: PetMood) -> MascotTimeline {
        switch mood {
        case .rest: sleep
        case .calm: lookAround
        case .focus: walk
        case .burst: hop
        }
    }
}
