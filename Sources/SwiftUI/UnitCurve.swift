import Foundation

public struct UnitCurve: Hashable, Sendable {
    private enum Function: Hashable, Sendable {
        case linear, circularIn, circularOut, circularInOut
        case bezier(UnitPoint, UnitPoint)
    }

    private let function: Function

    public static let linear = Self(function: .linear)
    public static let circularEaseIn = Self(function: .circularIn)
    public static let circularEaseOut = Self(function: .circularOut)
    public static let circularEaseInOut = Self(function: .circularInOut)
    public static let easeIn = bezier(startControlPoint: .init(x: 0.42, y: 0), endControlPoint: .bottomTrailing)
    public static let easeOut = bezier(startControlPoint: .zero, endControlPoint: .init(x: 0.58, y: 1))
    public static let easeInOut = bezier(startControlPoint: .init(x: 0.42, y: 0), endControlPoint: .init(x: 0.58, y: 1))
    @available(*, deprecated, message: "Use easeInOut instead")
    public static let easeInEaseOut = easeInOut

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        Self(function: .bezier(startControlPoint, endControlPoint))
    }

    public var inverse: UnitCurve {
        switch function {
        case .linear, .circularInOut: return self
        case .circularIn: return .circularEaseOut
        case .circularOut: return .circularEaseIn
        case let .bezier(start, end):
            return .bezier(startControlPoint: .init(x: start.y, y: start.x),
                           endControlPoint: .init(x: end.y, y: end.x))
        }
    }

    public func value(at progress: Double) -> Double {
        switch function {
        case .linear: return progress
        case .circularIn: return 1 - Self.circleHeight(at: progress)
        case .circularOut: return Self.circleHeight(at: 1 - progress)
        case .circularInOut:
            return progress < 0.5 ? (1 - Self.circleHeight(at: 2 * progress)) / 2
                                  : (1 + Self.secondHalfHeight(at: progress)) / 2
        case let .bezier(start, end):
            let t = Self.horizontal(start.x, end.x).parameter(at: progress)
            return Self.quantized(Cubic(start.y, end.y).value(t))
        }
    }

    public func velocity(at progress: Double) -> Double {
        switch function {
        case .linear: return 1
        case .circularIn: return Self.circleSlope(at: progress)
        case .circularOut: return abs(1 - progress) / sqrt(progress * (2 - progress))
        case .circularInOut:
            if progress < 0.5 { return Self.circleSlope(at: 2 * progress) }
            return 2 * abs(1 - progress) / Self.secondHalfHeight(at: progress)
        case let .bezier(start, end):
            let x = Self.horizontal(start.x, end.x)
            let t = x.parameter(at: progress)
            let dx = x.slope(t), dy = Cubic(start.y, end.y).slope(t)
            return dx == 0 && dy == 0 ? 1 : Self.quantized(dy / dx)
        }
    }

    private static func circleHeight(at x: Double) -> Double { sqrt(1 - x * x) }
    private static func secondHalfHeight(at progress: Double) -> Double {
        sqrt(4 * progress * (2 - progress) - 3)
    }
    private static func circleSlope(at x: Double) -> Double { abs(x) / circleHeight(at: x) }

    private static let precision = 1.0 / 1_048_576

    private static func quantized(_ value: Double) -> Double {
        // Bézier samples on the desktop SDK use 20 fractional bits.
        (value / precision).rounded() * precision
    }

    private static func horizontal(_ start: Double, _ end: Double) -> Cubic {
        Cubic(min(1, max(0, start)), min(1, max(0, end)))
    }

    private struct Cubic {
        let a, b, c: Double

        init(_ start: Double, _ end: Double) {
            c = 3 * start
            b = 3 * (end - start) - c
            a = 1 - c - b
        }

        func value(_ t: Double) -> Double { ((a * t + b) * t + c) * t }
        func slope(_ t: Double) -> Double { (3 * a * t + 2 * b) * t + c }

        func parameter(at progress: Double) -> Double {
            guard progress > 0 else { return 0 }
            guard progress < 1 else { return 1 }
            // Invert the x coordinate with Newton steps. Near a flat tangent,
            // bisection retains a bounded solution even when Newton overshoots.
            var t = progress
            for _ in 0..<8 {
                let error = value(t) - progress
                if abs(error) < UnitCurve.precision { return t }
                let derivative = slope(t)
                guard abs(derivative) > UnitCurve.precision else { break }
                t -= error / derivative
            }
            var lower = 0.0, upper = 1.0
            t = progress
            for _ in 0..<54 {
                let error = value(t) - progress
                if abs(error) < UnitCurve.precision { break }
                if error < 0 { lower = t } else { upper = t }
                t = (lower + upper) / 2
            }
            return t
        }
    }
}
