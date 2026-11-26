import QtBridge

public struct Material: ShapeStyle, Sendable {
    let radius: CGFloat
    let tint: Color

    private init(radius: CGFloat, opacity: Double) {
        self.radius = radius
        tint = Color(light: Color(white: 0.98, opacity: opacity).argb(.light),
                     dark: Color(white: 0.12, opacity: opacity).argb(.dark))
    }

    public static let ultraThin = Material(radius: 7, opacity: 0.22)
    public static let thin = Material(radius: 10, opacity: 0.38)
    public static let regular = Material(radius: 14, opacity: 0.55)
    public static let thick = Material(radius: 19, opacity: 0.72)
    public static let ultraThick = Material(radius: 24, opacity: 0.86)
    public static let bar = Material(radius: 16, opacity: 0.67)

    public typealias Resolved = Never
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThin }
    public static var thinMaterial: Material { .thin }
    public static var regularMaterial: Material { .regular }
    public static var thickMaterial: Material { .thick }
    public static var ultraThickMaterial: Material { .ultraThick }
    public static var bar: Material { Material.bar }
}

extension View {
    nonisolated public func compositingGroup() -> some View {
        Transform(content: self) { content, context in
            let group = context.widget(QSGroup)
            qs_compositing_group(group)
            return context.children(of: content, inside: group)
        }
    }

    nonisolated public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        Transform(content: self) { content, context in
            var inner = context
            if case .material(let material) = style.paint(in: context.environment) { inner.environment.backgroundMaterial = material }
            return content.background(shape.fill(style, style: fillStyle)).resolve(inner)
        }
    }
}
