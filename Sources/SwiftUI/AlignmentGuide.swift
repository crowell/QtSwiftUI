public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
    static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?)
}

extension AlignmentID {
    public static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?) {
        parentValue = parentValue.map { $0 + (childValue - $0) / CGFloat(n + 1) } ?? childValue
    }
}

public struct AlignmentKey: Hashable, Comparable, Sendable {
    fileprivate enum Standard: UInt { case start, center, end, firstBaseline, lastBaseline }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.vertical == rhs.vertical }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id ? (!lhs.vertical && rhs.vertical) : lhs.id < rhs.id
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(vertical) }

    private let id: UInt
    let vertical: Bool
    let custom: (any AlignmentID.Type)?
    fileprivate init(_ standard: Standard, vertical: Bool) {
        id = standard.rawValue
        self.vertical = vertical
        custom = nil
    }
    fileprivate init(_ type: any AlignmentID.Type, vertical: Bool) {
        id = UInt(bitPattern: ObjectIdentifier(type))
        self.vertical = vertical
        custom = type
    }
    func defaultValue(in d: ViewDimensions) -> CGFloat {
        if let custom { return custom.defaultValue(in: d) }
        let length = vertical ? d.height : d.width
        switch Standard(rawValue: id) {
        case .start: return 0
        case .center: return length / 2
        default: return length
        }
    }
    func combine<S: Sequence>(_ values: S) -> CGFloat? where S.Element == CGFloat? {
        if let custom {
            var result: CGFloat?, count = 0
            for case let value? in values {
                custom._combineExplicit(childValue: value, count, into: &result)
                count += 1
            }
            return result
        }
        if self == VerticalAlignment.firstTextBaseline.key { return values.compactMap { $0 }.min() }
        if self == VerticalAlignment.lastTextBaseline.key { return values.compactMap { $0 }.max() }
        return nil
    }
}

public struct HorizontalAlignment: Hashable, Sendable {
    public let key: AlignmentKey
    public init(_ id: any AlignmentID.Type) { key = .init(id, vertical: false) }
    private init(_ standard: AlignmentKey.Standard) { key = .init(standard, vertical: false) }
    public static let leading = Self(.start), center = Self(.center), trailing = Self(.end)
    public func combineExplicit<S>(_ values: S) -> CGFloat? where S: Sequence, S.Element == CGFloat? { key.combine(values) }
}

public struct VerticalAlignment: Hashable, Sendable {
    public let key: AlignmentKey
    public init(_ id: any AlignmentID.Type) { key = .init(id, vertical: true) }
    private init(_ standard: AlignmentKey.Standard) { key = .init(standard, vertical: true) }
    public static let top = Self(.start), center = Self(.center), bottom = Self(.end)
    public static let firstTextBaseline = Self(.firstBaseline), lastTextBaseline = Self(.lastBaseline)
    var isBaseline: Bool { self == .firstTextBaseline || self == .lastTextBaseline }
    public func combineExplicit<S>(_ values: S) -> CGFloat? where S: Sequence, S.Element == CGFloat? { key.combine(values) }
}

extension View {
    @preconcurrency nonisolated public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        AlignmentWritingView(content: self, key: g.key, compute: computeValue)
    }
    @preconcurrency nonisolated public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        AlignmentWritingView(content: self, key: g.key, compute: computeValue)
    }
}

private nonisolated struct AlignmentWritingView<Content: View>: View {
    let content: Content
    let key: AlignmentKey
    let compute: @Sendable (ViewDimensions) -> CGFloat
    @MainActor var body: some View {
        Transform(content: content) { view, context in
            view.resolve(context).map { child in
                let element = child.wrapping(size: child.measure, place: child.place)
                element.guides[key] = { p, size in compute(child.dimensions(p, size)) }
                return element
            }
        }
    }
}

extension Alignment {
    @MainActor func rect(for child: Element, size: CGSize, proposal: ProposedViewSize, in bounds: CGRect,
                         parent: Element? = nil, parentProposal: ProposedViewSize = .unspecified,
                         direction: LayoutDirection = .leftToRight) -> CGRect {
        let outer = ViewDimensions(size: bounds.size)
        let x = parent?.coordinate(horizontal.key, parentProposal, bounds.size) ?? outer[horizontal]
        let y = parent?.coordinate(vertical.key, parentProposal, bounds.size) ?? outer[vertical]
        let rect = CGRect(x: bounds.minX + x - child.coordinate(horizontal.key, proposal, size),
                          y: bounds.minY + y - child.coordinate(vertical.key, proposal, size), width: size.width, height: size.height)
        return direction.position(rect, in: bounds)
    }
}

extension Element {
    func dimensions(_ p: ProposedViewSize, _ size: CGSize) -> ViewDimensions {
        ViewDimensions(size: size, resolveExplicit: { key in self.explicitValue(key, p, size) })
    }
    func explicitValue(_ key: AlignmentKey, _ p: ProposedViewSize, _ size: CGSize) -> CGFloat? {
        if let value = guides[key]?(p, size) { return value }
        if key == VerticalAlignment.firstTextBaseline.key { return baselines?(p, size)?.first }
        if key == VerticalAlignment.lastTextBaseline.key { return baselines?(p, size)?.last }
        return nil
    }
    func coordinate(_ key: AlignmentKey, _ p: ProposedViewSize, _ size: CGSize) -> CGFloat {
        explicitValue(key, p, size) ?? key.defaultValue(in: dimensions(p, size))
    }
    // A wrapper reports its child’s explicit guide translated to its own logical origin.
    func translateGuides(from child: Element, placement: @escaping (ProposedViewSize, CGSize) -> (CGRect, ProposedViewSize)) {
        guides = [:]
        for (key, value) in child.guides {
            guides[key] = { p, size in
                let (rect, offer) = placement(p, size)
                return value(offer, rect.size).map { $0 + (key.vertical ? rect.minY : rect.minX) }
            }
        }
    }
}
