public protocol TextSelectability {
    static var allowsSelection: Bool { get }
}

public struct EnabledTextSelectability: TextSelectability {
    public static let allowsSelection = true
}

public struct DisabledTextSelectability: TextSelectability {
    public static let allowsSelection = false
}

extension TextSelectability where Self == EnabledTextSelectability { public static var enabled: Self { Self() } }
extension TextSelectability where Self == DisabledTextSelectability { public static var disabled: Self { Self() } }
extension View {
    nonisolated public func textSelection<S: TextSelectability>(_ selectability: S) -> some View {
        environment(\.selectableText, S.allowsSelection)
    }
    nonisolated public func kerning(_ kerning: CGFloat) -> some View {
        Transform(content: self, readingContext: { $0.with(\.kerning, kerning) }) {
            $0.resolve($1.with(\.kerning, kerning))
        }
    }
    public func tracking(_ tracking: CGFloat) -> some View { environment(\.tracking, tracking) }
    @_disfavoredOverload
    public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        background(style, in: Rectangle())
    }
}
