import QtBridge

extension Path: Shape {
    public nonisolated func path(in rect: CGRect) -> Self { self }
}

public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double
    public var degrees: Double { get { radians * 180 / .pi } set { radians = newValue * .pi / 180 } }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { radians = degrees * .pi / 180 }
    public static let zero = Self(radians: 0)
    public static func radians(_ value: Double) -> Self { Self(radians: value) }
    public static func degrees(_ value: Double) -> Self { Self(degrees: value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.radians < rhs.radians }
}
public struct Gradient: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var color: Color, location: CGFloat
        public init(color: Color, location: CGFloat) { self.color = color; self.location = location }
    }
    public var stops: [Stop]
    public init(stops: [Stop]) { self.stops = stops }
    public init(colors: [Color]) {
        stops = colors.enumerated().map { .init(color: $1, location: CGFloat($0) / CGFloat(max(1, colors.count - 1))) }
    }
}

public struct GraphicsContext {
    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let `repeat` = Self(rawValue: 1), mirror = Self(rawValue: 2), linearColor = Self(rawValue: 4)
    }
    public struct Shading {
        fileprivate enum Paint {
            case style(any ShapeStyle)
            case linear(AnyGradient, CGPoint, CGPoint, GradientOptions)
        }
        fileprivate let paint: Paint
        public static func color(_ color: Color) -> Self { Self(paint: .style(color)) }
        public static func style<S: ShapeStyle>(_ style: S) -> Self { Self(paint: .style(style)) }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = []) -> Self {
            Self(paint: .linear(gradient.colorSpace(.device), startPoint, endPoint, options))
        }
        public static func linearGradient(_ gradient: AnyGradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = []) -> Self {
            Self(paint: .linear(gradient, startPoint, endPoint, options))
        }
    }
    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let opaque = Self(rawValue: 1), dithersResult = Self(rawValue: 2)
    }
    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let linearColor = Self(rawValue: 1)
    }
    public struct Filter: Sendable {
        fileprivate let radius: CGFloat
        fileprivate let options: BlurOptions
        public static func blur(radius: CGFloat, options: BlurOptions = []) -> Self {
            Self(radius: radius, options: options)
        }
    }
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let inverse = Self(rawValue: 1)
    }
    fileprivate struct ClipRegion {
        let bounds: CGRect
        var steps: [(path: Path, evenOdd: Bool, inverse: Bool)] = []

        func withPath<R>(_ body: (OpaquePointer) -> R) -> R {
            Path(bounds).withNativePath { clip in
                for step in steps {
                    step.path.withNativePath { qs_path_clip(clip, $0, step.evenOdd ? 1 : 0, step.inverse ? 1 : 0) }
                }
                return body(clip)
            }
        }
    }
    fileprivate struct Draw {
        let path: Path, shading: Shading, fill: FillStyle, transform: CGAffineTransform
        let opacity: Double, lineWidth: CGFloat?
        let environment: EnvironmentValues
        let clip: ClipRegion
        let filters: [(Filter, FilterOptions)]
    }
    fileprivate final class DisplayList { var drawings: [Draw] = [] }
    fileprivate let list: DisplayList
    fileprivate var region: ClipRegion
    fileprivate var filters: [(Filter, FilterOptions)] = []
    public var environment: EnvironmentValues
    public var opacity: Double = 1
    public var transform = CGAffineTransform.identity
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = transform.scaledBy(x: x, y: y) }
    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = transform.translatedBy(x: x, y: y) }
    public mutating func rotate(by angle: Angle) { transform = transform.rotated(by: angle.radians) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }
    public var clipBoundingRect: CGRect {
        region.withPath { clip in
            let local = qs_path_new()!
            defer { qs_path_delete(local) }
            qs_path_append(local, clip, transform.inverted().native)
            let r = qs_path_bounds(local)
            return r.width < 0 ? .null : CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }
    }
    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = []) {
        region.steps.append((path.applying(transform), style.isEOFilled, options.contains(.inverse)))
    }
    public mutating func addFilter(_ filter: Filter, options: FilterOptions = []) {
        filters.append((filter, options))
    }
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        fill(path.strokedPath(style), with: shading)
    }
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        list.drawings.append(Draw(path: path, shading: shading, fill: style, transform: transform, opacity: opacity, lineWidth: nil, environment: environment, clip: region, filters: filters))
    }
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        if lineWidth > 0 {
            list.drawings.append(Draw(path: path, shading: shading, fill: FillStyle(), transform: transform, opacity: opacity, lineWidth: lineWidth, environment: environment, clip: region, filters: filters))
        }
    }
    @MainActor fileprivate func replay(on widget: UnsafeMutableRawPointer) {
        qs_canvas_clear(widget)
        for drawing in list.drawings {
            drawing.path.withNativePath {
                qs_canvas_path(widget, $0, drawing.transform.native, drawing.opacity, drawing.lineWidth ?? -1,
                               drawing.fill.isEOFilled ? 1 : 0, drawing.fill.isAntialiased ? 1 : 0)
            }
            if !drawing.clip.steps.isEmpty { drawing.clip.withPath { qs_canvas_clip(widget, $0) } }
            for (filter, options) in drawing.filters {
                qs_canvas_blur(widget, filter.radius, filter.options.rawValue, options.rawValue)
            }
            let environment = drawing.environment
            switch drawing.shading.paint {
            case .style(let style):
                switch style.paint(in: environment) {
                case .color(let color): qs_canvas_color(widget, color.hex(environment.colorScheme))
                case .linear(let gradient): gradient.shade(widget, bounds: drawing.path.boundingRect, environment: environment)
                }
            case .linear(let gradient, let start, let end, let options):
                gradient.shade(widget, from: start, to: end, scheme: environment.colorScheme, options: options)
            }
        }
    }
}

