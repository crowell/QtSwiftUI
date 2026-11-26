import QtBridge

extension Gradient {
    public struct ColorSpace: Hashable, Sendable {
        fileprivate let mode: GradientInterpolation
        public static let device = Self(mode: .device)
        public static let perceptual = Self(mode: .perceptual)
    }

    public func colorSpace(_ space: ColorSpace) -> AnyGradient {
        AnyGradient(self).colorSpace(space)
    }
}

public struct AnyGradient: Hashable, ShapeStyle, Sendable {
    let gradient: Gradient
    var space = Gradient.ColorSpace.perceptual

    public init(_ gradient: Gradient) { self.gradient = gradient }
    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient {
        var copy = self
        copy.space = space
        return copy
    }

    public func resolve(in environment: EnvironmentValues) -> LinearGradient {
        LinearGradient(self, startPoint: .top, endPoint: .bottom)
    }

    func stops(for scheme: ColorScheme) -> [QSGradientStop] { space.mode.stops(gradient.stops, scheme: scheme) }

    @MainActor func shade(_ widget: UnsafeMutableRawPointer, from start: CGPoint, to end: CGPoint,
                          scheme: ColorScheme, options: GraphicsContext.GradientOptions = []) {
        guard gradient.stops.count > 1 else {
            qs_canvas_color(widget, (gradient.stops.first?.color ?? .clear).hex(scheme))
            return
        }
        let mode = options.contains(.linearColor) ? .linear : space.mode
        let stops = mode.stops(gradient.stops, scheme: scheme)
        stops.withUnsafeBufferPointer {
            qs_canvas_gradient(widget, start.x, start.y, end.x, end.y, options.rawValue, $0.baseAddress, $0.count)
        }
    }
}

extension Gradient: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> AnyGradient { AnyGradient(self) }
}

public struct AnyShapeStyle: ShapeStyle, Sendable {
    private let base: any ShapeStyle
    public init<S: ShapeStyle>(_ style: S) { base = style }
    public func resolve(in environment: EnvironmentValues) -> Self { self }
    func resolvedPaint(in environment: EnvironmentValues) -> ResolvedPaint { base.paint(in: environment) }
}

// Qt gradients interpolate premultiplied device RGB. Supply intermediate stops
// for linear-light RGB and Oklab so curved channel values survive Qt's lookup table.
private enum GradientInterpolation: Hashable, Sendable {
    case device, linear, perceptual

    func stops(_ input: [Gradient.Stop], scheme: ColorScheme) -> [QSGradientStop] {
        let ordered = input.filter { $0.location.isFinite }.sorted { $0.location < $1.location }
        var result: [QSGradientStop] = []
        var last: (location: Double, argb: UInt32)?
        for stop in ordered {
            let location = Double(min(1, max(0, stop.location)))
            let argb = stop.color.argb(scheme)
            if let last, self != .device, last.argb & 0xffffff != argb & 0xffffff {
                let divisions = Int(ceil((location - last.location) * 64))
                if divisions > 1 {
                    let first = components(last.argb), second = components(argb)
                    for index in 1..<divisions {
                        let t = Double(index) / Double(divisions)
                        let alpha = first.alpha * (1 - t) + second.alpha * t
                        let rgb = alpha > 0 ? (first.rgb * (first.alpha * (1 - t)) + second.rgb * (second.alpha * t)) / alpha : .zero
                        result.append(QSGradientStop(location: last.location + t * (location - last.location), argb: pack(rgb, alpha: alpha)))
                    }
                }
            }
            result.append(QSGradientStop(location: location, argb: argb))
            last = (location, argb)
        }
        return result
    }

    private func components(_ argb: UInt32) -> (rgb: SIMD3<Double>, alpha: Double) {
        func channel(_ shift: Int) -> Double {
            let value = Double(argb >> shift & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = channel(16), g = channel(8), b = channel(0)
        let alpha = Double(argb >> 24) / 255
        guard self == .perceptual else { return (SIMD3(r, g, b), alpha) }
        let l = cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
        let m = cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
        let s = cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
        return (SIMD3(0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
                      1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
                      0.0259040371*l + 0.7827717662*m - 0.8086757660*s), alpha)
    }

    private func pack(_ color: SIMD3<Double>, alpha: Double) -> UInt32 {
        let rgb: SIMD3<Double>
        if self == .perceptual {
            let l = color.x + 0.3963377774*color.y + 0.2158037573*color.z
            let m = color.x - 0.1055613458*color.y - 0.0638541728*color.z
            let s = color.x - 0.0894841775*color.y - 1.2914855480*color.z
            let l3 = l*l*l, m3 = m*m*m, s3 = s*s*s
            rgb = SIMD3(4.0767416621*l3 - 3.3077115913*m3 + 0.2309699292*s3,
                        -1.2684380046*l3 + 2.6097574011*m3 - 0.3413193965*s3,
                        -0.0041960863*l3 - 0.7034186147*m3 + 1.7076147010*s3)
        } else { rgb = color }
        func byte(_ linear: Double) -> UInt32 {
            let value = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1/2.4) - 0.055
            return UInt32((min(1, max(0, value)) * 255).rounded())
        }
        return UInt32((alpha * 255).rounded()) << 24 | byte(rgb.x) << 16 | byte(rgb.y) << 8 | byte(rgb.z)
    }
}
