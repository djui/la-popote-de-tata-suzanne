import SwiftUI

/// Lightweight confirmation / error banner used on the profile screens (the website's toasts).
struct ProfileBanner: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError = false

    static func error(_ text: String) -> ProfileBanner { ProfileBanner(text: text, isError: true) }
}

private struct ProfileBannerModifier: ViewModifier {
    @Binding var banner: ProfileBanner?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let banner {
                    HStack(spacing: 8) {
                        Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(banner.isError ? Palette.destructive : Palette.sage)
                        Text(banner.text)
                            .font(AppFont.body(14, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.foreground)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { self.banner = nil }
                    .accessibilityAddTraits(.isStaticText)
                    .task(id: banner.id) {
                        try? await Task.sleep(for: .seconds(banner.isError ? 5 : 3))
                        if self.banner?.id == banner.id { self.banner = nil }
                    }
                }
            }
            .animation(.snappy, value: banner)
            .sensoryFeedback(trigger: banner) { _, new in
                guard let new else { return nil }
                return new.isError ? .error : .success
            }
    }
}

extension View {
    func profileBanner(_ banner: Binding<ProfileBanner?>) -> some View {
        modifier(ProfileBannerModifier(banner: banner))
    }
}

/// Navy gradient tile with an SF Symbol, like the website's link-card icons.
struct ProfileTile: View {
    let systemImage: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.tileGradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row with a tile, a title and a subtitle.
struct ProfileLinkLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            ProfileTile(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body(16, weight: .bold))
                    .foregroundStyle(Palette.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Section header in Fraunces.
struct ProfileSectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title)
        }
        .font(AppFont.display(19, bold: false, relativeTo: .title3))
        .foregroundStyle(Palette.foreground)
        .textCase(nil)
    }
}

/// Short explanation shown under controls that need the network.
struct OfflineHint: View {
    var body: some View {
        Label("Disponible uniquement en ligne.", systemImage: "icloud.slash")
            .font(AppFont.body(13, relativeTo: .footnote))
            .foregroundStyle(Palette.muted)
    }
}
