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
    let baselines: TextBaselines?
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public subscript(guide: HorizontalAlignment) -> CGFloat { width * guide.factor }
    public subscript(guide: VerticalAlignment) -> CGFloat {
        if guide.isBaseline { return self[explicit: guide] ?? height }
        return height * guide.factor
    }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { nil }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? {
        guard guide.isBaseline else { return nil }
        return guide == .firstTextBaseline ? baselines?.first : baselines?.last
    }
}
