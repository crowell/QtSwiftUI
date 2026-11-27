import QtBridge

public struct Animation: Equatable, Sendable {
    private let curve: UnitCurve
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
    fileprivate var persistent: PersistentSpring?

    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825,
                              blendDuration: TimeInterval = 0) -> Self {
        let spring = PersistentSpring(response: max(0, response), damping: max(0, dampingFraction), blend: max(0, blendDuration))
        return Self(curve: .linear, duration: spring.duration, persistent: spring)
    }
    public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Self {
        .spring(response: duration, dampingFraction: dampingRatio(bounce), blendDuration: blendDuration)
    }
    public static var spring: Self { .spring() }

    @_disfavoredOverload
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86,
                                         blendDuration: TimeInterval = 0.25) -> Self {
        .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
    public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0, blendDuration: TimeInterval = 0.25) -> Self {
        .spring(duration: duration, bounce: 0.15 + extraBounce, blendDuration: blendDuration)
    }
    public static var interactiveSpring: Self { .interactiveSpring() }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Self { .spring(duration: duration, bounce: extraBounce) }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Self { .spring(duration: duration, bounce: 0.15 + extraBounce) }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Self { .spring(duration: duration, bounce: 0.3 + extraBounce) }
    public static var smooth: Self { .smooth() }
    public static var snappy: Self { .snappy() }
    public static var bouncy: Self { .bouncy() }

    private static func dampingRatio(_ bounce: Double) -> Double {
        if bounce <= -1 { return .infinity }
        return bounce < 0 ? 1 / (1 + bounce) : max(0, 1 - bounce)
    }

    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Self {
        let spring = DampedSpring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
        return Self(curve: .linear, duration: spring.duration, oscillator: spring)
    }
    public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0, initialVelocity: Double = 0) -> Self {
        let frequency = 2 * Double.pi / max(0.001, duration)
        let ratio = bounce >= 0 ? max(0, 1 - bounce) : 1 / max(0.001, 1 + bounce)
        return interpolatingSpring(stiffness: frequency * frequency, damping: 2 * ratio * frequency, initialVelocity: initialVelocity)
    }
    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0.0) -> Animation {
        .spring(duration: spring.duration, bounce: spring.bounce, blendDuration: blendDuration)
    }
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation {
        .interpolatingSpring(duration: spring.duration, bounce: spring.bounce, initialVelocity: initialVelocity)
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
        .timingCurve(.bezier(startControlPoint: .init(x: p1x, y: p1y),
                             endControlPoint: .init(x: p2x, y: p2y)), duration: duration)
    }
    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        let diagonal = UnitCurve.bezier(startControlPoint: .zero, endControlPoint: .bottomTrailing)
        return Self(curve: curve == diagonal ? .linear : curve, duration: duration)
    }
    public static var linear: Self { .linear(duration: 0.35) }
    public static var easeIn: Self { .easeIn(duration: 0.35) }
    public static var easeOut: Self { .easeOut(duration: 0.35) }
    public static var easeInOut: Self { .easeInOut(duration: 0.35) }
    public static func linear(duration: TimeInterval) -> Self { .timingCurve(0, 0, 1, 1, duration: duration) }
    public static func easeIn(duration: TimeInterval) -> Self { .timingCurve(0.42, 0, 1, 1, duration: duration) }
    public static func easeOut(duration: TimeInterval) -> Self { .timingCurve(0, 0, 0.58, 1, duration: duration) }
    public static func easeInOut(duration: TimeInterval) -> Self { .timingCurve(0.42, 0, 0.58, 1, duration: duration) }

    fileprivate func elapsed(at time: TimeInterval) -> TimeInterval {
        var elapsed = time
        for delay in delays.reversed() {
            if elapsed < delay { return 0 }
            elapsed -= delay
        }
        return max(0, elapsed)
    }

    func fraction(at time: TimeInterval) -> Double {
        let elapsed = elapsed(at: time)
        guard duration > 0 && elapsed < duration else { return 1 }
        if let persistent { return 1 - persistent.motion(offset: 1.0, velocity: 0, from: nil, at: elapsed).offset }
        if let oscillator { return oscillator.fraction(at: max(0, elapsed)) }
        return curve.value(at: max(0, elapsed / duration))
    }
}

private struct DampedSpring: Equatable, Sendable {
    let spring: Spring
    let initialVelocity: Double

