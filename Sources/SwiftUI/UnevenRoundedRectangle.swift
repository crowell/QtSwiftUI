public struct RectangleCornerRadii: Equatable, Animatable, Sendable {
    public var topLeading, bottomLeading, bottomTrailing, topTrailing: CGFloat

    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }

    public typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    public var animatableData: AnimatableData {
        get { .init(.init(topLeading, topTrailing), .init(bottomTrailing, bottomLeading)) }
        set {
            (topLeading, topTrailing) = (newValue.first.first, newValue.first.second)
            (bottomTrailing, bottomLeading) = (newValue.second.first, newValue.second.second)
        }
    }

    fileprivate func inset(by amount: CGFloat) -> Self {
        Self(topLeading: max(0, topLeading - amount), bottomLeading: max(0, bottomLeading - amount),
             bottomTrailing: max(0, bottomTrailing - amount), topTrailing: max(0, topTrailing - amount))
    }
}

public nonisolated struct UnevenRoundedRectangle: InsettableShape {
    public var cornerRadii: RectangleCornerRadii
    public var style: RoundedCornerStyle

    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.cornerRadii = cornerRadii
        self.style = style
    }
    public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0,
                bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadii: .init(topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius,
                                     bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius), style: style)
    }

    public var animatableData: RectangleCornerRadii.AnimatableData {
        get { cornerRadii.animatableData }
        set { cornerRadii.animatableData = newValue }
    }
    public func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadii: cornerRadii, style: style) }
    public func inset(by amount: CGFloat) -> some InsettableShape { Inset(base: self, amount: amount) }

    private nonisolated struct Inset: InsettableShape {
        var base: UnevenRoundedRectangle
        var amount: CGFloat
        var animatableData: AnimatablePair<RectangleCornerRadii.AnimatableData, CGFloat> {
            get { .init(base.animatableData, amount) }
            set { base.animatableData = newValue.first; amount = newValue.second }
        }
        func path(in rect: CGRect) -> Path {
            Path(roundedRect: rect.insetBy(dx: amount, dy: amount), cornerRadii: base.cornerRadii.inset(by: amount), style: base.style)
        }
        func inset(by amount: CGFloat) -> Self { Self(base: base, amount: self.amount + amount) }
    }
}

extension Shape where Self == UnevenRoundedRectangle {
    public static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> Self {
        Self(cornerRadii: cornerRadii, style: style)
    }
    public static func rect(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
                            topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) -> Self {
        Self(topLeadingRadius: topLeadingRadius, bottomLeadingRadius: bottomLeadingRadius,
             bottomTrailingRadius: bottomTrailingRadius, topTrailingRadius: topTrailingRadius, style: style)
    }
}

extension Path {
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        guard !rect.isNull, !rect.isInfinite else { self.init(); return }
        let r = rect.standardized
        // Each radius can consume half an edge or whatever its smaller neighbor leaves free.
        let wanted = [cornerRadii.topLeading, cornerRadii.topTrailing, cornerRadii.bottomTrailing, cornerRadii.bottomLeading].map { max(0, $0) }
        func limited(_ index: Int, across: Int, vertical: Int) -> CGFloat {
            min(wanted[index], max(r.width / 2, r.width - wanted[across]), max(r.height / 2, r.height - wanted[vertical]))
        }
        let tl = limited(0, across: 1, vertical: 3), tr = limited(1, across: 0, vertical: 2)
        let br = limited(2, across: 3, vertical: 1), bl = limited(3, across: 2, vertical: 0)
        func size(_ radius: CGFloat) -> CGSize { CGSize(width: radius, height: radius) }
        self.init(cornersIn: r, topLeading: size(tl), topTrailing: size(tr), bottomTrailing: size(br), bottomLeading: size(bl), style: style)
    }

    init(cornersIn r: CGRect, topLeading tl: CGSize, topTrailing tr: CGSize, bottomTrailing br: CGSize, bottomLeading bl: CGSize,
         style: RoundedCornerStyle) {
        self.init()
        let extent: CGFloat = 1.528665
        func reach(_ length: CGFloat, _ radii: CGFloat) -> CGFloat {
            style == .continuous && radii > 0 ? min(extent, length / radii) : 1
        }
        let top = reach(r.width, tl.width + tr.width), bottom = reach(r.width, bl.width + br.width)
        let left = reach(r.height, tl.height + bl.height), right = reach(r.height, tr.height + br.height)
        move(to: CGPoint(x: r.maxX, y: r.midY + (tr.height - br.height) / 2))
        // Construct each clockwise corner in a local basis. u measures distance back
        // along the arriving edge, v measures distance ahead along the departing edge.
        func corner(_ incoming: CGFloat, _ outgoing: CGFloat, _ p: (CGFloat, CGFloat) -> CGPoint) {
            addLine(to: p(incoming, 0))
            if style == .circular {
                let handle: CGFloat = 1 - 4 * (sqrt(2) - 1) / 3
                addCurve(to: p(0, 1), control1: p(handle, 0), control2: p(0, handle))
            } else {
                // Three cubics flatten the tangent near each edge. When adjacent corners
                // touch, shorten the outer handles while preserving the middle arc.
                func outer(_ reach: CGFloat) -> CGFloat { 0.96 + (reach - 1) * 0.24305 }
                func inner(_ reach: CGFloat) -> CGFloat { 0.82 + (reach - 1) * 0.091565 }
                addCurve(to: p(0.631494, 0.0749114), control1: p(outer(incoming), 0), control2: p(inner(incoming), 0))
                addCurve(to: p(0.0749114, 0.631494), control1: p(0.372824, 0.16906), control2: p(0.16906, 0.372824))
                addCurve(to: p(0, outgoing), control1: p(0, inner(outgoing)), control2: p(0, outer(outgoing)))
            }
        }
        corner(right, bottom) { CGPoint(x: r.maxX - $1 * br.width, y: r.maxY - $0 * br.height) }
        corner(bottom, left) { CGPoint(x: r.minX + $0 * bl.width, y: r.maxY - $1 * bl.height) }
        corner(left, top) { CGPoint(x: r.minX + $1 * tl.width, y: r.minY + $0 * tl.height) }
        corner(top, right) { CGPoint(x: r.maxX - $0 * tr.width, y: r.minY + $1 * tr.height) }
        closeSubpath()
    }

    public mutating func addRoundedRect(in rect: CGRect, cornerRadii: RectangleCornerRadii,
                                        style: RoundedCornerStyle = .continuous, transform: CGAffineTransform = .identity) {
        addPath(Path(roundedRect: rect, cornerRadii: cornerRadii, style: style), transform: transform)
    }
}
