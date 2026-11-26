public struct ScrollBounceBehavior: Sendable {
    let policy: Int32
    public static var automatic: Self { Self(policy: 0) }
    public static var always: Self { Self(policy: 1) }
    public static var basedOnSize: Self { Self(policy: 2) }
}

extension View {
    nonisolated public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        Transform(content: self) { view, context in
            var inner = context
            if axes.contains(.horizontal) { inner.environment.horizontalScrollBounceBehavior = behavior }
            if axes.contains(.vertical) { inner.environment.verticalScrollBounceBehavior = behavior }
            return view.resolve(inner)
        }
    }
}