    init(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double) {
        precondition(mass > 0 && stiffness > 0 && damping >= 0)
        spring = Spring(mass: mass, stiffness: stiffness, damping: damping, allowOverDamping: true)
        self.initialVelocity = initialVelocity
    }

    var duration: TimeInterval {
        let squared = spring.frequencySquared, decay = spring.decay
        let rate = decay > sqrt(squared) ? squared / (decay + sqrt(decay * decay - squared)) : decay
        return rate > 0 ? (12 + log1p(abs(initialVelocity) / sqrt(squared))) / rate : .infinity
    }
    func fraction(at time: TimeInterval) -> Double {
        1 + advance(offset: -1.0, velocity: initialVelocity, time: time).offset
    }
    func advance<V: VectorArithmetic>(offset: V, velocity: V, time: TimeInterval) -> (offset: V, velocity: V) {
        guard spring.decay.isFinite else { return (offset, .zero) }
        return spring.advance(offset: offset, velocity: velocity, time: time)
    }
}

private struct PersistentSpring: Equatable, Sendable {
    let response, damping, blend: Double

    private func oscillator(response: Double) -> DampedSpring {
        let frequency = 2 * Double.pi / max(0.000001, response)
        return DampedSpring(mass: 1, stiffness: frequency * frequency, damping: 2 * damping * frequency, initialVelocity: 0)
    }
    var duration: Double { response == 0 ? 0 : oscillator(response: response).duration }

    func response(from previous: Double?, at time: Double) -> Double {
        guard let previous, blend > 0, time < blend else { return response }
        return previous + (response - previous) * time / blend
    }

    func motion<V: VectorArithmetic>(offset: V, velocity: V, from previous: Double?, at time: Double) -> (offset: V, velocity: V) {
        guard response > 0 else { return (.zero, .zero) }
        var state = (offset: offset, velocity: velocity)
        var elapsed = 0.0
        if let previous, blend > 0 {
            // Integrate the changing response in fixed intervals. Outside the blend
            // interval the harmonic oscillator has an exact closed-form solution.
            let end = min(time, blend), step = max(1 / 240.0, blend / 120)
            while elapsed < end {
                let next = min(end, elapsed + step)
                let period = response(from: previous, at: (elapsed + next) / 2)
                state = oscillator(response: period).advance(offset: state.offset, velocity: state.velocity, time: next - elapsed)
                elapsed = next
            }
        }
        return oscillator(response: response).advance(offset: state.offset, velocity: state.velocity, time: time - elapsed)
    }
}

final class AnimatedValue<Value: VectorArithmetic> {
    private struct Movement {
        let delta: Value, start: TimeInterval, animation: Animation
        let initialVelocity: Value
        let previousResponse: Double?

        func motion(at time: TimeInterval) -> (offset: Value, velocity: Value) {
            let age = time - start
            if let spring = animation.persistent {
                return spring.motion(offset: .zero - delta, velocity: initialVelocity,
                                     from: previousResponse, at: animation.elapsed(at: age))
            }
            return (delta.scaled(by: animation.fraction(at: age) - 1), .zero)
        }
        var duration: TimeInterval {
            animation.totalDuration + (previousResponse == nil ? 0 : animation.persistent?.blend ?? 0)
        }
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
        var velocity = Value.zero
        var previousResponse: Double?
        if let spring = animation?.persistent, let last = movements.last, let previous = last.animation.persistent {
            velocity = last.motion(at: time).velocity
            let response = previous.response(from: last.previousResponse, at: last.animation.elapsed(at: time - last.start))
            if spring.blend > 0 && response != spring.response { previousResponse = response }
        }
        if !additive { movements.removeAll() }
        if let animation {
            movements.append(Movement(delta: delta, start: time, animation: animation,
                                      initialVelocity: velocity, previousResponse: previousResponse))
        }
        target = value
    }
    func sample(at time: TimeInterval) -> Value {
        movements.removeAll { time - $0.start >= $0.duration }
        return movements.reduce(target) { $0 + $1.motion(at: time).offset }
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
            if !ctx.host.isMeasuringAlternative { ctx.host.transitions.record(inner.transaction, at: ctx.path) }
            ctx.host.storage[key] = trigger
            ctx.host.liveStorage.insert(key)
            return view.resolve(inner)
        }
    }
}
