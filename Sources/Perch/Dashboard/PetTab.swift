import SwiftUI

struct PetTab: View {
    @ObservedObject var state: AppState
    @Local private var preview: PetMood?

    private var shown: PetStatus {
        guard let preview else { return state.pet }
        var status = state.pet
        status.mood = preview
        return status
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                Text("PREVIEW PET STATES")
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PetView(status: shown, species: state.species)
                    .frame(width: 300, height: 190)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            )
                    )

                HStack(spacing: 8) {
                    ForEach(PetMood.allCases, id: \.self) { mood in
                        Button { preview = preview == mood ? nil : mood } label: {
                            Text(mood.caption)
                                .font(.system(size: 11, weight: preview == mood ? .semibold : .regular))
                                .foregroundStyle(preview == mood ? Theme.primaryText : Theme.secondaryText)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(
                                    Capsule().fill(preview == mood ? Color.white.opacity(0.10) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(preview == nil
                     ? "Showing the live state, driven by your real activity."
                     : "Previewing — click again to return to live.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .perchCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your companion")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Every species shares the mascot rig — body, eyes, two hands, four legs — so they all walk, lean and jump the same way. The palette and the mark differ.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(PetSpecies.all) { species in
                        Button { state.settings.petSpecies = species.id } label: {
                            HStack(spacing: 9) {
                                PetView(status: state.pet, species: species, showsExtras: false)
                                    .frame(width: 42, height: 27)
                                Text(species.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                if state.settings.petSpecies == species.id {
                                    Circle().fill(Theme.positive).frame(width: 6, height: 6)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Theme.raised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(
                                                state.settings.petSpecies == species.id
                                                    ? Theme.accent.opacity(0.6) : Theme.hairline,
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(Theme.hairline)

                Text("WHAT DRIVES THE PET")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.tertiaryText)
                rule("Working", "a request in the last 90 seconds")
                rule("Focused", "a request in the last 6 minutes")
                rule("Calm", "active today, but idle right now")
                rule("Resting", "nothing for 45 minutes — eyes close, z's drift up")
                rule("Racing flag", "a streak of 3 days or more (currently \(state.rollup.currentStreak))")
                rule("Confetti", "two or more models used today (currently \(state.pet.modelsToday))")
            }
            .frame(width: 380)
            .perchCard()
        }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 96, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
