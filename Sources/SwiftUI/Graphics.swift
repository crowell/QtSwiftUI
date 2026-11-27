import QtBridge

public protocol ShapeStyle: Sendable {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
}
extension Never: ShapeStyle {}

extension ShapeStyle where Resolved == Never {
    public func resolve(in environment: EnvironmentValues) -> Never { fatalError("Primitive shape styles are rendered directly") }
}

extension ShapeStyle {
    func paint(in environment: EnvironmentValues) -> ResolvedPaint {
        if let color = self as? Color { return .color(color) }
        if let components = self as? Color.Resolved { return .color(components.color) }
        if let gradient = self as? LinearGradient { return .linear(gradient) }
        if let material = self as? Material { return .material(material) }
        if let erased = self as? AnyShapeStyle { return erased.resolvedPaint(in: environment) }
        return resolve(in: environment).paint(in: environment)
    }
}

enum ResolvedPaint: Sendable {
    case color(Color), linear(LinearGradient), material(Material)

    var representativeColor: Color {
        switch self {
        case .color(let color): color
        case .material(let material): material.tint
        case .linear(let style): style.gradient.gradient.stops.first?.color ?? .clear
        }
    }
}
public nonisolated struct Color: ShapeStyle, Primitive, Hashable, Sendable {
    private let light: UInt32, dark: UInt32
    private let lightOpacity: Double, darkOpacity: Double
    private nonisolated init(rgb: UInt32, dark: UInt32? = nil) {
        self.init(light: 0xff000000 | rgb, dark: 0xff000000 | (dark ?? rgb))
    }
    nonisolated init(light: UInt32, dark: UInt32, lightOpacity: Double? = nil, darkOpacity: Double? = nil) {
        self.light = light
        self.dark = dark
        self.lightOpacity = lightOpacity ?? Double(light >> 24) / 255
        self.darkOpacity = darkOpacity ?? Double(dark >> 24) / 255
    }
    func alpha(_ scheme: ColorScheme) -> Double { scheme == .dark ? darkOpacity : lightOpacity }
    public enum RGBColorSpace: Sendable { case sRGB, sRGBLinear, displayP3 }
    public nonisolated init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func gamma(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        let r, g, b: Double
        switch colorSpace {
        case .sRGB: (r, g, b) = (red, green, blue)
        case .sRGBLinear: (r, g, b) = (gamma(red), gamma(green), gamma(blue))
        case .displayP3:
            let lr = linear(red), lg = linear(green), lb = linear(blue)
            (r, g, b) = (gamma(1.22494 * lr - 0.22494 * lg), gamma(-0.04206 * lr + 1.04206 * lg),
                         gamma(-0.01964 * lr - 0.07864 * lg + 1.09828 * lb))
        }
        func byte(_ n: Double) -> UInt32 { UInt32((min(1, max(0, n)) * 255).rounded()) }
        let rgba = byte(opacity) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
        let alpha = min(1, max(0, opacity))
        self.init(light: rgba, dark: rgba, lightOpacity: alpha, darkOpacity: alpha)
    }
    public nonisolated init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }
    public nonisolated func opacity(_ opacity: Double) -> Color {
        let amount = min(1, max(0, opacity))
        let lightAlpha = lightOpacity * amount, darkAlpha = darkOpacity * amount
        func faded(_ argb: UInt32, _ alpha: Double) -> UInt32 {
            UInt32((alpha * 255).rounded()) << 24 | (argb & 0xffffff)
        }
        return Color(light: faded(light, lightAlpha), dark: faded(dark, darkAlpha),
                     lightOpacity: lightAlpha, darkOpacity: darkAlpha)
    }
    nonisolated func argb(_ scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }
    nonisolated func hex(_ scheme: ColorScheme) -> String { String(format: "#%08x", argb(scheme)) }
    public struct Resolved: ShapeStyle, Hashable, Sendable {
        public var red, green, blue, opacity: Float
        public init(red: Float, green: Float, blue: Float, opacity: Float = 1) {
            self.red = red; self.green = green; self.blue = blue; self.opacity = opacity
        }
        var color: Color { Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(opacity)) }
        public func resolve(in environment: EnvironmentValues) -> Self { self }
    }
    public nonisolated func resolve(in environment: EnvironmentValues) -> Resolved {
        let argb = environment.colorScheme == .dark ? dark : light
        func channel(_ shift: Int) -> Float { Float((argb >> shift) & 255) / 255 }
        return Resolved(red: channel(16), green: channel(8), blue: channel(0), opacity: Float(alpha(environment.colorScheme)))
    }
    public nonisolated static let primary = Color(rgb: 0x202124, dark: 0xf3f4f5), secondary = Color(rgb: 0x646970, dark: 0xaeb3bc)
    public nonisolated static let black = Color(rgb: 0), white = Color(rgb: 0xffffff), gray = Color(rgb: 0x8e8e93)
    public nonisolated static let clear = Color(white: 0, opacity: 0), red = Color(rgb: 0xff3b30), orange = Color(rgb: 0xff9500)
    public nonisolated static let yellow = Color(rgb: 0xffcc00), green = Color(rgb: 0x34c759), mint = Color(rgb: 0x00c7be)
    public nonisolated static let teal = Color(rgb: 0x30b0c7), cyan = Color(rgb: 0x32ade6), blue = Color(rgb: 0x007aff)
    public nonisolated static let indigo = Color(rgb: 0x5856d6), purple = Color(rgb: 0xaf52de), pink = Color(rgb: 0xff2d55)
    public nonisolated static let brown = Color(rgb: 0xa2845e), accentColor = blue
    @MainActor func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSSurface)
        qs_surface(widget, hex(context.environment.colorScheme), 0)
        qs_shape_hits(widget, nil, 0, context.environment.allowsHits && alpha(context.environment.colorScheme) > 0 ? 1 : 0)
        return [Element { $0.replacingUnspecifiedDimensions() } place: { rect, _ in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
        }]
    }
}
extension ShapeStyle where Self == Color {
    public static var primary: Color { Color.primary }
    public static var secondary: Color { Color.secondary }
    public static var white: Color { Color.white }
    public static var black: Color { Color.black }
    public static var gray: Color { Color.gray }
    public static var red: Color { Color.red }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var green: Color { Color.green }
    public static var mint: Color { Color.mint }
    public static var teal: Color { Color.teal }
    public static var cyan: Color { Color.cyan }
    public static var blue: Color { Color.blue }
    public static var indigo: Color { Color.indigo }
    public static var purple: Color { Color.purple }
    public static var pink: Color { Color.pink }
    public static var brown: Color { Color.brown }
    public static var clear: Color { Color.clear }
}
public struct Path: Equatable, Sendable {
    enum Command: Equatable, Sendable {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), cubic(CGPoint, CGPoint, CGPoint)
        case close, rect(CGRect), ellipse(CGRect)
        indirect case transformed(Path, CGAffineTransform)
        indirect case stroked(Path, StrokeStyle)
        indirect case trimmed(Path, CGFloat, CGFloat)
    }
    var commands: [Command] = []
    public init() {}
    public init(_ callback: (inout Path) -> Void) { callback(&self) }
    public init(_ rect: CGRect) { commands = [.rect(rect)] }
    public init(ellipseIn rect: CGRect) { commands = [.ellipse(rect)] }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        guard !rect.isNull, !rect.isInfinite else { self.init(); return }
        let width = max(0, cornerSize.width), height = max(0, cornerSize.height)
        guard width > 0 || height > 0 else { self.init(rect); return }
        let r = rect.standardized
        let scale = min(1, width > 0 ? r.width / width / 2 : 1, height > 0 ? r.height / height / 2 : 1)
        let size = CGSize(width: width * scale, height: height * scale)
        self.init(cornersIn: r, topLeading: size, topTrailing: size, bottomTrailing: size, bottomLeading: size, style: style)
    }
    public func applying(_ transform: CGAffineTransform) -> Path {
        if isEmpty || transform.isIdentity { return self }
        var path = Path(); path.commands = [.transformed(self, transform)]; return path
    }
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        if !path.isEmpty { commands.append(.transformed(path, transform)) }
    }
    public var isEmpty: Bool { commands.isEmpty }
    public var boundingRect: CGRect {
        guard !isEmpty else { return .null }
        let r = withNativePath(qs_path_bounds)
        return r.width < 0 ? .null : CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }
    public var currentPoint: CGPoint? {
        guard !isEmpty else { return nil }
        let p = withNativePath(qs_path_position)
        return p.width.isNaN ? nil : CGPoint(x: p.width, y: p.height)
    }
    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        withNativePath { qs_path_contains($0, p.x, p.y, eoFill ? 1 : 0) != 0 }
    }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { applying(.init(translationX: dx, y: dy)) }
    public mutating func addRects(_ rects: [CGRect]) { for rect in rects { addRect(rect) } }
    public mutating func addLines(_ lines: [CGPoint]) {
        guard let first = lines.first else { return }
        move(to: first)
        for point in lines.dropFirst() { addLine(to: point) }
    }
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) {
        addPath(Path(roundedRect: rect, cornerSize: cornerSize, style: style), transform: transform)
    }
    public mutating func addRect(_ rect: CGRect) { commands.append(.rect(rect)) }
    public mutating func addEllipse(in rect: CGRect) { commands.append(.ellipse(rect)) }
    public mutating func move(to point: CGPoint) { commands.append(.move(point)) }
    public mutating func addLine(to point: CGPoint) { commands.append(.line(point)) }
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { commands.append(.quad(control, p)) }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) { commands.append(.cubic(control1, control2, p)) }
    public mutating func closeSubpath() { commands.append(.close) }
    func withNativePath<R>(_ body: (OpaquePointer) -> R) -> R {
        let w = qs_path_new()!
        defer { qs_path_delete(w) }
        for command in commands {
            switch command {
            case .move(let p): qs_path_step(w, 0, p.x, p.y, 0, 0, 0, 0)
            case .line(let p): qs_path_step(w, 1, p.x, p.y, 0, 0, 0, 0)
            case .quad(let a, let p): qs_path_step(w, 2, a.x, a.y, p.x, p.y, 0, 0)
            case .cubic(let a, let b, let p): qs_path_step(w, 3, a.x, a.y, b.x, b.y, p.x, p.y)
            case .trimmed(let path, let from, let to):
                path.withNativePath { qs_path_trim(w, $0, from, to) }
            case .stroked(let path, let style):
                path.withNativePath { style.appendOutline(of: $0, to: w) }
            case .transformed(let path, let transform):
                path.withNativePath { qs_path_append(w, $0, transform.native) }
            case .close: qs_path_step(w, 4, 0, 0, 0, 0, 0, 0)
            case .rect(let r): qs_path_step(w, 5, r.minX, r.minY, r.width, r.height, 0, 0)
            case .ellipse(let r): qs_path_step(w, 6, r.minX, r.minY, r.width, r.height, 0, 0)
            }
        }
        return body(w)
    }
}
extension CGAffineTransform {
    var native: QSAffine { QSAffine(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}
public struct FillStyle: Equatable, Sendable {
    public var isEOFilled, isAntialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true) { isEOFilled = eoFill; isAntialiased = antialiased }
}
public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    nonisolated func inset(by amount: CGFloat) -> InsetShape
}
public nonisolated protocol Shape: View, Sendable, Animatable {
    nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { get }
    nonisolated func path(in rect: CGRect) -> Path
}
protocol AnimatedShape: Shape {
    @MainActor func renderedPath(in rect: CGRect, context: Context) -> Path
}
extension Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .mirrors }
    @MainActor func displayPath(in rect: CGRect, context: Context) -> Path {
        let path = self.path(in: rect, context: context)
        guard layoutDirectionBehavior == .mirrors(in: context.environment.layoutDirection) else { return path }
        return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
    @MainActor func path(in rect: CGRect, context: Context) -> Path {
        if let shape = self as? any AnimatedShape { return shape.renderedPath(in: rect, context: context) }
        if AnimatableData.self == EmptyAnimatableData.self { return path(in: rect) }
        var shape = self
        shape.animatableData = context.interpolated(animatableData, key: "shape data")
        return shape.path(in: rect)
    }
    public var body: some View { FilledShape(shape: self, style: nil as Color?) }
    public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View {
        FilledShape(shape: self, style: content, fill: style)
    }
}
struct FilledShape<S: Shape, Style: ShapeStyle>: Primitive {
    let shape: S, style: Style?
    var fill = FillStyle()
    func elements(in context: Context) -> [Element] {
        let paint = style?.paint(in: context.environment) ?? context.environment.foregroundPaint
        let widget: UnsafeMutableRawPointer
        let visible: Bool
        switch paint {
        case .color(let color):
            visible = color.alpha(context.environment.colorScheme) > 0
            widget = context.widget(QSSurface)
            qs_surface(widget, color.hex(context.environment.colorScheme), 0)
        case .material(let material):
            visible = true
            widget = context.widget(QSSurface)
            context.host.hasMaterial = true
            qs_surface_material(widget, material.radius, material.tint.argb(context.environment.colorScheme))
        case .linear(let linear):
            visible = linear.gradient.gradient.stops.contains { $0.color.alpha(context.environment.colorScheme) > 0 }
            widget = context.widget(QSCanvas)
        }
        return [Element { p in
            let size = p.replacingUnspecifiedDimensions()
            if shape is Circle { let side = min(size.width, size.height); return CGSize(width: side, height: side) }
            return size
        } place: { rect, _ in
            let bounds = CGRect(origin: .zero, size: rect.size)
            shape.displayPath(in: bounds, context: context).withNativePath { path in
                qs_shape_hits(widget, path, fill.isEOFilled ? 1 : 0, visible && context.environment.allowsHits ? 1 : 0)
                switch paint {
                case .color, .material:
                    qs_surface_path(widget, path, fill.isEOFilled ? 1 : 0, fill.isAntialiased ? 1 : 0)
                case .linear(let gradient):
                    qs_canvas_clear(widget)
                    qs_canvas_path(widget, path, CGAffineTransform.identity.native, 1, -1, fill.isEOFilled ? 1 : 0, fill.isAntialiased ? 1 : 0)
                    gradient.shade(widget, bounds: bounds, environment: context.environment)
                }
            }
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
        }]
    }
}
public struct Rectangle: Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    public nonisolated init() {}
    public nonisolated func path(in rect: CGRect) -> Path { Path(rect) }
}
public struct Ellipse: Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    public nonisolated init() {}
    public nonisolated func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}
