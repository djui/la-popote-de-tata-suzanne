import SwiftUI

/// Sign in / sign up, same fields, copy and rules as the website's `/auth` page.
struct AuthView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var inviteCode = ""
    @State private var termsAccepted = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmationSent = false
    @State private var showTerms = false
    @State private var showStory = false
    @FocusState private var focus: Field?

    enum Field { case invite, firstName, email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Wordmark(size: 40)
                        .padding(.top, 40)
                    Text("Les recettes de famille,\npartagées entre tous.")
                        .font(AppFont.body(18))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)

                    if confirmationSent {
                        Text("Jette un œil à ta boîte mail pour confirmer ton compte, puis reviens te connecter.")
                            .font(AppFont.body(16))
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .popoteCard()
                            .padding(.top, 28)
                        Button("Se connecter") {
                            withAnimation { confirmationSent = false; mode = .signIn }
                        }
                        .buttonStyle(.popotePrimary)
                        .padding(.top, 16)
                    } else {
                        form.padding(.top, 30)
                    }

                    Button("Conditions générales d'utilisation") { showTerms = true }
                        .font(AppFont.body(13))
                        .underline()
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 22)

                    Button { showStory = true } label: {
                        Text("Mais qui est Tata Suzanne ?")
                            .font(AppFont.script(22))
                            .foregroundStyle(Palette.primary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .popoteBackground()
            .sheet(isPresented: $showTerms) { NavigationStack { TermsView() } }
            .sheet(isPresented: $showStory) { NavigationStack { StoryView() } }
            .onAppear {
                if let code = router.pendingInvitation, inviteCode.isEmpty { inviteCode = code }
            }
        }
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .signUp {
                labeled("Code d'invitation") {
                    TextField("", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .invite)
                        .submitLabel(.next)
                        .onSubmit { focus = .firstName }
                }
                labeled("Prénom") {
                    TextField("", text: $firstName)
                        .textContentType(.givenName)
                        .focused($focus, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                }
            }
            labeled("Email") {
                TextField("", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            labeled("Mot de passe") {
                SecureField("", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }
            if mode == .signUp {
                Toggle(isOn: $termsAccepted) {
                    HStack(spacing: 4) {
                        Text("J'accepte les")
                        Button("conditions générales d'utilisation") { showTerms = true }
                            .underline()
                    }
                    .font(AppFont.body(14))
                }
                .toggleStyle(CheckboxToggleStyle())
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.body(14, weight: .semibold))
                    .foregroundStyle(Palette.destructive)
                    .transition(.opacity)
            }

            Button {
                Task { await submit() }
            } label: {
                if isWorking {
                    ProgressView().tint(Palette.onPrimary)
                } else {
                    Text(mode == .signIn ? "Se connecter" : "Créer mon compte")
                }
            }
            .buttonStyle(.popotePrimary)
            .disabled(isWorking)
            .padding(.top, 4)

            Button {
                withAnimation(.snappy) {
                    mode = mode == .signIn ? .signUp : .signIn
                    errorMessage = nil
                }
            } label: {
                Text(mode == .signIn ? "Pas encore de compte ? S'inscrire" : "Déjà un compte ? Se connecter")
                    .font(AppFont.body(14))
                    .underline()
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.body(13, weight: .bold))
            content()
                .font(AppFont.body(16))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .popoteCard(radius: 14)
        }
    }

    private func submit() async {
        errorMessage = nil
        if mode == .signUp && !termsAccepted {
            errorMessage = String(localized: "Accepte les conditions générales pour créer ton compte")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            if mode == .signIn {
                try await store.signIn(email: email, password: password)
            } else {
                try await store.signUp(email: email, password: password, firstName: firstName,
                                       inviteCode: inviteCode, termsAccepted: termsAccepted)
                withAnimation { confirmationSent = true }
            }
        } catch {
            withAnimation {
                if mode == .signIn {
                    errorMessage = AppStore.isOfflineError(error)
                        ? String(localized: "Pas de connexion internet.")
                        : String(localized: "Oups, email ou mot de passe incorrect")
                } else {
                    let message = error.localizedDescription
                    errorMessage = message.range(of: "invitation|database error", options: [.regularExpression, .caseInsensitive]) != nil
                        ? String(localized: "Ce code d'invitation n'est pas valide")
                        : message
                }
            }
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Palette.primary : Palette.muted)
                    .imageScale(.large)
                configuration.label
                    .foregroundStyle(Palette.foreground)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("Coché") : Text("Non coché"))
    }
}

/// Blocking sheet shown until terms version 1.0 is accepted (website's terms gate).
struct TermsGateView: View {
    @Environment(AppStore.self) private var store
    @State private var accepted = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Avant de continuer")
                    .font(AppFont.display(26))
                Text("Pour utiliser La Popote, accepte les conditions générales d'utilisation.")
                    .font(AppFont.body(16))
                    .foregroundStyle(Palette.muted)
                NavigationLink("Lire les conditions générales") { TermsView() }
                    .font(AppFont.body(15, weight: .bold))
                Toggle("J'accepte les conditions générales d'utilisation", isOn: $accepted)
                    .toggleStyle(CheckboxToggleStyle())
                    .font(AppFont.body(15))
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Palette.destructive).font(AppFont.body(14))
                }
                Spacer()
                Button {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        do { try await store.acceptTerms() } catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    if isWorking { ProgressView().tint(Palette.onPrimary) } else { Text("Continuer") }
                }
                .buttonStyle(.popotePrimary)
                .disabled(!accepted || isWorking)
                Button("Se déconnecter") { Task { await store.signOut() } }
                    .font(AppFont.body(14))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .popoteBackground()
        }
    }
}
