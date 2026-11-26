import QtBridge

public struct LinearGradient: View, ShapeStyle, Sendable {
    let gradient: AnyGradient
    let startPoint, endPoint: UnitPoint

    public nonisolated init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(AnyGradient(gradient), startPoint: startPoint, endPoint: endPoint)
    }

    nonisolated init(_ gradient: AnyGradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public nonisolated init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public nonisolated init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    public var body: some View { Rectangle().fill(self) }
    public nonisolated func resolve(in environment: EnvironmentValues) -> Self { self }

    func shade(_ widget: UnsafeMutableRawPointer, bounds: CGRect, environment: EnvironmentValues) {
        func point(_ unit: UnitPoint) -> CGPoint {
            let x = environment.layoutDirection == .rightToLeft ? 1 - unit.x : unit.x
            return CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + unit.y * bounds.height)
        }
        gradient.shade(widget, from: point(startPoint), to: point(endPoint), scheme: environment.colorScheme)
    }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: AnyGradient, startPoint: UnitPoint, endPoint: UnitPoint) -> some ShapeStyle {
        LinearGradient(gradient, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}
