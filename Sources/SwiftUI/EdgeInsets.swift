@frozen public struct EdgeInsets: Equatable, Sendable, _VectorMath {
    public var top, leading, bottom, trailing: CGFloat
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }

    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    public var animatableData: AnimatableData {
        get { .init(top, .init(leading, .init(bottom, trailing))) }
        set {
            top = newValue.first
            leading = newValue.second.first
            bottom = newValue.second.second.first
            trailing = newValue.second.second.second
        }
    }

    public func inset(by corners: RectangleCornerInsets, edges: Edge.Set = .all) -> EdgeInsets {
        var result = self
        if edges.contains(.top) { result.top += max(corners.topLeading.height, corners.topTrailing.height) }
        if edges.contains(.leading) { result.leading += max(corners.topLeading.width, corners.bottomLeading.width) }
        if edges.contains(.bottom) { result.bottom += max(corners.bottomLeading.height, corners.bottomTrailing.height) }
        if edges.contains(.trailing) { result.trailing += max(corners.topTrailing.width, corners.bottomTrailing.width) }
        return result
    }
}

@frozen public struct RectangleCornerInsets: Hashable, Sendable {
    public var topLeading, topTrailing, bottomLeading, bottomTrailing: CGSize
    public init() { self.init(topLeading: .zero, topTrailing: .zero, bottomLeading: .zero, bottomTrailing: .zero) }
    public init(topLeading: CGSize, topTrailing: CGSize, bottomLeading: CGSize, bottomTrailing: CGSize) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }
}
