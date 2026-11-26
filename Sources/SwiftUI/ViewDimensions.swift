struct TextBaselines {
    var first, last: CGFloat
    func offset(by y: CGFloat) -> Self { .init(first: first + y, last: last + y) }
    static func combining(_ values: [Self]) -> Self? {
        guard let first = values.map(\.first).min(), let last = values.map(\.last).max() else { return nil }
        return .init(first: first, last: last)
    }
}

public struct ViewDimensions {
    let size: CGSize
    var resolveExplicit: ((AlignmentKey) -> CGFloat?)?
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public subscript(guide: HorizontalAlignment) -> CGFloat { self[explicit: guide] ?? guide.key.defaultValue(in: self) }
    public subscript(guide: VerticalAlignment) -> CGFloat { self[explicit: guide] ?? guide.key.defaultValue(in: self) }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { explicitValue(guide.key) }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { explicitValue(guide.key) }
    func explicitValue(_ key: AlignmentKey) -> CGFloat? {
        resolveExplicit?(key)
    }
}
