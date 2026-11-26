public struct ScrollIndicatorVisibility: Equatable, Sendable {
    private enum Policy { case automatic, visible, hidden, never }
    private let policy: Policy
    public static var automatic: Self { Self(policy: .automatic) }
    public static var visible: Self { Self(policy: .visible) }
    public static var hidden: Self { Self(policy: .hidden) }
    public static var never: Self { Self(policy: .never) }
    var qtPolicy: Int32 { policy == .automatic ? 1 : policy == .visible ? 2 : 0 }
    var showsBar: Bool { qtPolicy != 0 }
}

extension View {
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        Transform(content: self) { view, context in
            var inner = context
            if axes.contains(.horizontal) { inner.environment.horizontalScrollIndicatorVisibility = visibility }
            if axes.contains(.vertical) { inner.environment.verticalScrollIndicatorVisibility = visibility }
            return view.resolve(inner)
        }
    }
}
