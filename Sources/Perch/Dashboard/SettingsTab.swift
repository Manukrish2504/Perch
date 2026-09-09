import SwiftUI

struct SettingsTab: View {
    @ObservedObject var state: AppState
    @Local private var confirmRebuild = false

    /// Only models that actually carry usage — no point editing rates for the rest.
    private var usedModels: [String] {
        state.rollup.modelsRanked.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("SHELF") {
                row("Shelf shows") {
                    Picker("", selection: $state.settings.shelfMetric) {
                        ForEach(Settings.ShelfMetric.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                row("Show cost") {
                    Toggle("", isOn: $state.settings.showCost).labelsHidden()
                }
                row("Hide in full screen") {
                    Toggle("", isOn: $state.settings.hideInFullscreen).labelsHidden()
                }
                Text("The shelf hangs below the notch, so it would otherwise cover the top of a full-screen app.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("RATES") {
                Text("""
                     Dollars per million tokens. Anthropic rates are published; others are \
                     Perch's estimate and are marked as such. Edits are saved to \
                     rates.json and applied immediately.
                     """)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 0) {
                    Text("Model").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(["Input", "Output", "Cache 5m", "Cache 1h", "Cache read"], id: \.self) {
                        Text($0).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 74, alignment: .trailing)
                    }
                }
                .padding(.top, 4)

                ForEach(usedModels, id: \.self) { model in
                    rateRow(model)
                }

                HStack {
                    Button("Reset to bundled rates") { state.resetRates() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.top, 4)
            }

            section("DATA") {
                row("Last scan") {
                    Text(state.lastScan.map { Format.relative($0) } ?? "—")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                row("Scan duration") {
                    Text(String(format: "%.2fs", state.scanDuration))
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }
                row("Events tracked") {
                    Text(Format.full(state.rollup.eventCount))
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }
                row("Perch's own files") {
                    Text(Format.tildePath(PerchPaths.supportDirectory.path))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                }

                HStack(spacing: 10) {
                    Button {
                        confirmRebuild = true
                    } label: {
                        Text("Rebuild from scratch")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Color.white.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(PerchPaths.supportDirectory)
                    } label: {
                        Text("Open data folder")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 4)
                .alert("Re-read every log from scratch?", isPresented: $confirmRebuild) {
                    Button("Rebuild", role: .destructive) { state.rebuildFromScratch() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Discards Perch's cached snapshot and re-parses every source. Nothing outside Perch's own folder is touched.")
                }
            }
        }
    }

    private func rateRow(_ model: String) -> some View {
        let rate = state.prices.rate(for: model)
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(model).font(.system(size: 11)).foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if rate.estimated {
                    Text("est")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            field(model, rate, \.input)
            field(model, rate, \.output)
            field(model, rate, \.cacheWrite5m)
            field(model, rate, \.cacheWrite1h)
            field(model, rate, \.cacheRead)
        }
        .padding(.vertical, 3)
    }

    private func field(
        _ model: String, _ rate: ModelRate, _ key: WritableKeyPath<ModelRate, Double>
    ) -> some View {
        let binding = Binding<String>(
            get: { String(format: "%g", rate[keyPath: key]) },
            set: { text in
                guard let value = Double(text) else { return }
                var updated = rate
                updated[keyPath: key] = value
                // A hand-edited rate is no longer Perch's estimate.
                updated.estimated = false
                state.updateRate(model: model, rate: updated)
            }
        )
        return TextField("", text: binding)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5))
            .frame(width: 70)
            .padding(.leading, 4)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchCard()
    }

    private func row(_ label: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.primaryText)
            Spacer()
            control()
        }
    }
}
