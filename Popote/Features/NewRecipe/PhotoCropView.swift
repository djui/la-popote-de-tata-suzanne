import SwiftUI
import UIKit

/// Maths for a react-easy-crop-style cropper: a fixed frame, the image pans and zooms underneath.
struct CropGeometry: Equatable {
    var imageSize: CGSize
    var frameSize: CGSize
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    static let zoomRange: ClosedRange<CGFloat> = 1...3

    /// Scale at which the image just covers the frame.
    var baseScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
    }

    var scale: CGFloat { baseScale * zoom }

    var displayedSize: CGSize { CGSize(width: imageSize.width * scale, height: imageSize.height * scale) }

    /// Keeps the image covering the frame.
    func clamped(_ o: CGSize) -> CGSize {
        let maxX = max(0, (displayedSize.width - frameSize.width) / 2)
        let maxY = max(0, (displayedSize.height - frameSize.height) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    /// The crop rectangle in image pixels.
    var cropRect: CGRect {
        let s = scale
        guard s > 0 else { return .zero }
        let o = clamped(offset)
        let x = ((displayedSize.width - frameSize.width) / 2 - o.width) / s
        let y = ((displayedSize.height - frameSize.height) / 2 - o.height) / s
        let rect = CGRect(x: x, y: y, width: frameSize.width / s, height: frameSize.height / s)
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Positions zoom and offset so `rect` (image pixels) fills the frame as well as possible.
    mutating func focus(on rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let z = min(frameSize.width / (rect.width * baseScale), frameSize.height / (rect.height * baseScale))
        zoom = min(max(z, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let s = scale
        offset = clamped(CGSize(width: (imageSize.width / 2 - rect.midX) * s, height: (imageSize.height / 2 - rect.midY) * s))
    }
}

/// "Recadre ta photo" (SPEC §A.16 crop dialog).
struct PhotoCropView: View {
    let image: UIImage
    var initialBox: [Double]?
    let onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var aspect: CGFloat = 1
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var frameSize: CGSize = .zero
    @State private var didFocus = false
    @State private var working = false

    private var imageSize: CGSize { ImagePipeline.pixelSize(image) }

    private var geometry: CropGeometry {
        CropGeometry(imageSize: imageSize, frameSize: frameSize, zoom: zoom, offset: offset)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker(selection: $aspect) {
                    Text("Carré").tag(CGFloat(1))
                    Text("Paysage").tag(CGFloat(4.0 / 3.0))
                    Text("Portrait").tag(CGFloat(3.0 / 4.0))
                } label: { EmptyView() }
                .pickerStyle(.segmented)

                GeometryReader { proxy in
                    let size = fitted(in: proxy.size)
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: geometryFor(size).displayedSize.width, height: geometryFor(size).displayedSize.height)
                            .offset(geometryFor(size).clamped(offset))
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    .contentShape(Rectangle())
                    .gesture(drag(size).simultaneously(with: magnify))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { frameSize = size; focusIfNeeded() }
                    .onChange(of: size) { _, new in
                        frameSize = new
                        offset = geometryFor(new).clamped(offset)
                    }
                }
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(Palette.muted)
                    Slider(value: $zoom, in: CropGeometry.zoomRange, step: 0.05) { Text("Zoom") }
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(Palette.muted)
                }
                .onChange(of: zoom) { _, _ in offset = geometry.clamped(offset) }

                HStack(spacing: 12) {
                    Button("Garder telle quelle") { finish(image) }
                        .buttonStyle(.popoteSecondary)
                    Button("Valider") { validate() }
                        .buttonStyle(.popotePrimary)
                }
                .disabled(working)
            }
            .padding()
            .popoteBackground()
            .navigationTitle("Recadre ta photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func fitted(in available: CGSize) -> CGSize {
        let pad: CGFloat = 12
        let w = max(1, available.width - pad * 2), h = max(1, available.height - pad * 2)
        return w / h > aspect ? CGSize(width: h * aspect, height: h) : CGSize(width: w, height: w / aspect)
    }

    private func geometryFor(_ size: CGSize) -> CropGeometry {
        CropGeometry(imageSize: imageSize, frameSize: size, zoom: zoom, offset: offset)
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = offset }
                offset = geometryFor(size).clamped(CGSize(width: start.width + value.translation.width,
                                                          height: start.height + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                if zoomStart == nil { zoomStart = zoom }
                zoom = min(max(start * value.magnification, CropGeometry.zoomRange.lowerBound), CropGeometry.zoomRange.upperBound)
            }
            .onEnded { _ in zoomStart = nil; offset = geometry.clamped(offset) }
    }

    private func focusIfNeeded() {
        guard !didFocus, let box = initialBox,
              let rect = ImagePipeline.cropRect(box: box, imageSize: imageSize, padding: 0.02) else { return }
        didFocus = true
        let ratio = rect.width / max(rect.height, 1)
        aspect = ratio > 1.15 ? 4.0 / 3.0 : (ratio < 0.87 ? 3.0 / 4.0 : 1)
        // The frame size follows the aspect on the next layout pass; focus once it's known.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            var g = geometry
            g.focus(on: rect)
            zoom = g.zoom
            offset = g.offset
        }
    }

    private func validate() {
        let rect = geometry.cropRect
        working = true
        Task {
            let cropped = await Task.detached(priority: .userInitiated) { [image] in
                ImagePipeline.crop(image, to: rect)
            }.value
            working = false
            finish(cropped ?? image)
        }
    }

    private func finish(_ result: UIImage) {
        onDone(result)
        dismiss()
    }
}
