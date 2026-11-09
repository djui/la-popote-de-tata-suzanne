import Foundation
import Supabase
import UIKit

/// Photo processing and storage helpers (SPEC §A.15).
///
/// iOS can't encode WebP, so every image the app uploads is a JPEG (`image/jpeg`, `.jpg`).
/// Storage paths are `{uid}/{plats|sources}/{uuid}.jpg` in the `recipe-photos` bucket.
enum ImagePipeline {
    enum Folder: String, Sendable { case plats, sources }

    enum PipelineError: LocalizedError {
        case unreadable, encoding, notSignedIn
        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "Oups, cette photo n'a pas pu être lue")
            case .encoding: String(localized: "Oups, la photo n'a pas pu être envoyée")
            case .notSignedIn: String(localized: "Non connecté")
            }
        }
    }

    /// Size budgets carried over from the website (WebP budgets loosened a little for JPEG).
    struct Budget: Sendable {
        var maxPixel: CGFloat
        var quality: CGFloat
        var maxBytes: Int

        /// Recipe page sent to the AI and kept in `sources/`.
        static let sourcePage = Budget(maxPixel: 1600, quality: 0.8, maxBytes: 500_000)
        /// Dish photo, full size.
        static let dishFull = Budget(maxPixel: 1600, quality: 0.8, maxBytes: 400_000)
        /// Dish photo, list thumbnail.
        static let dishThumb = Budget(maxPixel: 400, quality: 0.75, maxBytes: 60_000)
    }

    // MARK: - Pure geometry

    /// Pixel rectangle for a normalised `box_2d` (`[ymin, xmin, ymax, xmax]`, 0–1000), padded by
    /// `padding` of the image width/height on each side and clamped to the image.
    static func cropRect(box: [Double], imageSize: CGSize, padding: Double = 0.02) -> CGRect? {
        guard box.count == 4, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let w = Double(imageSize.width), h = Double(imageSize.height)
        let ymin = min(box[0], box[2]) / 1000, ymax = max(box[0], box[2]) / 1000
        let xmin = min(box[1], box[3]) / 1000, xmax = max(box[1], box[3]) / 1000
        let x0 = max(0, ((xmin - padding) * w).rounded())
        let y0 = max(0, ((ymin - padding) * h).rounded())
        let x1 = min(w, ((xmax + padding) * w).rounded())
        let y1 = min(h, ((ymax + padding) * h).rounded())
        guard x1 - x0 >= 1, y1 - y0 >= 1 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Target size that fits `size` inside `maxPixel` on its longest side (never upscales).
    static func fittedSize(_ size: CGSize, maxPixel: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return CGSize(width: size.width.rounded(), height: size.height.rounded()) }
        let scale = maxPixel / longest
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    static func dataURL(jpeg: Data) -> String {
        "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    // MARK: - Image operations (thread-safe, call off the main actor for big images)

    /// Redraws the image upright at `size` pixels (scale 1), dropping EXIF orientation.
    static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Pixel size of the image as displayed (orientation applied).
    static func pixelSize(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    static func resized(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let px = pixelSize(image)
        let target = fittedSize(px, maxPixel: maxPixel)
        if target == px, image.imageOrientation == .up, image.scale == 1 { return image }
        return render(image, size: target)
    }

    /// Upright copy at scale 1, so pixel coordinates match `cgImage`.
    static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1 { return image }
        return render(image, size: pixelSize(image))
    }

    /// Crops to a pixel rectangle (in upright coordinates).
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let upright = normalized(image)
        guard let cg = upright.cgImage?.cropping(to: rect.integral) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Crops to an AI detection box with the website's 2 % padding.
    static func crop(_ image: UIImage, box: [Double], padding: Double = 0.02) -> UIImage? {
        guard let rect = cropRect(box: box, imageSize: pixelSize(image), padding: padding) else { return nil }
        return crop(image, to: rect)
    }

    /// Resizes then JPEG-encodes, lowering quality (then size) until it fits the byte budget.
    static func jpeg(_ image: UIImage, budget: Budget) -> Data? {
        var current = resized(image, maxPixel: budget.maxPixel)
        var quality = budget.quality
        var best: Data?
        for _ in 0..<8 {
            guard let data = current.jpegData(compressionQuality: quality) else { return best }
            best = data
            if data.count <= budget.maxBytes { return data }
            if quality > 0.5 {
                quality -= 0.1
            } else {
                let px = pixelSize(current)
                current = render(current, size: fittedSize(px, maxPixel: max(px.width, px.height) * 0.8))
            }
        }
        return best
    }

    /// Full and thumbnail JPEGs of a dish photo.
    static func dishVariants(_ image: UIImage) -> (full: Data, thumb: Data)? {
        guard let full = jpeg(image, budget: .dishFull), let thumb = jpeg(image, budget: .dishThumb) else { return nil }
        return (full, thumb)
    }

    /// Async wrappers that do the heavy lifting off the main actor.
    static func dishVariantsAsync(_ image: UIImage) async -> (full: Data, thumb: Data)? {
        await Task.detached(priority: .userInitiated) { dishVariants(image) }.value
    }

    static func jpegAsync(_ image: UIImage, budget: Budget) async -> Data? {
        await Task.detached(priority: .userInitiated) { jpeg(image, budget: budget) }.value
    }

    static func cropAsync(_ image: UIImage, box: [Double], padding: Double = 0.02) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { crop(image, box: box, padding: padding) }.value
    }

    /// Decodes picker/camera data (HEIC, JPEG, PNG…) into an upright image.
    static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            // Keep page photos at a workable size: 2400 px is plenty for re-cropping a dish.
            return resized(image, maxPixel: 2400)
        }.value
    }

    // MARK: - Storage

    static func newPath(userId: UUID, folder: Folder) -> String {
        "\(userId.uuidString.lowercased())/\(folder.rawValue)/\(UUID().uuidString.lowercased()).jpg"
    }

    /// Uploads a JPEG and returns its storage path.
    static func upload(_ data: Data, folder: Folder, userId: UUID?, client: SupabaseClient) async throws -> String {
        guard let userId else { throw PipelineError.notSignedIn }
        let path = newPath(userId: userId, folder: folder)
        _ = try await client.storage.from(Backend.photoBucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    /// Removes storage objects, ignoring errors (like the website).
    static func remove(_ paths: [String], client: SupabaseClient) async {
        let paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }
        _ = try? await client.storage.from(Backend.photoBucket).remove(paths: paths)
    }
}

/// Tracks every upload made during a form session so uncommitted files can be removed
/// when the user cancels (SPEC §A.15, orphan cleanup).
@MainActor
final class UploadSession {
    /// Paths saved into a recipe row; protected from cleanup for the life of the app.
    static var committedPaths: Set<String> = []

    private(set) var uploaded: [String] = []
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func track(_ paths: [String]) { uploaded.append(contentsOf: paths) }

    static func commit(_ paths: [String?]) {
        committedPaths.formUnion(paths.compactMap { $0 })
    }

    /// Removes the given paths right away when they were uploaded here and never committed.
    func discard(_ paths: [String?]) {
        let doomed = paths.compactMap { $0 }.filter { uploaded.contains($0) && !Self.committedPaths.contains($0) }
        guard !doomed.isEmpty else { return }
        uploaded.removeAll { doomed.contains($0) }
        let client = client
        Task { await ImagePipeline.remove(doomed, client: client) }
    }

    /// Removes every uncommitted upload of this session.
    func cleanup() {
        let doomed = uploaded.filter { !Self.committedPaths.contains($0) }
        uploaded = []
        guard !doomed.isEmpty else { return }
        let client = client
        Task { await ImagePipeline.remove(doomed, client: client) }
    }
}
