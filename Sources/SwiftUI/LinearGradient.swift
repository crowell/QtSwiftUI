import QtBridge

public struct LinearGradient: View, ShapeStyle, Sendable {
    let gradient: Gradient
    let startPoint, endPoint: UnitPoint

    public nonisolated init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
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

extension Gradient {
    @MainActor func shade(_ widget: UnsafeMutableRawPointer, from start: CGPoint, to end: CGPoint, scheme: ColorScheme) {
        guard stops.count > 1 else {
            qs_canvas_color(widget, (stops.first?.color ?? .clear).hex(scheme))
            return
        }
        qs_canvas_gradient(widget, start.x, start.y, end.x, end.y)
        for stop in stops { qs_canvas_stop(widget, stop.location, stop.color.hex(scheme)) }
    }
}
