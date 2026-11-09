import PhotosUI
import SwiftUI
import UIKit

/// Category tile with the website's navy gradient (SPEC §A.6 "Category tile component").
struct CategoryTileButton: View {
    let category: RecipeCategory
    var isOn = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 4 : 8) {
                RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous)
                    .fill(Palette.tileGradient)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: category.symbol)
                            .font(.system(size: compact ? 22 : 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .overlay {
                        if isOn {
                            RoundedRectangle(cornerRadius: compact ? 14 : 20, style: .continuous)
                                .strokeBorder(Palette.foreground.opacity(0.8), lineWidth: compact ? 3 : 4)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isOn && compact {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Palette.tileBottom, Palette.lemon)
                                .font(.system(size: 16))
                                .padding(4)
                        }
                    }
                Text(category.label)
                    .font(AppFont.body(compact ? 11 : 13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(category.label))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A large source tile ("Photo", "Coller un texte", "Lien web").
struct SourceTile: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    let systemImage: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.tileGradient)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AppFont.display(20, relativeTo: .title3))
                    Text(hint).font(AppFont.body(14)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.foreground)
            .padding(14)
            .popoteCard(radius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// Shown above online-only actions when the device is offline.
struct NewRecipeOfflineNotice: View {
    var message: LocalizedStringKey = "Tu es hors ligne : l'import automatique et l'enregistrement d'une recette demandent une connexion."
    var body: some View {
        Label { Text(message) } icon: { Image(systemName: "icloud.slash") }
            .font(AppFont.body(14, weight: .semibold))
            .foregroundStyle(Palette.foreground)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.warning.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Inline error box (SPEC §N.4 "Error box").
struct InlineErrorBox<Accessory: View>: View {
    let message: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(message) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.destructive) }
                .font(AppFont.body(14))
            accessory
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoteCard(radius: 18)
    }
}

extension InlineErrorBox where Accessory == EmptyView {
    init(message: String) { self.init(message: message) { EmptyView() } }
}

/// Camera capture via UIImagePickerController.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension PhotosPickerItem {
    /// Loads the picked photo (HEIC, JPEG, PNG…) as an upright image.
    func loadImage() async -> UIImage? {
        guard let data = try? await loadTransferable(type: Data.self) else { return nil }
        return await ImagePipeline.decode(data)
    }
}

/// Friendly rotating messages while the AI works (it can take 30–90 s).
struct AIProgressView: View {
    let title: LocalizedStringKey
    var progress: Double?
    @State private var index = 0

    private static let messages: [LocalizedStringKey] = [
        "Tata Suzanne chausse ses lunettes…",
        "Elle déchiffre la liste des ingrédients…",
        "Elle remet les étapes dans l'ordre…",
        "Elle cherche la photo du plat…",
        "Encore un petit instant, ça mijote…",
        "Presque prêt !",
    ]

    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: progress.map { min(max($0, 0), 1) })
                .progressViewStyle(.linear)
                .tint(Palette.primary)
                .opacity(progress == nil ? 0 : 1)
            HStack(spacing: 10) {
                ProgressView()
                Text(title).font(AppFont.body(16, weight: .bold))
            }
            Text(Self.messages[index % Self.messages.count])
                .font(AppFont.body(14))
                .foregroundStyle(Palette.muted)
                .contentTransition(.opacity)
                .id(index)
                .transition(.opacity)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .popoteCard(radius: 20)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeInOut(duration: 0.4)) { index += 1 }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Reads plain text from the pasteboard.
@MainActor
enum Clipboard {
    static var string: String? {
        let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return s?.isEmpty == false ? s : nil
    }
}
