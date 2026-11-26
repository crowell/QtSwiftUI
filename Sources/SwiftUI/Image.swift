import CoreFoundation
import QtBridge

extension CGImage {
    @_spi(Qt) public static func rgba8(_ pixels: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max), width <= Int.max / 4 else { return nil }
        let rowBytes = width * 4
        guard pixels.count.isMultiple(of: rowBytes), pixels.count / rowBytes == height else { return nil }
        let data = pixels.withUnsafeBytes { bytes in
            CFDataCreate(nil, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard let data, let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: rowBytes, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

public nonisolated struct Image: View, Equatable, Sendable {
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored
    }
    public enum ResizingMode: Hashable, Sendable { case tile, stretch }
    public enum Interpolation: Hashable, Sendable { case none, low, medium, high }

    let source: CGImage
    let scale: CGFloat
    let orientation: Orientation
    private let label: String?
    var caps = EdgeInsets()
    var resizing: ResizingMode?
    var interpolation: Interpolation?

    public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up) {
        self.init(source: cgImage, scale: scale, orientation: orientation, label: nil)
    }

    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up, label: Text) {
        self.init(source: cgImage, scale: scale, orientation: orientation, label: label.string)
    }

    @_spi(Qt) public init?(rgba8 pixels: Data, width: Int, height: Int, scale: CGFloat = 1, orientation: Orientation = .up) {
        guard let cg = CGImage.rgba8(pixels, width: width, height: height) else { return nil }
        self.init(decorative: cg, scale: scale, orientation: orientation)
    }

    private init(source: CGImage, scale: CGFloat, orientation: Orientation, label: String?) {
        self.source = source
        self.scale = scale.isFinite && scale > 0 ? scale : 1
        self.orientation = orientation
        self.label = label
    }

    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        copy.caps = capInsets
        copy.resizing = resizingMode
        return copy
    }

    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolation = interpolation
        return copy
    }

    public static func == (lhs: Image, rhs: Image) -> Bool {
        lhs.source === rhs.source && lhs.scale == rhs.scale && lhs.orientation == rhs.orientation &&
        lhs.label == rhs.label && lhs.caps == rhs.caps && lhs.resizing == rhs.resizing && lhs.interpolation == rhs.interpolation
    }

    @MainActor @ViewBuilder public var body: some View {
        if let label {
            Raster(image: self).accessibilityElement(children: .ignore).accessibilityAddTraits(.isImage).accessibilityLabel(label)
        } else {
            Raster(image: self).accessibilityHidden(true)
        }
    }
}

extension Image {
    var naturalSize: CGSize {
        let rotated = orientation.rawValue >= Orientation.left.rawValue
        return CGSize(width: CGFloat(rotated ? source.height : source.width) / scale,
                      height: CGFloat(rotated ? source.width : source.height) / scale)
    }

    func withRaster(in environment: EnvironmentValues, _ draw: (QSRasterImage) -> Void) {
        guard let data = source.dataProvider?.data else { return }
        let rtl = environment.layoutDirection == .rightToLeft
        let smooth = interpolation.map { $0 != .none } ?? source.shouldInterpolate
        withExtendedLifetime(data) {
            draw(QSRasterImage(bytes: CFDataGetBytePtr(data), width: Int32(source.width), height: Int32(source.height),
                               stride: source.bytesPerRow, alpha: Int32(source.alphaInfo.rawValue),
                               little: source.bitmapInfo.contains(.byteOrder32Little) ? 1 : 0,
                               orientation: Int32(orientation.rawValue), scale: scale, smooth: smooth ? 1 : 0,
                               left: max(0, rtl ? caps.trailing : caps.leading), top: max(0, caps.top),
                               right: max(0, rtl ? caps.leading : caps.trailing), bottom: max(0, caps.bottom),
                               tile: resizing == .tile ? 1 : 0))
        }
    }
}

private struct Raster: Primitive {
    let image: Image

    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSRaster)
        let ideal = image.naturalSize
        image.withRaster(in: context.environment) { qs_raster_image(widget, $0) }
        return [Element { image.resizing == nil ? ideal : $0.replacingUnspecifiedDimensions(by: ideal) } place: { rect, _ in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
        }]
    }
}
