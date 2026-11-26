import QtBridge

public struct Animation: Equatable, Sendable {
    private let x1, y1, x2, y2: Double
    let duration: TimeInterval

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

    func fraction(at elapsed: TimeInterval) -> Double {
        guard duration > 0 && elapsed < duration else { return 1 }
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

private final class AnimatedValue<Value: VectorArithmetic> {
    var from: Value, to: Value
    var start: TimeInterval = 0
    var animation: Animation?
    init(_ value: Value) { from = value; to = value }
    func sample(at time: TimeInterval) -> Value {
        guard let animation else { return to }
        let elapsed = time - start
        if elapsed >= animation.duration { self.animation = nil; return to }
        return from.interpolated(towards: to, amount: animation.fraction(at: elapsed))
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
        if slot.to != value {
            slot.from = slot.sample(at: now)
            slot.to = value
            slot.start = now
            slot.animation = animation
        }
        let current = slot.sample(at: now)
        if slot.animation != nil { qs_animation_frame(host.window) }
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
                inner.animation = animation
            }
            ctx.host.storage[key] = trigger
            ctx.host.liveStorage.insert(key)
            return view.resolve(inner)
        }
    }
}
