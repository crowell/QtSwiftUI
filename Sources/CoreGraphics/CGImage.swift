import CoreFoundation

public final class CGDataProvider: @unchecked Sendable {
    public let data: CFData?
    public init?(data: CFData) {
        guard let copy = CFDataCreateCopy(nil, data) else { return nil }
        self.data = copy
    }
}

public final class CGColorSpace: Sendable {
    fileprivate init() {}
    public static var sRGB: CFString {
        CFStringCreateWithCString(nil, "kCGColorSpaceSRGB", CFStringBuiltInEncodings.ASCII.rawValue)
    }
    public init?(name: CFString) {
        guard CFEqual(name, Self.sRGB) else { return nil }
    }
}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}
public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = Self(rawValue: 0x1f)
    public static let floatComponents = Self(rawValue: 1 << 8)
    public static let byteOrderMask = Self(rawValue: 0x7000)
    public static let byteOrderDefault = Self([])
    public static let byteOrder16Little = Self(rawValue: 0x1000)
    public static let byteOrder32Little = Self(rawValue: 0x2000)
    public static let byteOrder16Big = Self(rawValue: 0x3000)
    public static let byteOrder32Big = Self(rawValue: 0x4000)
}
public enum CGImageByteOrderInfo: UInt32, Sendable {
    case orderDefault = 0
    case order16Little = 0x1000, order32Little = 0x2000
    case order16Big = 0x3000, order32Big = 0x4000
    case orderMask = 0x7000
}

public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

public final class CGImage: Sendable {
    public let width, height, bitsPerComponent, bitsPerPixel, bytesPerRow: Int
    public let colorSpace: CGColorSpace?
    public let bitmapInfo: CGBitmapInfo
    public var byteOrderInfo: CGImageByteOrderInfo {
        CGImageByteOrderInfo(rawValue: bitmapInfo.intersection(.byteOrderMask).rawValue) ?? .orderDefault
    }
    public let alphaInfo: CGImageAlphaInfo
    public let dataProvider: CGDataProvider?
    public let shouldInterpolate: Bool
    public let renderingIntent: CGColorRenderingIntent

    /// Device RGB rasters with eight-bit components, optionally including alpha or padding.
    public init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider,
                 decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        guard width > 0, width <= Int(Int32.max), height > 0, height <= Int(Int32.max),
              bitsPerComponent == 8, decode == nil,
              let data = provider.data,
              let alpha = CGImageAlphaInfo(rawValue: bitmapInfo.intersection(.alphaInfoMask).rawValue),
              alpha != .alphaOnly, bitsPerPixel == (alpha == .none ? 24 : 32),
              bitmapInfo.subtracting([.alphaInfoMask, .byteOrderMask]).isEmpty else { return nil }
        let order = bitmapInfo.intersection(.byteOrderMask)
        guard order.isEmpty || (bitsPerPixel == 32 && (order == .byteOrder32Little || order == .byteOrder32Big)),
              bytesPerRow >= width * (bitsPerPixel / 8),
              height <= CFDataGetLength(data) / bytesPerRow else { return nil }
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = bitmapInfo
        self.alphaInfo = alpha
        self.dataProvider = provider
        self.shouldInterpolate = shouldInterpolate
        self.renderingIntent = intent
    }
}
