import AppKit
import SwiftUI

/// Renders the mascot's animations to PNG frame sequences for the documentation.
///
/// The README's GIFs are generated from these frames rather than screen-recorded,
/// so they are deterministic and reproducible: `PERCH_RENDER_MASCOT=<dir>` writes
/// one folder per animation, and `docs/make-gifs.sh` encodes them.
///
/// This is why `PetView.frame(at:)` exists — `TimelineView` does not advance under
/// `ImageRenderer`, so a live view cannot yield a chosen frame.
@MainActor
enum MascotRenderer {
    static let fps: Double = 24
    private static let size = CGSize(width: 300, height: 210)

    private struct Clip {
        let name: String
        let timeline: MascotTimeline
        let status: PetStatus
        let species: PetSpecies
    }

    private static func status(
        _ mood: PetMood, streak: Int = 0, models: Int = 1
    ) -> PetStatus {
        var status = PetStatus()
        status.mood = mood
        status.streak = streak
        status.modelsToday = models
        return status
    }

    private static var clips: [Clip] {
        [
            Clip(name: "walk", timeline: MascotAnimations.walk,
                 status: status(.focus), species: .pip),
            Clip(name: "run", timeline: MascotAnimations.run,
                 status: status(.focus), species: .pip),
            Clip(name: "hop", timeline: MascotAnimations.hop,
                 status: status(.burst), species: .pip),
            Clip(name: "look", timeline: MascotAnimations.lookAround,
                 status: status(.calm), species: .pip),
            Clip(name: "sleep", timeline: MascotAnimations.sleep,
                 status: status(.rest), species: .pip),
            Clip(name: "flag", timeline: MascotAnimations.lookAround,
                 status: status(.calm, streak: 12), species: .pip),
            Clip(name: "confetti", timeline: MascotAnimations.hop,
                 status: status(.burst, streak: 12, models: 3), species: .pip),
            Clip(name: "species-sprig", timeline: MascotAnimations.walk,
                 status: status(.focus), species: .sprig),
            Clip(name: "species-byte", timeline: MascotAnimations.walk,
                 status: status(.focus), species: .byte),
            Clip(name: "species-ember", timeline: MascotAnimations.walk,
                 status: status(.focus), species: .ember),
            Clip(name: "species-nimbus", timeline: MascotAnimations.walk,
                 status: status(.focus), species: .nimbus),
        ]
    }

    /// The README's hero: the mascot runs, and the wordmark is laid down in its
    /// wake — the pet is at the front of the reveal, not beside it.
    private struct HeroFrame: View {
        let time: TimeInterval
        let loop: Double
        let status: PetStatus

        // Banner proportions: this is the first thing on the README, so it is
        // rendered large and on a clear background rather than the app's surface —
        // it has to sit on whichever GitHub theme the reader is using.
        static let size = CGSize(width: 820, height: 300)
        static let cell: CGFloat = 15
        static let petSize = CGSize(width: 146, height: 98)

        var body: some View {
            // The word finishes a little before the loop ends, so the last frames
            // hold on the finished mark instead of cutting on the final dash.
            let progress = min(1, time / (loop * 0.80))
            let wordWidth = HeroWordmark.width(cell: Self.cell)
            let wordX = (Self.size.width - wordWidth) / 2
            let wordY: CGFloat = 168

            ZStack(alignment: .topLeading) {
                // No background fill — the GIF is keyed transparent on encode.
                Color.clear

                HeroWordmark(reveal: progress, cell: Self.cell)
                    .offset(x: wordX, y: wordY)

                PetView(
                    status: status, species: .pip,
                    showsExtras: false, animation: MascotAnimations.run
                )
                .frame(at: time)
                .frame(width: Self.petSize.width, height: Self.petSize.height)
                // Sits clear above the letters rather than on them, and leads the
                // reveal slightly so it never stands on the dash it just laid.
                .offset(
                    x: wordX + wordWidth * CGFloat(progress) - Self.petSize.width * 0.36,
                    y: wordY - Self.petSize.height - 14
                )
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
    }

    private static func renderHero(into root: URL) {
        let folder = root.appendingPathComponent("hero")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let loop = 2.6
        let frameCount = Int((loop * fps).rounded())

        for index in 0..<frameCount {
            let renderer = ImageRenderer(
                content: HeroFrame(
                    time: Double(index) / fps, loop: loop, status: status(.focus)
                )
            )
            renderer.scale = 2
            guard let image = renderer.nsImage, let data = png(from: image) else { continue }
            try? data.write(to: folder.appendingPathComponent(String(format: "%03d.png", index)))
        }
        FileHandle.standardError.write(Data("rendered hero (\(frameCount) frames)\n".utf8))
    }

    static func render(into directory: String) {
        let root = URL(fileURLWithPath: directory)
        renderHero(into: root)
        for clip in clips {
            let folder = root.appendingPathComponent(clip.name)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            // Loop over an exact number of whole frames so the GIF cycles cleanly.
            let frameCount = max(1, Int((clip.timeline.duration * fps).rounded()))
            for index in 0..<frameCount {
                let time = Double(index) / fps
                let pet = PetView(
                    status: clip.status, species: clip.species,
                    showsExtras: true, animation: clip.timeline
                )
                let content = pet.frame(at: time)
                    .frame(width: size.width, height: size.height)
                    .background(Theme.bg)

                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let data = png(from: image) else { continue }
                let file = folder.appendingPathComponent(String(format: "%03d.png", index))
                try? data.write(to: file)
            }
            FileHandle.standardError.write(
                Data("rendered \(clip.name) (\(frameCount) frames)\n".utf8)
            )
        }
    }

    private static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