public struct Circle: Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    public nonisolated init() {}
    public nonisolated func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
    }
}
public enum RoundedCornerStyle: Sendable { case circular, continuous }
public struct RoundedRectangle: Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    public nonisolated init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = .init(width: cornerRadius, height: cornerRadius); self.style = style
    }
    public nonisolated init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { self.cornerSize = cornerSize; self.style = style }
    public nonisolated var animatableData: CGSize.AnimatableData {
        get { cornerSize.animatableData }
        set { cornerSize.animatableData = newValue }
    }
    public nonisolated func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerSize: cornerSize, style: style) }
}
public struct Capsule: Shape {
    public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    public var style: RoundedCornerStyle
    public nonisolated init(style: RoundedCornerStyle = .continuous) { self.style = style }
    public nonisolated func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: style) }
}
extension Shape where Self == Rectangle {
    public static var rect: Self { Self() }
}
extension Shape where Self == RoundedRectangle {
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> Self { .init(cornerRadius: cornerRadius, style: style) }
    public static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> Self { .init(cornerSize: cornerSize, style: style) }
}
extension Shape where Self == Capsule {
    public static var capsule: Self { .init() }
    public static func capsule(style: RoundedCornerStyle) -> Self { .init(style: style) }
}
extension Shape where Self == Circle {
    public static var circle: Self { .init() }
}
extension Shape where Self == Ellipse {
    public static var ellipse: Self { .init() }
}
public struct Divider: View {
    @Environment(\.stackAxis) private var axis
    public init() {}
    public var body: some View {
        Color.gray.opacity(0.35).frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
    }
}
