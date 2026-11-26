import QtBridge

public struct Animation: Equatable, Sendable {
    private let x1, y1, x2, y2: Double
    let duration: TimeInterval
    private var delays: [TimeInterval] = []
    fileprivate var totalDuration: TimeInterval {
        delays.reduce(duration) { max(0, $0 + $1) }
    }

    public func delay(_ delay: TimeInterval) -> Self {
        var copy = self
        copy.delays.append(delay)
        return copy
    }
    private var oscillator: DampedSpring?

    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Self {
        let spring = DampedSpring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
        return Self(x1: 0, y1: 0, x2: 1, y2: 1, duration: spring.duration, oscillator: spring)
    }
    public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0, initialVelocity: Double = 0) -> Self {
        let frequency = 2 * Double.pi / max(0.001, duration)
        let ratio = bounce >= 0 ? max(0, 1 - bounce) : 1 / max(0.001, 1 + bounce)
        return interpolatingSpring(stiffness: frequency * frequency, damping: 2 * ratio * frequency, initialVelocity: initialVelocity)
    }
    public static var interpolatingSpring: Self { .interpolatingSpring() }
    private var isDefault = false
    public static let `default`: Self = {
        var animation = Self.interpolatingSpring(duration: 0.55)
        animation.isDefault = true
        return animation
    }()
    fileprivate var addsToPreviousSpring: Bool { oscillator != nil }

    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
                                   duration: TimeInterval = 0.35) -> Self {
        Self(x1: p1x, y1: p1y, x2: p2x, y2: p2y, duration: duration)
    }
    public static var linear: Self { .linear(duration: 0.35) }
    public static var easeIn: Self { .easeIn(duration: 0.35) }
    public static var easeOut: Self { .easeOut(duration: 0.35) }
    public static var easeInOut: Self { .easeInOut(duration: 0.35) }
    public static func linear(duration: TimeInterval) -> Self { .timingCurve(0, 0, 1, 1, duration: duration) }
    public static func easeIn(duration: TimeInterval) -> Self { .timingCurve(0.42, 0, 1, 1, duration: duration) }
    public static func easeOut(duration: TimeInterval) -> Self { .timingCurve(0, 0, 0.58, 1, duration: duration) }
    public static func easeInOut(duration: TimeInterval) -> Self { .timingCurve(0.42, 0, 0.58, 1, duration: duration) }

    func fraction(at time: TimeInterval) -> Double {
        var elapsed = time
        for delay in delays.reversed() {
            if elapsed < delay { return 0 }
            elapsed -= delay
        }
        guard duration > 0 && elapsed < duration else { return 1 }
        if let oscillator { return oscillator.fraction(at: max(0, elapsed)) }
        let x = max(0, elapsed / duration)
        if x1 == y1 && x2 == y2 { return x }
        func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let t = (lo + hi) / 2
            if cubic(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return cubic((lo + hi) / 2, y1, y2)
    }
}

private struct DampedSpring: Equatable, Sendable {
    let frequencySquared: Double, decay: Double, initialVelocity: Double

    init(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double) {
        precondition(mass > 0 && stiffness > 0 && damping >= 0)
        frequencySquared = stiffness / mass
        decay = damping / (2 * mass)
        self.initialVelocity = initialVelocity
    }
    var duration: TimeInterval {
        // Conservative envelope cutoff, including the slow mode of an overdamped system.
        let rate = decay > sqrt(frequencySquared) ? frequencySquared / (decay + sqrt(decay * decay - frequencySquared)) : decay
        return rate > 0 ? (12 + log1p(abs(initialVelocity) / sqrt(frequencySquared))) / rate : .infinity
    }
    func fraction(at t: TimeInterval) -> Double {
        let discriminant = frequencySquared - decay * decay
        if abs(discriminant) <= 1e-10 * frequencySquared {
            return 1 - exp(-decay * t) * (1 + (decay - initialVelocity) * t)
        }
        if discriminant > 0 {
            let frequency = sqrt(discriminant)
            return 1 - exp(-decay * t) * (cos(frequency * t) + (decay - initialVelocity) * sin(frequency * t) / frequency)
        }
        let root = sqrt(-discriminant)
        let slow = -frequencySquared / (decay + root), fast = -decay - root
        let weight = (-initialVelocity - fast) / (slow - fast)
        return 1 - weight * exp(slow * t) - (1 - weight) * exp(fast * t)
    }
}

final class AnimatedValue<Value: VectorArithmetic> {
    private struct Movement {
        let delta: Value, start: TimeInterval, animation: Animation
    }
    private(set) var target: Value
    private var movements: [Movement] = []
    init(_ value: Value) { target = value }
    var isAnimating: Bool { !movements.isEmpty }

    func update(to value: Value, at time: TimeInterval, animation: Animation?) {
        guard target != value else { return }
        let displayed = sample(at: time)
        let additive = animation?.addsToPreviousSpring == true && movements.last?.animation.addsToPreviousSpring == true
        let delta = value - (additive ? target : displayed)
        if !additive { movements.removeAll() }
        if let animation { movements.append(Movement(delta: delta, start: time, animation: animation)) }
        target = value
    }
    func sample(at time: TimeInterval) -> Value {
        movements.removeAll { time - $0.start >= $0.animation.totalDuration }
        return movements.reduce(target) { current, movement in
            current + movement.delta.scaled(by: movement.animation.fraction(at: time - movement.start) - 1)
        }
    }
}

private final class AnimationTrigger<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension Context {
    func interpolated<Value: VectorArithmetic>(_ value: Value, key: String) -> Value {
        let id = path + [.property(key)]
        let slot = host.storage[id] as? AnimatedValue<Value> ?? AnimatedValue(value)
        host.storage[id] = slot
        host.liveStorage.insert(id)
        let now = host.frameTime
        slot.update(to: value, at: now, animation: animation)
        let current = slot.sample(at: now)
        if slot.isAnimating { qs_animation_frame(host.window) }
        return current
    }
}
extension View {
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        Transform(content: self) { view, ctx in
            var inner = ctx
            let key = ctx.path + [.property("animation trigger")]
            let trigger = ctx.host.storage[key] as? AnimationTrigger<V> ?? AnimationTrigger(value)
            if trigger.value != value {
                trigger.value = value
                if !inner.transaction.disablesAnimations { inner.animation = animation }
            }
            ctx.host.storage[key] = trigger
            ctx.host.liveStorage.insert(key)
            return view.resolve(inner)
        }
    }
}
