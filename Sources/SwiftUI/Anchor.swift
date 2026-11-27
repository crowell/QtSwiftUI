private enum AnchorSourceKind: Hashable, Sendable {
    case bounds, rect, point, unitPoint
    case array([Self])
    indirect case optional(Self?)
}

public struct Anchor<Value> {
    fileprivate let global: Value
    fileprivate let kind: AnchorSourceKind
    fileprivate let convert: @Sendable (Value, CGAffineTransform) -> Value

    public struct Source {
        fileprivate let kind: AnchorSourceKind
        let value: @Sendable (CGRect) -> Value
        fileprivate let convert: @Sendable (Value, CGAffineTransform) -> Value
    }
}
extension Anchor: Sendable where Value: Sendable {}
extension Anchor.Source: Sendable where Value: Sendable {}
extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind && lhs.global == rhs.global }
}
extension Anchor: Hashable where Value: Hashable {
    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(global)
    }
}

extension Anchor.Source {
    public init<T>(_ array: [Anchor<T>.Source]) where Value == [T] {
        let sources = array.map(\.value)
        let conversions = array.map(\.convert)
        kind = .array(array.map(\.kind))
        value = { rect in sources.map { $0(rect) } }
        convert = { values, transform in zip(values, conversions).map { $1($0, transform) } }
    }

    public init<T>(_ anchor: Anchor<T>.Source?) where Value == T? {
        let source = anchor?.value
        let conversion = anchor?.convert
        kind = .optional(anchor?.kind)
        value = { rect in source.map { $0(rect) } }
        convert = { value, transform in value.flatMap { wrapped in conversion.map { $0(wrapped, transform) } } }
    }
}

extension Anchor.Source where Value == CGRect {
    public static var bounds: Self { Self(kind: .bounds, value: { $0 }, convert: { $0.applying($1) }) }
    public static func rect(_ r: CGRect) -> Self {
        Self(kind: .rect, value: { r.offsetBy(dx: $0.minX, dy: $0.minY) }, convert: { $0.applying($1) })
    }
}
extension Anchor.Source where Value == CGPoint {
    public static func point(_ p: CGPoint) -> Self {
        Self(kind: .point, value: { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) }, convert: { $0.applying($1) })
    }
    public static func unitPoint(_ p: UnitPoint) -> Self {
        Self(kind: .unitPoint, value: { CGPoint(x: $0.minX + p.x * $0.width, y: $0.minY + p.y * $0.height) }, convert: { $0.applying($1) })
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
        anchor.convert(anchor.global, fromWindow)
    }
}

extension View {
    nonisolated public func anchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                       transform: @escaping (Anchor<A>) -> K.Value) -> some View {
        PlacedAnchor(content: self, source: value) { content, anchor in
            content.deferredPreference(K.self) { transform(anchor()) }
        }
    }

    nonisolated public func transformAnchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                               transform: @escaping (inout K.Value, Anchor<A>) -> Void) -> some View {
        PlacedAnchor(content: self, source: value) { content, anchor in
            content.transformPreference(K.self) { transform(&$0, anchor()) }
        }
    }
}

private nonisolated struct PlacedAnchor<Content: View, A, Output: View>: Primitive, SubviewSource {
    let content: Content
    let source: Anchor<A>.Source
    let output: (AnyView, @escaping () -> Anchor<A>) -> Output

    @MainActor func elements(in context: Context) -> [Element] {
        subviews(in: context).flatMap { $0.resolve(context.preferenceBranch()) }
    }

    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { child in
            child.applying { view, destination in
                var bounds = CGRect.zero
                let writer = output(AnyView(view)) {
                    let local = source.value(CGRect(origin: .zero, size: bounds.size))
                    let global = source.convert(local, destination.transformToWindow(from: bounds.origin))
                    return Anchor(global: global, kind: source.kind, convert: source.convert)
                }
                return writer.resolve(destination).map { element in
                    element.wrapping(size: element.measure) { frame, proposal in
                        bounds = frame
                        element.place(frame, proposal)
                    }
                }
            }
        }
    }
}
