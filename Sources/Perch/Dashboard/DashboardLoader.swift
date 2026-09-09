import SwiftUI

/// The dashboard's opening run.
///
/// The pet is the progress indicator, not decoration beside one: it runs the
/// length of the track and lays the bar down behind it, and its position is real
/// scan progress — the fraction of sources actually read. Where the scan finishes
/// faster than the eye can follow, an elapsed-time floor carries the run so it
/// never jumps to the end; the bar only ever moves forward.
struct DashboardLoader: View {
    @ObservedObject var state: AppState
    let startedAt: Date

    /// The floor the run is paced against, matching `AppState.beginDashboardIntro`.
    private let pacing: TimeInterval = 1.15
    private let petWidth: CGFloat = 78
    private let petHeight: CGFloat = 52

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            // `min`, not `max`: a warm scan reports 100% almost immediately, and
            // taking the larger of the two would snap the bar to the end before the
            // pet had taken a step. Time paces the run; real progress holds it back
            // whenever the scan is the slower of the two.
            let progress = min(1, min(elapsed / pacing, max(state.scanProgress, 0.02)))
            body(progress: progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func body(progress: Double) -> some View {
        VStack(spacing: 0) {
            Spacer()
            track(progress: progress)
                .frame(width: 460, height: petHeight + 18)
            caption(progress: progress)
                .frame(width: 460)
                .padding(.top, 18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func track(progress: Double) -> some View {
        GeometryReader { geo in
            let travel = geo.size.width - petWidth
            let x = travel * CGFloat(progress)
            let baseline = geo.size.height - 3

            ZStack(alignment: .topLeading) {
                // The line the pet is running along, and the part it has laid down.
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 3)
                    .offset(y: baseline)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.55), Theme.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, x + petWidth / 2), height: 3)
                    .offset(y: baseline)

                PetView(
                    status: state.pet,
                    species: state.species,
                    showsExtras: false,
                    animation: MascotAnimations.run
                )
                .frame(width: petWidth, height: petHeight)
                // The mascot's feet sit ~95% down its own bounds (the rest is
                // headroom reserved for the jump), so drop it that far to put them
                // on the line instead of floating above it.
                .offset(x: x, y: baseline - petHeight * 0.95)
            }
        }
    }

    private func caption(progress: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.scanStage.isEmpty ? "Reading your logs…" : state.scanStage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .animation(.easeInOut(duration: 0.2), value: state.scanStage)
            Spacer()
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }
}
