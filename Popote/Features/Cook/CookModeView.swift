import SwiftUI
import UIKit

/// `/recettes/$id/cuisiner` (SPEC §A.3): full-screen, always dark, step by step with timers.
struct CookModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    let recipe: Recipe
    /// Servings from the menu (`?p=`); otherwise the recipe's own.
    var initialServings: Int?
    /// Called after "Laisser un commentaire" closes cook mode.
    var onLeaveComment: (() -> Void)?

    @State private var page = 0
    @State private var struck: Set<Int> = []
    @State private var servings: Int
    @State private var timers: CookTimerCenter
    @State private var restoreOffer: SavedCookSession?
    @State private var restoreChecked = false
    @State private var showAllSteps = false
    @State private var showIngredients = false
    @State private var showEdit = false
    @State private var toast: String?

    init(recipe: Recipe, initialServings: Int? = nil, onLeaveComment: (() -> Void)? = nil) {
        self.recipe = recipe
        self.initialServings = initialServings
        self.onLeaveComment = onLeaveComment
        let p = initialServings.flatMap { (1..<100).contains($0) ? $0 : nil }
        _servings = State(initialValue: p ?? recipe.servings ?? 4)
        _timers = State(initialValue: CookTimerCenter(recipeId: recipe.id, recipeTitle: recipe.title))
    }

    private var steps: [RecipeStep] { store.stepsByRecipe[recipe.id] ?? [] }
    private var ingredients: [RecipeIngredient] { store.ingredientsByRecipe[recipe.id] ?? [] }
    private var isFinished: Bool { !steps.isEmpty && page >= steps.count }
    private var sideBySide: Bool { hSize == .regular }

    var body: some View {
        VStack(spacing: 0) {
            header
            if steps.isEmpty {
                ContentUnavailableView("Cette recette n'a pas encore d'étapes.", systemImage: "list.number")
                    .foregroundStyle(Palette.cookForeground)
            } else if sideBySide {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView { ingredientsPanel.padding(20) }
                        .frame(maxWidth: 380)
                        .background(Palette.cookCard.opacity(0.5), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    stepsPanel
                }
                .padding(.horizontal, 20)
            } else {
                stepsPanel
            }
            timerTray
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.cookBackground.ignoresSafeArea())
        .foregroundStyle(Palette.cookForeground)
        .tint(Palette.lemon)
        .preferredColorScheme(.dark)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "popote-timer", let s = Int(url.host() ?? "") else { return .systemAction }
            startTimer(seconds: s)
            return .handled
        })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            checkSavedSession()
            syncStepInfo()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timers.suspend()
        }
        .onChange(of: page) { _, _ in persist(); syncStepInfo() }
        .onChange(of: struck) { _, _ in persist() }
        .onChange(of: servings) { _, _ in persist() }
        .onChange(of: timers.timers) { _, _ in persist() }
        .sensoryFeedback(.impact(weight: .light), trigger: page)
        .sensoryFeedback(.warning, trigger: timers.anyDone) { _, new in new }
        .alert("Reprendre où tu en étais ?", isPresented: Binding(get: { restoreOffer != nil }, set: { if !$0 { restoreOffer = nil } })) {
            Button("Recommencer", role: .cancel) {
                timers.reset(alsoCancel: restoreOffer?.timers.map(\.id) ?? [])
                SavedCookSession.clear(recipe.id)
                restoreOffer = nil
                restoreChecked = true
            }
            Button("Reprendre") { resume() }
        } message: {
            Text("Tu t'étais arrêté·e à l'étape \((restoreOffer?.step ?? 0) + 1).")
        }
        .sheet(isPresented: $showAllSteps) { allStepsSheet }
        .sheet(isPresented: $showIngredients) {
            NavigationStack {
                ScrollView { ingredientsPanel.padding(20) }
                    .background(Palette.cookBackground.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(role: .close) { showIngredients = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
            .foregroundStyle(Palette.cookForeground)
            .tint(Palette.lemon)
        }
        .fullScreenCover(isPresented: $showEdit) { editRecipeEntry(recipeId: recipe.id) }
        .recipeToast($toast, dark: true)
        .statusBarHidden(false)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Quitter le mode cuisine"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(AppFont.display(19, relativeTo: .headline))
                        .lineLimit(1)
                    Text("🔆 Écran maintenu allumé")
                        .font(AppFont.body(12, relativeTo: .caption))
                        .foregroundStyle(Palette.cookMuted)
                }
                Spacer(minLength: 0)
                if !sideBySide, !ingredients.isEmpty {
                    Button { showIngredients = true } label: {
                        Image(systemName: "basket").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Ingrédients"))
                }
            }
            if !steps.isEmpty, !isFinished {
                HStack(spacing: 12) {
                    Text("Étape \(page + 1) / \(steps.count)")
                        .font(AppFont.body(14, weight: .heavy, relativeTo: .subheadline))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(page)))
                    ProgressView(value: Double(page + 1), total: Double(steps.count))
                        .tint(Palette.lemon)
                        .accessibilityLabel(Text("Progression"))
                    Button { showAllSteps = true } label: {
                        Label("Toutes les étapes", systemImage: "list.number")
                            .font(AppFont.body(13, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.lemon)
                }
                .animation(.snappy, value: page)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Steps

    private var stepsPanel: some View {
        TabView(selection: $page) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                stepPage(i, step).tag(i)
            }
            finishPage.tag(steps.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy, value: page)
    }

    private func stepPage(_ index: Int, _ step: RecipeStep) -> some View {
        let matched = StepIngredientMatcher.ingredients(ingredients, for: step.instruction)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(timerAttributed(step.instruction))
                    .font(AppFont.body(sideBySide ? 30 : 26, weight: .semibold, relativeTo: .title))
                    .lineSpacing(6)
                    .tint(Palette.timerForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if !matched.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pour cette étape")
                            .font(AppFont.body(13, weight: .heavy, relativeTo: .caption))
                            .foregroundStyle(Palette.cookMuted)
                        RecipeFlowLayout {
                            ForEach(matched) { ing in
                                let f = Quantity.formatIngredient(Quantity.scale(ing.quantity, base: recipe.servings, target: servings),
                                                                  unit: ing.unit, name: ing.name)
                                HStack(spacing: 5) {
                                    if !f.qty.isEmpty { Text(f.qty).fontWeight(.heavy).foregroundStyle(Palette.lemon) }
                                    Text(f.name)
                                }
                                .font(AppFont.body(16, relativeTo: .body))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Palette.cookBackground, in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.cookCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, sideBySide ? 8 : 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    /// Step text with detected durations rendered as tappable timer pills (`popote-timer://<seconds>` links).
    private func timerAttributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for m in CookTimerParser.detect(text) {
            result += AttributedString(String(text[cursor..<m.range.lowerBound]))
            for (k, s) in m.seconds.enumerated() {
                if k > 0 { result += AttributedString(" – ") }
                var pill = AttributedString("\u{00A0}⏱\u{00A0}" + CookTimerParser.format(s).replacingOccurrences(of: " ", with: "\u{00A0}") + "\u{00A0}")
                pill.link = URL(string: "popote-timer://\(s)")
                pill.backgroundColor = Palette.timerBackground
                pill.foregroundColor = Palette.timerForeground
                result += pill
            }
            cursor = m.range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    // MARK: Finish

    private var finishPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(verbatim: "🍽️").font(.system(size: 64))
                Text("Bon appétit !")
                    .font(AppFont.script(48))
                    .foregroundStyle(Palette.lemon)
                VStack(spacing: 12) {
                    Text("Ça t'a plu ?").font(AppFont.body(17, weight: .heavy))
                    RecipeStarInput(value: store.myRatings[recipe.id], starSize: 34, tint: Palette.lemon, mutedTint: Palette.cookMuted) { stars in
                        store.setRating(recipe.id, stars: stars)
                        if stars != nil { toast = String(localized: "Merci pour ta note !") }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Palette.cookCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if store.canEdit(recipe) {
                    Button {
                        clearSession()
                        showEdit = true
                    } label: {
                        Label("Ajouter une photo de mon plat", systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.lemon)
                    .disabled(!store.isOnline)
                }
                Button {
                    clearSession()
                    dismiss()
                    onLeaveComment?()
                } label: {
                    Label("Laisser un commentaire", systemImage: "message")
                }
                .buttonStyle(.plain)
                .font(AppFont.body(16, weight: .bold))
                .foregroundStyle(Palette.lemon)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Ingredients

    private var ingredientsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ingrédients").font(AppFont.display(24, relativeTo: .title2))
                Spacer()
            }
            ServingsStepperPill(value: $servings, foreground: Palette.cookForeground, background: Palette.cookCard, large: true,
                                minusLabel: "Moins de personnes", plusLabel: "Plus de personnes")
            VStack(spacing: 0) {
                ForEach(Array(ingredients.enumerated()), id: \.element.id) { i, ing in
                    let f = Quantity.formatIngredient(Quantity.scale(ing.quantity, base: recipe.servings, target: servings),
                                                      unit: ing.unit, name: ing.name)
                    Button {
                        if struck.contains(i) { struck.remove(i) } else { struck.insert(i) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(f.qty)
                                .fontWeight(.heavy)
                                .foregroundStyle(Palette.lemon)
                                .frame(width: 100, alignment: .leading)
                            Text(f.name + (ing.optional == true ? String(localized: " (facultatif)") : ""))
                            Spacer(minLength: 0)
                        }
                        .font(AppFont.body(19, relativeTo: .title3))
                        .strikethrough(struck.contains(i))
                        .opacity(struck.contains(i) ? 0.4 : 1)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(struck.contains(i) ? .isSelected : [])
                    .sensoryFeedback(.selection, trigger: struck.contains(i))
                    Divider().overlay(Palette.cookMuted.opacity(0.3))
                }
            }
            if !struck.isEmpty {
                Button { withAnimation { struck = [] } } label: {
                    Label("Tout décocher", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .animation(.snappy, value: struck)
    }

    // MARK: Timers

    @ViewBuilder private var timerTray: some View {
        if !timers.timers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(timers.timers) { t in timerCard(t) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func timerCard(_ t: CookTimer) -> some View {
        let left = t.secondsLeft(at: timers.now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(t.label)
                .font(AppFont.body(13, weight: .bold, relativeTo: .caption))
                .lineLimit(1)
                .foregroundStyle(t.done ? .white : Palette.timerForeground)
            if t.done {
                Text("Terminé !").font(AppFont.body(26, weight: .heavy)).foregroundStyle(.white)
                Button("Arrêter") { timers.remove(t.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Palette.destructive)
            } else {
                Text(verbatim: CookTimerParser.clock(left))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel(Text(CookTimerParser.format(left)))
                HStack(spacing: 8) {
                    Button { timers.togglePause(t.id) } label: {
                        Image(systemName: t.isPaused ? "play.fill" : "pause.fill").frame(width: 34, height: 30)
                    }
                    .accessibilityLabel(t.isPaused ? Text("Reprendre") : Text("Pause"))
                    Button { timers.addMinute(t.id) } label: {
                        Text(verbatim: "+1 min").font(AppFont.body(13, weight: .heavy)).frame(height: 30)
                    }
                    .accessibilityLabel(Text("Ajouter une minute"))
                    Spacer(minLength: 0)
                    Button { timers.remove(t.id) } label: {
                        Image(systemName: "xmark").frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(Text("Annuler le minuteur"))
                }
                .buttonStyle(.bordered)
                .tint(Palette.timerForeground)
            }
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .background(t.done ? Palette.destructive : Palette.timerBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .phaseAnimator(t.done ? [false, true] : [false]) { content, phase in
            content.scaleEffect(phase ? 1.03 : 1)
        } animation: { _ in .easeInOut(duration: 0.6) }
        .accessibilityElement(children: .contain)
    }

    private func startTimer(seconds: Int, stepIndex: Int? = nil, matched: [RecipeIngredient]? = nil) {
        let index = stepIndex ?? min(page, max(0, steps.count - 1))
        guard steps.indices.contains(index) else { return }
        let text = steps[index].instruction
        let m = matched ?? StepIngredientMatcher.ingredients(ingredients, for: text)
        let label = CookTimerParser.label(stepText: text, stepIndex: index, matchedIngredient: m.first?.name)
        withAnimation(.snappy) { timers.start(label: label, seconds: seconds) }
        toast = "⏱ \(label) : \(CookTimerParser.format(seconds))"
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if isFinished {
                Button("Revoir la dernière étape") { page = max(0, steps.count - 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Terminer") {
                    clearSession()
                    dismiss()
                }
                .buttonStyle(.popotePrimary)
            } else if !steps.isEmpty {
                Button { page = max(0, page - 1) } label: {
                    Label("Précédente", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(page == 0)
                Button { page += 1 } label: {
                    if page == steps.count - 1 {
                        Text("Terminer")
                    } else {
                        Label("Suivante", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                    }
                }
                .buttonStyle(.popotePrimary)
            } else {
                Button("Terminer") { dismiss() }.buttonStyle(.popotePrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .environment(\.colorScheme, .dark)
    }

    // MARK: All steps

    private var allStepsSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        Button {
                            page = i
                            showAllSteps = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Étape \(i + 1)")
                                    .font(AppFont.body(13, weight: .heavy))
                                    .foregroundStyle(Palette.lemon)
                                Text(step.instruction)
                                    .font(AppFont.body(16))
                                    .foregroundStyle(Palette.cookForeground)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(i == page ? Palette.cookCard : Palette.cookBackground)
                        .overlay(alignment: .leading) {
                            if i == page { Rectangle().fill(Palette.lemon).frame(width: 3).offset(x: -16) }
                        }
                        .id(i)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.cookBackground.ignoresSafeArea())
                .onAppear { proxy.scrollTo(min(page, steps.count - 1), anchor: .center) }
            }
            .navigationTitle("Toutes les étapes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { showAllSteps = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.lemon)
    }

    // MARK: Session

    private func checkSavedSession() {
        guard !restoreChecked, restoreOffer == nil else { return }
        if let saved = SavedCookSession.load(recipe.id), saved.isWorthResuming {
            restoreOffer = saved
        } else {
            restoreChecked = true
        }
    }

    private func resume() {
        guard let s = restoreOffer else { return }
        page = min(max(0, s.step), steps.count)
        struck = Set(s.struck.filter { ingredients.indices.contains($0) })
        if initialServings == nil { servings = max(1, s.servings) }
        timers.restore(s.timers)
        restoreOffer = nil
        restoreChecked = true
        persist()
    }

    private func persist() {
        guard restoreChecked else { return }
        SavedCookSession(step: page, struck: Array(struck).sorted(), servings: servings, timers: timers.timers, savedAt: .now)
            .save(recipe.id)
    }

    private func clearSession() {
        timers.reset()
        SavedCookSession.clear(recipe.id)
        restoreChecked = false
    }

    private func syncStepInfo() {
        guard !steps.isEmpty else { return }
        let i = min(page, steps.count - 1)
        timers.stepInfo = (i, steps.count, steps[i].instruction)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
