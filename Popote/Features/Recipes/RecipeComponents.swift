import SwiftUI

/// Round heart button (SPEC §A.13). Works offline through the store's outbox.
struct RecipeHeartButton: View {
    @Environment(AppStore.self) private var store
    let recipeId: UUID
    var size: CGFloat = 32
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        let on = store.isFavorite(recipeId)
        Button {
            store.toggleFavorite(recipeId)
            onToggle?(!on)
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(on ? Palette.primary : Palette.foreground)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: on)
                .frame(width: size, height: size)
                .background(Palette.card.opacity(0.92), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel(on ? Text("Retirer des favoris") : Text("Ajouter aux favoris"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// `★ 4,5 · 3 avis` or `Pas encore notée` (SPEC §B.1.7).
struct RecipeRatingSummary: View {
    let avg: Double?
    let count: Int?
    var size: CGFloat = 13

    var body: some View {
        if let count, count > 0, let avg {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").foregroundStyle(Palette.primary).imageScale(.small)
                Text(verbatim: RecipeFormat.rating(avg)).fontWeight(.bold)
                Text("· \(count) avis").foregroundStyle(Palette.muted)
            }
            .font(AppFont.body(size, relativeTo: .caption))
            .accessibilityElement(children: .combine)
        } else {
            Text("Pas encore notée")
                .font(AppFont.body(size, relativeTo: .caption))
                .foregroundStyle(Palette.muted)
        }
    }
}

/// Five-star input with `Retirer ma note` (SPEC §A.8).
struct RecipeStarInput: View {
    let value: Int?
    var starSize: CGFloat = 28
    var tint: Color = Palette.primary
    var mutedTint: Color = Palette.muted
    let onChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        onChange(n)
                    } label: {
                        Image(systemName: n <= (value ?? 0) ? "star.fill" : "star")
                            .font(.system(size: starSize * 0.8))
                            .foregroundStyle(n <= (value ?? 0) ? tint : mutedTint)
                            .frame(width: starSize + 6, height: starSize + 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n == 1 ? Text("1 étoile") : Text("\(n) étoiles"))
                    .accessibilityAddTraits(n == value ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: value)
            if value != nil {
                Button {
                    onChange(nil)
                } label: {
                    Label("Retirer ma note", systemImage: "xmark")
                        .font(AppFont.body(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(mutedTint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// − 👥 N + pill. Minimum 1, no maximum.
struct ServingsStepperPill: View {
    @Binding var value: Int
    var foreground: Color = Palette.foreground
    var background: Color = Palette.chip
    var large = false
    var minusLabel: LocalizedStringKey = "Moins"
    var plusLabel: LocalizedStringKey = "Plus"

    var body: some View {
        HStack(spacing: large ? 14 : 8) {
            Button { value = max(1, value - 1) } label: {
                Image(systemName: "minus").frame(width: large ? 44 : 32, height: large ? 44 : 32).contentShape(Rectangle())
            }
            .disabled(value <= 1)
            .accessibilityLabel(Text(minusLabel))
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill").imageScale(.small)
                Text(verbatim: "\(value)").monospacedDigit().contentTransition(.numericText(value: Double(value)))
            }
            .font(AppFont.body(large ? 20 : 15, weight: .heavy))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(value) personnes"))
            Button { value += 1 } label: {
                Image(systemName: "plus").frame(width: large ? 44 : 32, height: large ? 44 : 32).contentShape(Rectangle())
            }
            .accessibilityLabel(Text(plusLabel))
        }
        .font(.system(size: large ? 18 : 14, weight: .bold))
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .background(background, in: Capsule())
        .animation(.snappy, value: value)
        .sensoryFeedback(.increase, trigger: value)
    }
}

/// Simple flow layout for chips.
struct RecipeFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let r = rows.count - 1
            rows[r].width += rows[r].indices.isEmpty ? size.width : size.width + spacing
            rows[r].height = max(rows[r].height, size.height)
            rows[r].indices.append(i)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Toast

/// A lightweight banner shown at the bottom of the screen for a couple of seconds.
struct RecipeToastModifier: ViewModifier {
    @Binding var message: String?
    var dark = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(AppFont.body(15, weight: .bold))
                    .foregroundStyle(dark ? Palette.cookForeground : Palette.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { self.message = nil }
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.6))
                        withAnimation { self.message = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
                    .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
            }
        }
        .animation(.spring(duration: 0.35), value: message)
    }
}

extension View {
    func recipeToast(_ message: Binding<String?>, dark: Bool = false) -> some View {
        modifier(RecipeToastModifier(message: message, dark: dark))
    }
}

/// Inline "offline" explanation used next to online-only actions.
struct OfflineNotice: View {
    var text: LocalizedStringKey = "Hors ligne : cette action sera possible au retour du réseau."
    var body: some View {
        Label(text, systemImage: "icloud.slash")
            .font(AppFont.body(13, relativeTo: .footnote))
            .foregroundStyle(Palette.muted)
    }
}
