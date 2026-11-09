import AVKit
import SwiftUI

/// "L'histoire de Tata Suzanne" (/histoire, SPEC §C.10) with the teaser video (§A.15).
struct StoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    private typealias S = LegalTexts.Story

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                TeaserVideo()

                section(S.whoTitle, systemImage: "frying.pan") {
                    paragraph(S.who1)
                    paragraph(S.who2)
                    HStack(spacing: 18) {
                        PostIt(color: Color(hex: 0xEBC85C), angle: -4) {
                            Text(verbatim: "Gratin de Mamie, p. 42 !")
                        }
                        PostIt(color: Color(hex: 0xEE9A86), angle: 5) {
                            Text(S.postit2.current)
                        }
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                }

                section(S.bazarTitle, systemImage: "iphone") {
                    paragraph(S.bazar1)
                    PostIt(color: Color(hex: 0xB9CBAA), angle: -1.5) {
                        Label {
                            Text(S.bazarPostit.current)
                        } icon: {
                            Image(systemName: "list.clipboard")
                        }
                    }
                    .padding(.top, 4)
                }

                section(S.ideaTitle, systemImage: "cooktop") {
                    paragraph(S.idea1)
                    paragraph(S.idea2)
                    paragraph(S.idea3)
                }

                section(S.chefTitle, systemImage: "sparkles") {
                    paragraph(S.chef1)
                }

                section(S.nextTitle, systemImage: "newspaper") {
                    paragraph(S.next1)
                }

                closing
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .popoteBackground()
        .navigationTitle("Tata Suzanne")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(S.title.current)
                .font(AppFont.display(32, relativeTo: .largeTitle))
                .foregroundStyle(Palette.foreground)
            Text(verbatim: "Tata Suzanne")
                .font(AppFont.script(46))
                .foregroundStyle(Palette.primary)
                .rotationEffect(.degrees(-3))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var closing: some View {
        VStack(spacing: 18) {
            Text(S.thanks.current)
                .font(AppFont.body(17))
            VStack(spacing: 0) {
                Text(S.bonAppetit.current)
                    .font(AppFont.display(24, bold: false))
                Text(verbatim: "Tata Suzanne")
                    .font(AppFont.script(40))
                    .foregroundStyle(Palette.primary)
                    .rotationEffect(.degrees(-4))
            }
            Button(S.browse.current) {
                router.tab = .recipes
                router.recipesPath = []
            }
            .buttonStyle(.popotePrimary)
            .frame(maxWidth: 360)
            NavigationLink {
                TermsView()
            } label: {
                Text("Conditions générales d'utilisation")
                    .font(AppFont.body(14))
                    .underline()
            }
            .foregroundStyle(Palette.muted)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Palette.foreground)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func section<Content: View>(_ title: LocalizedText, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProfileTile(systemImage: systemImage, size: 40)
                Text(title.current)
                    .font(AppFont.display(23, bold: false, relativeTo: .title2))
                    .foregroundStyle(Palette.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    private func paragraph(_ text: LocalizedText) -> some View {
        Text(text.current)
            .font(AppFont.body(17))
            .foregroundStyle(Palette.foreground)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A slightly rotated paper note. Paper colours are the same in light and dark mode, so the ink stays dark.
private struct PostIt<Content: View>: View {
    let color: Color
    let angle: Double
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(AppFont.script(21, relativeTo: .title3))
            .foregroundStyle(Color(hex: 0x3B2E25))
            .padding(16)
            .frame(maxWidth: 320, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: Color(hex: 0x4A3424).opacity(0.35), radius: 9, y: 8)
            .rotationEffect(.degrees(angle))
    }
}

/// Streams the website's teaser when online (`preload="metadata"`: nothing loads until it is shown).
private struct TeaserVideo: View {
    @Environment(AppStore.self) private var store
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if store.isOnline {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.foreground)
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        ProgressView().tint(Palette.background)
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 10)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Vidéo de présentation de Tata Suzanne"))
                .task {
                    if player == nil { player = AVPlayer(url: LegalTexts.teaserVideo) }
                }
                .onDisappear { player?.pause() }
            }
        }
    }
}
