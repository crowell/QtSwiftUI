import QtBridge

/// Persists across layout passes while the scroll view remains mounted.
@MainActor final class ScrollMotion {
    weak var host: Host?
    private var movement: AnimatedValue<CGPoint.AnimatableData>?
    private var userRevision: UInt64 = 0

    init(host: Host) { self.host = host }

    func move(widget: UnsafeMutableRawPointer, to destination: CGPoint, animation: Animation?) {
        guard let host else { return }
        let viewport = qs_scroll_viewport(widget)
        let maximum = qs_scroll_maximum(widget)
        let start = CGPoint(x: viewport.x, y: viewport.y)
        func bounded(_ value: CGFloat, _ upper: CGFloat, fallback: CGFloat) -> CGFloat {
            value.isFinite ? min(max(value, 0), upper).rounded() : fallback
        }
        let target = CGPoint(x: bounded(destination.x, maximum.width, fallback: start.x),
                             y: bounded(destination.y, maximum.height, fallback: start.y))
        guard let animation, animation.totalDuration > 0 else {
            movement = nil
            qs_scroll_set_offset(widget, target.x, target.y)
            qs_scroll_animating(widget, 0)
            return
        }
        let revision = qs_scroll_user_revision(widget)
        if revision != userRevision { movement = nil }
        userRevision = revision
        guard movement != nil || start != target else { return }
        let track = movement ?? AnimatedValue(start.animatableData)
        track.update(to: target.animatableData, at: host.animationClock(), animation: animation)
        movement = track
        qs_scroll_animating(widget, 1)
        qs_animation_frame(host.window)
    }

    func advance(widget: UnsafeMutableRawPointer) {
        guard let movement, let host else { return }
        if qs_scroll_user_revision(widget) != userRevision {
            self.movement = nil
            qs_scroll_animating(widget, 0)
            return
        }
        let point = movement.sample(at: host.frameTime)
        qs_scroll_set_offset(widget, point.first, point.second)
        if movement.isAnimating {
            qs_animation_frame(host.window)
        } else {
            self.movement = nil
            qs_scroll_animating(widget, 0)
        }
    }
}
