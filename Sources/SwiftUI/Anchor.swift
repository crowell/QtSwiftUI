public struct Anchor<Value> {
    let global: Value
    let translate: @Sendable (Value, CGPoint) -> Value

    public struct Source {
        let value: @Sendable (CGRect) -> Value
        let translate: @Sendable (Value, CGPoint) -> Value
    }
}
extension Anchor: Sendable where Value: Sendable {}
extension Anchor.Source: Sendable where Value: Sendable {}
extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.global == rhs.global }
}
extension Anchor.Source where Value == CGRect {
    public static var bounds: Self { Self(value: { $0 }, translate: { $0.offsetBy(dx: $1.x, dy: $1.y) }) }
    public static func rect(_ r: CGRect) -> Self {
        Self(value: { r.offsetBy(dx: $0.minX, dy: $0.minY) }, translate: bounds.translate)
    }
}
extension Anchor.Source where Value == CGPoint {
    public static func point(_ p: CGPoint) -> Self {
        Self(value: { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) },
             translate: { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) })
    }
    public static func unitPoint(_ p: UnitPoint) -> Self {
        Self(value: { CGPoint(x: $0.minX + p.x * $0.width, y: $0.minY + p.y * $0.height) },
             translate: point(.zero).translate)
    }
    public static var topLeading: Self { .unitPoint(.topLeading) }
    public static var top: Self { .unitPoint(.top) }
    public static var topTrailing: Self { .unitPoint(.topTrailing) }
    public static var leading: Self { .unitPoint(.leading) }
    public static var center: Self { .unitPoint(.center) }
    public static var trailing: Self { .unitPoint(.trailing) }
    public static var bottomLeading: Self { .unitPoint(.bottomLeading) }
    public static var bottom: Self { .unitPoint(.bottom) }
    public static var bottomTrailing: Self { .unitPoint(.bottomTrailing) }
}
extension GeometryProxy {
    public subscript<T>(_ anchor: Anchor<T>) -> T {
        anchor.translate(anchor.global, CGPoint(x: -globalOrigin.x, y: -globalOrigin.y))
    }
}

extension View {
    public func anchorPreference<A, K: PreferenceKey>(key: K.Type = K.self, value: Anchor<A>.Source,
                                                       transform: @escaping (Anchor<A>) -> K.Value) -> some View {
        PlacedAnchor(content: self, source: value) { content, anchor in
            content.deferredPreference(key) { transform(anchor()) }
        }
    }

    public func transformAnchorPreference<A, K: PreferenceKey>(key: K.Type = K.self, value: Anchor<A>.Source,
                                                               transform: @escaping (inout K.Value, Anchor<A>) -> Void) -> some View {
        PlacedAnchor(content: self, source: value) { content, anchor in
            content.transformPreference(key) { transform(&$0, anchor()) }
        }
    }
}

private struct PlacedAnchor<Content: View, A, Output: View>: Primitive {
    let content: Content
    let source: Anchor<A>.Source
    let output: (Content, @escaping () -> Anchor<A>) -> Output
    func elements(in context: Context) -> [Element] {
        var global = CGRect.zero
        let elements = output(content) { Anchor(global: source.value(global), translate: source.translate) }.resolve(context)
        return elements.map { child in
            let placed = child.wrapping(size: child.measure) { bounds, proposal in
                let offset = context.windowOffset
                global = bounds.offsetBy(dx: offset.x, dy: offset.y)
                child.place(bounds, proposal)
            }
            return placed
        }
    }
}
