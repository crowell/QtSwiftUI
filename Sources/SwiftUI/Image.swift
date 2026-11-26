import CoreFoundation
import QtBridge

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

private struct Raster: Primitive {
    let image: Image

    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSRaster)
        let source = image.source
        let rotated = image.orientation.rawValue >= Image.Orientation.left.rawValue
        let ideal = CGSize(width: CGFloat(rotated ? source.height : source.width) / image.scale,
                           height: CGFloat(rotated ? source.width : source.height) / image.scale)
        if let data = source.dataProvider?.data {
            let smooth = image.interpolation.map { $0 != .none } ?? source.shouldInterpolate
            qs_raster_image(widget, CFDataGetBytePtr(data), Int32(source.width), Int32(source.height), source.bytesPerRow,
                            Int32(source.alphaInfo.rawValue), source.bitmapInfo.contains(.byteOrder32Little) ? 1 : 0,
                            Int32(image.orientation.rawValue), image.scale, smooth ? 1 : 0)
        }
        let rtl = context.environment.layoutDirection == .rightToLeft
        let caps = image.caps
        qs_raster_resize(widget, max(0, rtl ? caps.trailing : caps.leading), max(0, caps.top),
                         max(0, rtl ? caps.leading : caps.trailing), max(0, caps.bottom), image.resizing == .tile ? 1 : 0)
        return [Element { image.resizing == nil ? ideal : $0.replacingUnspecifiedDimensions(by: ideal) } place: { rect, _ in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
        }]
    }
}
