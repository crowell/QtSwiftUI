import Foundation

public struct Spring: Hashable, Sendable {
    private let physicalMass: Double
    public var mass: Double { physicalMass }
    let decay: Double
    private let frequency: Double
    private let overdamped: Bool

    public init(mass: Double = 1.0, stiffness: Double, damping: Double, allowOverDamping: Bool = false) {
        let squared = stiffness / mass
        let natural = sqrt(squared)
        let rate = damping / (2 * mass)
        physicalMass = mass
        if !allowOverDamping && rate > natural {
            decay = natural
            frequency = 0
            overdamped = false
        } else {
            decay = rate
            frequency = sqrt(abs(squared - rate * rate))
            overdamped = allowOverDamping && rate > natural
        }
    }

    public init(response: Double, dampingRatio: Double) {
        let natural = 2 * Double.pi / response
        self.init(mass: 1, stiffness: natural * natural, damping: 2 * dampingRatio * natural, allowOverDamping: true)
    }

    public init(duration: TimeInterval = 0.5, bounce: Double = 0.0) {
        self.init(response: duration, dampingRatio: bounce < 0 ? 1 / max(0, 1 + bounce) : max(0, 1 - bounce))
    }

    public init(settlingDuration: TimeInterval, dampingRatio: Double, epsilon: Double = 0.001) {
        // Solve for frequency on a unit time interval, then scale to the requested duration.
        let ratio = min(1, dampingRatio)
        var natural = 5.0
        for _ in 0..<12 {
            let envelope: Double, slope: Double
            if ratio == 1 {
                let exponential = exp(-natural)
                envelope = (1 + natural) * exponential
                slope = -natural * exponential
            } else {
                envelope = ratio / sqrt(1 - ratio * ratio) * exp(-ratio * natural)
                slope = -ratio * envelope
            }
            let step = (envelope - epsilon) / slope
            natural -= step
            if abs(step) < epsilon * max(0.01, settlingDuration) { break }
        }
        natural = abs(natural) / max(0.01, settlingDuration)
        self.init(mass: 1, stiffness: natural * natural, damping: 2 * ratio * natural)
    }

    var frequencySquared: Double {
        decay * decay + (overdamped ? -1 : 1) * frequency * frequency
    }
    public var stiffness: Double { mass * (decay * decay + frequency * frequency) }
    public var damping: Double { 2 * mass * decay }
    public var response: Double { 2 * .pi / sqrt(frequencySquared) }
    public var duration: TimeInterval { response }
    public var dampingRatio: Double { decay / sqrt(frequencySquared) }
    public var bounce: Double { dampingRatio > 1 ? 1 / dampingRatio - 1 : 1 - dampingRatio }

