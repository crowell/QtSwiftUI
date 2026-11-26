public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}
extension VectorArithmetic {
    public func scaled(by rhs: Double) -> Self {
        var result = self
        result.scale(by: rhs)
        return result
    }
    public mutating func interpolate(towards other: Self, amount: Double) {
        self += (other - self).scaled(by: amount)
    }
    public func interpolated(towards other: Self, amount: Double) -> Self {
        self + (other - self).scaled(by: amount)
    }
}
public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: AnimatableData { get set }
}
extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { get { self } set { self = newValue } }
}
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    public init() {}
    public static var zero: Self { Self() }
    public static func + (lhs: Self, rhs: Self) -> Self { lhs }
    public static func - (lhs: Self, rhs: Self) -> Self { lhs }
    public mutating func scale(by rhs: Double) {}
    public var magnitudeSquared: Double { 0 }
}
extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData { get { .zero } set {} }
}
extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
extension Double: VectorArithmetic, Animatable {
    public typealias AnimatableData = Self
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}
extension CGFloat: VectorArithmetic, Animatable {
    public typealias AnimatableData = Self
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) { self.first = first; self.second = second }
    public init(_ firstType: First.Type, _ secondType: Second.Type) { self.init(.zero, .zero) }
    public static var zero: Self { Self(.zero, .zero) }
    public static func + (lhs: Self, rhs: Self) -> Self { Self(lhs.first + rhs.first, lhs.second + rhs.second) }
    public static func - (lhs: Self, rhs: Self) -> Self { Self(lhs.first - rhs.first, lhs.second - rhs.second) }
    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}
extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}

extension CGPoint: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(x, y) }
        set { (x, y) = (newValue.first, newValue.second) }
    }
}
extension CGSize: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(width, height) }
        set { (width, height) = (newValue.first, newValue.second) }
    }
}
extension CGRect: Animatable {
    public var animatableData: AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData> {
        get { .init(origin.animatableData, size.animatableData) }
        set { (origin.animatableData, size.animatableData) = (newValue.first, newValue.second) }
    }
}
extension UnitPoint: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(x, y) }
        set { (x, y) = (newValue.first, newValue.second) }
    }
}
extension Angle: Animatable {
    public var animatableData: Double { get { radians } set { radians = newValue } }
}
