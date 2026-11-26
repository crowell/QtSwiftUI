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

@MainActor public struct GraphicsContext {
    public struct Shading {
        fileprivate enum Paint {
            case style(any ShapeStyle)
            case linear(Gradient, CGPoint, CGPoint)
        }
        fileprivate let paint: Paint
        public static func color(_ color: Color) -> Self { Self(paint: .style(color)) }
        public static func style<S: ShapeStyle>(_ style: S) -> Self { Self(paint: .style(style)) }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint) -> Self {
            Self(paint: .linear(gradient, startPoint, endPoint))
        }
    }
    fileprivate struct Draw {
        let path: Path, shading: Shading, fill: FillStyle, transform: CGAffineTransform
        let opacity: Double, lineWidth: CGFloat?
        let environment: EnvironmentValues
    }
    fileprivate final class DisplayList { var drawings: [Draw] = [] }
    fileprivate let list: DisplayList
    public var environment: EnvironmentValues
    public var opacity: Double = 1
    public var transform = CGAffineTransform.identity
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = transform.scaledBy(x: x, y: y) }
    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = transform.translatedBy(x: x, y: y) }
    public mutating func rotate(by angle: Angle) { transform = transform.rotated(by: angle.radians) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        list.drawings.append(Draw(path: path, shading: shading, fill: style, transform: transform, opacity: opacity, lineWidth: nil, environment: environment))
    }
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        if lineWidth > 0 {
            list.drawings.append(Draw(path: path, shading: shading, fill: FillStyle(), transform: transform, opacity: opacity, lineWidth: lineWidth, environment: environment))
        }
    }
    fileprivate func replay(on widget: UnsafeMutableRawPointer) {
        qs_canvas_clear(widget)
        for drawing in list.drawings {
            drawing.path.withNativePath {
                qs_canvas_path(widget, $0, drawing.transform.native, drawing.opacity, drawing.lineWidth ?? -1,
                               drawing.fill.isEOFilled ? 1 : 0, drawing.fill.isAntialiased ? 1 : 0)
            }
            let environment = drawing.environment
            switch drawing.shading.paint {
            case .style(let style): qs_canvas_color(widget, style.color(in: environment).hex(environment.colorScheme))
            case .linear(let gradient, let start, let end):
                qs_canvas_gradient(widget, start.x, start.y, end.x, end.y)
                for stop in gradient.stops { qs_canvas_stop(widget, stop.location, stop.color.hex(environment.colorScheme)) }
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
            var graphics = GraphicsContext(list: .init(), environment: context.environment)
            renderer(&graphics, bounds.size)
            graphics.replay(on: widget)
            qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
        }]
    }
}
extension Shape {
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        Canvas { context, size in context.stroke(path(in: CGRect(origin: .zero, size: size)), with: .style(content), lineWidth: lineWidth) }
    }
    public func stroke(lineWidth: CGFloat = 1) -> some View {
        Canvas { context, size in
            context.stroke(path(in: CGRect(origin: .zero, size: size)), with: .color(context.environment.foreground), lineWidth: lineWidth)
        }
    }
}
extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        inset(by: lineWidth / 2).stroke(content, lineWidth: lineWidth)
    }
    public func strokeBorder(lineWidth: CGFloat = 1) -> some View { inset(by: lineWidth / 2).stroke(lineWidth: lineWidth) }
}
private struct InsetGeometry<Base: Shape>: InsettableShape {
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