    public static var smooth: Spring { smooth() }
    public static var snappy: Spring { snappy() }
    public static var bouncy: Spring { bouncy() }
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: extraBounce)
    }
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.15 + extraBounce)
    }
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Spring {
        Spring(duration: duration, bounce: 0.3 + extraBounce)
    }

    // Fundamental solutions for initial displacement and initial velocity.
    private func coefficients(at time: Double) -> (displacement: Double, velocity: Double) {
        if frequency == 0 {
            let exponential = exp(-decay * time)
            return ((1 + decay * time) * exponential, time * exponential)
        }
        let cosine: Double, sine: Double
        if overdamped {
            let slow = exp(-frequencySquared / (decay + frequency) * time)
            let fast = exp(-(decay + frequency) * time)
            cosine = (slow + fast) / 2
            sine = (slow - fast) / (2 * frequency)
        } else {
            let exponential = exp(-decay * time)
            cosine = exponential * cos(frequency * time)
            sine = exponential * sin(frequency * time) / frequency
        }
        return (cosine + decay * sine, sine)
    }

    func advance<V: VectorArithmetic>(offset: V, velocity: V, time: TimeInterval) -> (offset: V, velocity: V) {
        guard time > 0 else { return (offset, velocity) }
        let (a, b) = coefficients(at: time)
        return (offset.scaled(by: a) + velocity.scaled(by: b),
                offset.scaled(by: -frequencySquared * b) + velocity.scaled(by: a - 2 * decay * b))
    }

    public func value<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        target + advance(offset: .zero - target, velocity: initialVelocity, time: time).offset
    }

    public func velocity<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: TimeInterval) -> V {
        let result = advance(offset: .zero - target, velocity: initialVelocity, time: time).velocity
        // The desktop SDK includes the target displacement in overdamped velocity samples.
        return overdamped && time > 0 ? target + result : result
    }

    public func update<V: VectorArithmetic>(value: inout V, velocity: inout V, target: V, deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        let delta = target - value
        let motion = advance(offset: .zero - delta, velocity: velocity, time: deltaTime)
        value = target + motion.offset
        velocity = overdamped ? delta + motion.velocity : motion.velocity
    }

    public func force<V: VectorArithmetic>(target: V, position: V, velocity: V) -> V {
        (target - position).scaled(by: stiffness) - velocity.scaled(by: damping)
    }

    public var settlingDuration: TimeInterval { settlingDuration(target: 1.0, epsilon: 0.001) }

    public func settlingDuration<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, epsilon: Double) -> TimeInterval {
        if decay == 0 { return .infinity }
        guard decay > 0, decay.isFinite, frequency.isFinite else { return 0 }
        if frequency > 0 && !overdamped {
            let amplitude = sqrt(target.magnitudeSquared) + sqrt((initialVelocity - target.scaled(by: decay)).magnitudeSquared)
            return max(0, log(amplitude / epsilon) / decay)
        }
        // The SDK estimates the last threshold crossing on a 100 ms grid over 100 seconds.
        let tolerance = epsilon * epsilon
        guard epsilon > 0 else { return 0 }
        let offset = V.zero - target
        let offsetMagnitude = sqrt(offset.magnitudeSquared)
        let speed = sqrt(initialVelocity.magnitudeSquared)
        var time = 0.0, lastOutside: Double? = nil
        for _ in 0...1000 {
            let (a, b) = coefficients(at: time)
            let error = offset.scaled(by: a) + initialVelocity.scaled(by: b)
            if error.magnitudeSquared >= tolerance { lastOutside = time }
            // Both coefficients decrease after the peak of the velocity response.
            let pastPeak = a - 2 * decay * b <= 0
            if pastPeak && abs(a) * offsetMagnitude + abs(b) * speed < epsilon {
                return lastOutside.map { $0 + 0.1 } ?? 0
            }
            time += 0.1
        }
        // Cancellation between the two components can cross the threshold before
        // their upper bound does. Keep the measured crossing at the end of the grid.
        guard let lastOutside, lastOutside + 0.1 < time else { return 0 }
        return lastOutside + 0.1
    }

    public func settlingDuration<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, epsilon: Double) -> TimeInterval {
        settlingDuration(target: toValue.animatableData - fromValue.animatableData,
                         initialVelocity: initialVelocity.animatableData, epsilon: epsilon)
    }

    public func value<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V {
        var result = toValue
        result.animatableData = fromValue.animatableData + value(target: toValue.animatableData - fromValue.animatableData,
                                                                initialVelocity: initialVelocity.animatableData, time: time)
        return result
    }

    public func velocity<V: Animatable>(fromValue: V, toValue: V, initialVelocity: V, time: TimeInterval) -> V {
        var result = toValue
        result.animatableData = velocity(target: toValue.animatableData - fromValue.animatableData,
                                         initialVelocity: initialVelocity.animatableData, time: time)
        return result
    }

    public func force<V: Animatable>(fromValue: V, toValue: V, position: V, velocity: V) -> V {
        var result = toValue
        result.animatableData = force(target: toValue.animatableData - fromValue.animatableData,
                                      position: position.animatableData, velocity: velocity.animatableData)
        return result
    }
}