public struct Canvas<Symbols: View>: Primitive {
    public var renderer: (inout GraphicsContext, CGSize) -> Void
    public init(renderer: @escaping (inout GraphicsContext, CGSize) -> Void) where Symbols == EmptyView {
        self.renderer = renderer
    }
    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSCanvas)
        return [Element { $0.replacingUnspecifiedDimensions() } place: { bounds, _ in
            var graphics = GraphicsContext(list: .init(), region: .init(bounds: CGRect(origin: .zero, size: bounds.size)), environment: context.environment)
            renderer(&graphics, bounds.size)
            graphics.replay(on: widget)
            qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
        }]
    }
}
extension Shape {
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        stroke(style: StrokeStyle(lineWidth: lineWidth)).fill(content)
    }
}
extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        inset(by: lineWidth / 2).stroke(content, lineWidth: lineWidth)
    }
    public func strokeBorder(lineWidth: CGFloat = 1) -> some View { inset(by: lineWidth / 2).stroke(lineWidth: lineWidth) }
}
private struct InsetGeometry<Base: Shape>: InsettableShape {
    nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { base.layoutDirectionBehavior }
    let base: Base
    let amount: CGFloat
    public nonisolated func path(in rect: CGRect) -> Path { base.path(in: rect.insetBy(dx: amount, dy: amount)) }
    public nonisolated func inset(by amount: CGFloat) -> Self { Self(base: base, amount: self.amount + amount) }
}
extension Rectangle: InsettableShape {
    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape { InsetGeometry(base: self, amount: amount) }
}
extension Ellipse: InsettableShape {
    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape { InsetGeometry(base: self, amount: amount) }
}
extension Circle: InsettableShape {
    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape { InsetGeometry(base: self, amount: amount) }
}
extension Capsule: InsettableShape {
    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape { InsetGeometry(base: self, amount: amount) }
}
extension RoundedRectangle: InsettableShape {
    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape {
        let corners = CGSize(width: max(0, cornerSize.width - amount), height: max(0, cornerSize.height - amount))
        return InsetGeometry(base: RoundedRectangle(cornerSize: corners, style: style), amount: amount)
    }
}
