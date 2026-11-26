import QtBridge
import CoreFoundation

private struct SnapshotPixels {
    var data: CFData?
    var bytesPerRow = 0
}

public final class ImageRenderer<Content: View> {
    @MainActor public final var content: Content
    @MainActor public final var proposedSize: ProposedViewSize = .unspecified
    @MainActor public final var scale: CGFloat = 1
    @MainActor public final var isOpaque: Bool = false
    @MainActor private var host: Host?

    @MainActor public init(content view: Content) { content = view }

    @MainActor deinit { host?.close() }

    /// A single raster page in PDF points, rendered in memory at the receiver's scale.
    @_spi(Qt) @MainActor public final func pdfData(pageSize: CGSize) -> Data? {
        guard let cgImage else { return nil }
        var result: Data?
        Image(decorative: cgImage, scale: scale).withRaster(in: EnvironmentValues()) { raster in
            _ = qs_raster_pdf(raster, pageSize.width, pageSize.height, &result) { context, base, count in
                guard let context, let base else { return }
                context.assumingMemoryBound(to: Data?.self).pointee = Data(bytes: base, count: count)
            }
        }
        return result
    }

    @MainActor public final var cgImage: CGImage? {
        guard scale.isFinite, scale > 0 else { return nil }
        let renderer: Host
        if let host { renderer = host }
        else {
            renderer = Host(title: "") { [weak self] in self?.content.resolve($0) ?? [] }
            qs_snapshot_window(renderer.window)
            host = renderer
        }
        let size = renderer.render(proposal: proposedSize, viewport: nil, scale: scale)
        guard let width = Int32(exactly: ceil(size.width * scale)), width > 0,
              let height = Int32(exactly: ceil(size.height * scale)), height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = SnapshotPixels()
        let success = qs_snapshot_pixels(renderer.window, width, height, scale, isOpaque ? 1 : 0, &pixels) { destination, base, length, stride in
            destination?.assumingMemoryBound(to: SnapshotPixels.self).pointee =
                SnapshotPixels(data: CFDataCreate(nil, base, length), bytesPerRow: Int(stride))
        }
        guard success != 0, let data = pixels.data, let provider = CGDataProvider(data: data) else { return nil }
        let alpha: CGImageAlphaInfo = isOpaque ? .noneSkipLast : .premultipliedLast
        return CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.bytesPerRow,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}
