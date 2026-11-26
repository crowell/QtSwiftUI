extension Path {
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle,
                                clockwise: Bool, transform: CGAffineTransform = .identity) {
        let turn = 2 * Double.pi
        var delta = endAngle.radians - startAngle.radians
        if clockwise && delta > 0 {
            delta = delta.truncatingRemainder(dividingBy: turn) - turn
        } else if !clockwise && delta < 0 {
            delta = delta.truncatingRemainder(dividingBy: turn) + turn
        }
        addRelativeArc(center: center, radius: radius, startAngle: startAngle, delta: .radians(delta), transform: transform)
    }

    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle,
                                        transform: CGAffineTransform = .identity) {
        let sweep = delta.radians
        guard startAngle.radians.isFinite, sweep.isFinite, radius.isFinite else { return }
        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var angle = startAngle.radians
        let start = point(angle).applying(transform)
        if let currentPoint {
            if currentPoint != start { addLine(to: start) }
        } else { move(to: start) }

        // Each cubic spans at most a quarter turn. Transform the control
        // points as well as the endpoints so nonuniform transforms give ellipses.
        let count = ceil(abs(sweep) / (.pi / 2))
        guard count > 0, count < Double(Int.max) else { return }
        let step = sweep / count
        let handle = (4 / 3.0) * tan(step / 4) * radius
        for _ in 0..<Int(count) {
            let a = point(angle), next = angle + step, b = point(next)
            let first = CGPoint(x: a.x - handle * sin(angle), y: a.y + handle * cos(angle))
            let last = CGPoint(x: b.x + handle * sin(next), y: b.y - handle * cos(next))
            addCurve(to: b.applying(transform), control1: first.applying(transform), control2: last.applying(transform))
            angle = next
        }
    }

    public mutating func addArc(tangent1End corner: CGPoint, tangent2End end: CGPoint, radius: CGFloat,
                                transform: CGAffineTransform = .identity) {
        let from = (currentPoint ?? .zero).applying(transform.inverted())
        let dx = corner.x - from.x, dy = corner.y - from.y
        let ex = end.x - corner.x, ey = end.y - corner.y
        let first = hypot(dx, dy), second = hypot(ex, ey)
        let turn = atan2(dx * ey - dy * ex, dx * ex + dy * ey)
        guard first > 0, second > 0, radius != 0, abs(sin(turn)) > 1e-12 else {
            if isEmpty { move(to: corner.applying(transform)) } else { addLine(to: corner.applying(transform)) }
            return
        }
        let distance = radius * tan(abs(turn) / 2)
        let entry = CGPoint(x: corner.x - dx / first * distance, y: corner.y - dy / first * distance)
        let signedRadius = turn > 0 ? radius : -radius
        let center = CGPoint(x: entry.x - dy / first * signedRadius, y: entry.y + dx / first * signedRadius)
        let angle = atan2(entry.y - center.y, entry.x - center.x)
        addRelativeArc(center: center, radius: abs(radius), startAngle: .radians(angle),
                       delta: .radians(turn), transform: transform)
    }
}
