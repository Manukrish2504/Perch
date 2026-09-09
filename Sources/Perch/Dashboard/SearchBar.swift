import SwiftUI

/// What a search hit points at.
struct SearchHit: Identifiable {
    enum Kind {
        case project
        case model

        var icon: String {
            switch self {
            case .project: "folder.fill"
            case .model: "cpu.fill"
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String
    /// Project path or model name — whatever the caller needs to act on.
    let key: String
    let tokens: Int

    var id: String { "\(kind)-\(key)" }
}

/// A search field that starts as a pill and grows into an input, with results
/// that appear to be extruded out of the bar itself.
///
/// The blob behind the results is a real metaball: `Canvas` blurs the bar and each
/// row together, then `alphaThreshold` re-hardens the edge, so overlapping shapes
/// fuse instead of stacking. The rows are drawn normally on top — thresholding
/// text would destroy it.
struct SearchBar: View {
    @ObservedObject var state: AppState
    var onOpenProject: (String) -> Void
    var onOpenModel: (String) -> Void

    @Local private var expanded = false
    @Local private var query = ""
    @Local private var hits: [SearchHit] = []
    @Local private var hovered: String?
    @FocusState private var focused: Bool

    private let rowHeight: CGFloat = 40
    /// Wide enough to type in without expanding first — a search box that has to
    /// be opened before it is usable is a button pretending to be a field.
    private let collapsedWidth: CGFloat = 264
    private let expandedWidth: CGFloat = 420
    /// Matches the pill control's outer height so the toolbar reads as one row.
    private let barHeight: CGFloat = 42

    var body: some View {
        field
            .frame(width: expanded ? expandedWidth : collapsedWidth, height: barHeight)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expanded)
            // The results hang below the toolbar without displacing it.
            .overlay(alignment: .topLeading) {
                if expanded, !hits.isEmpty {
                    results
                        .offset(y: 48)
                        .transition(.opacity)
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .onChange(of: expanded) { _, isOpen in
                if !isOpen {
                    query = ""
                    hits = []
                } else {
                    focused = true
                }
            }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(expanded ? Theme.accent : Theme.secondaryText)

            if expanded {
                TextField("Search projects and models…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.primaryText)
                    .focused($focused)
                    .onSubmit { openFirst() }

                Button {
                    expanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Text("Search projects and models…")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 15)
        // maxHeight matters: without it the capsule wraps the text's own height
        // and the field renders as a thin outline beside the full-height controls.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.raised)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            expanded ? Theme.accent.opacity(0.55) : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Capsule())
        .onTapGesture { if !expanded { expanded = true } }
    }

    // MARK: - Results

    private var results: some View {
        ZStack(alignment: .top) {
            gooeyBackdrop
            VStack(spacing: 2) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    row(hit, index: index)
                }
            }
            .padding(6)
        }
        .frame(width: expandedWidth)
    }

    /// The bar and every row, blurred together then re-hardened — the shapes fuse
    /// where they overlap, so the panel reads as pulled out of the field.
    private var gooeyBackdrop: some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.42, color: Theme.surface))
            context.addFilter(.blur(radius: 9))
            context.drawLayer { layer in
                // A stub that overlaps the field above, so the two merge.
                layer.fill(
                    Path(roundedRect: CGRect(x: 14, y: -22, width: size.width - 28, height: 40), cornerRadius: 15),
                    with: .color(.white)
                )
                layer.fill(
                    Path(roundedRect: CGRect(x: 0, y: 4, width: size.width, height: max(0, size.height - 8)), cornerRadius: 16),
                    with: .color(.white)
                )
            }
        }
        .frame(height: CGFloat(hits.count) * rowHeight + 14)
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private func row(_ hit: SearchHit, index: Int) -> some View {
        Button {
            open(hit)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hit.kind.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(hit.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Format.compact(hit.tokens))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 9)
            .frame(height: rowHeight - 2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered == hit.id ? Color.white.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? hit.id : nil }
        // Rows arrive staggered, small and soft, then settle.
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .top)
                    .combined(with: .opacity)
                    .combined(with: .offset(y: -10)),
                removal: .opacity
            )
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.7)
                .delay(Double(index) * 0.045),
            value: hits.count
        )
    }

    // MARK: - Searching

    /// Debounced so a fast typist does not rebuild the list on every keystroke.
    private func scheduleSearch() {
        let text = query
        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard text == query else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                hits = search(text)
            }
        }
    }

    private func search(_ text: String) -> [SearchHit] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        let projects = state.rollup.projectsRanked
            .filter { $0.name.lowercased().contains(needle) || $0.path.lowercased().contains(needle) }
            .prefix(5)
            .map {
                SearchHit(
                    kind: .project, title: $0.name,
                    subtitle: "\($0.days.count) days · \($0.byModel.count) models",
                    key: $0.path, tokens: $0.totals.total
                )
            }

        let models = state.rollup.modelsRanked
            .filter { $0.name.lowercased().contains(needle) }
            .prefix(3)
            .map {
                SearchHit(
                    kind: .model, title: $0.name,
                    subtitle: "\($0.days.count) days active",
                    key: $0.name, tokens: $0.totals.total
                )
            }

        return Array(projects) + Array(models)
    }

    private func openFirst() {
        if let first = hits.first { open(first) }
    }

    private func open(_ hit: SearchHit) {
        switch hit.kind {
        case .project: onOpenProject(hit.key)
        case .model: onOpenModel(hit.key)
        }
        expanded = false
    }
}
