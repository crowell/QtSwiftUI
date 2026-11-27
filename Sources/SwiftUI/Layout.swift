public struct ProposedViewSize: Equatable, Hashable, Sendable {
    public var width, height: CGFloat?
    public init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
    public init(_ size: CGSize) { self.init(width: size.width, height: size.height) }
    public static let unspecified = Self(width: nil, height: nil)
    public static let zero = Self(.zero)
    public static let infinity = Self(width: .infinity, height: .infinity)
    public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }
}
@frozen public struct UnitPoint: Hashable, Sendable, Codable {
    public var x, y: CGFloat
    public init() { self.init(x: 0, y: 0) }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public init(from decoder: any Decoder) throws {
        var coordinates = try decoder.unkeyedContainer()
        x = try coordinates.decode(CGFloat.self)
        y = try coordinates.decode(CGFloat.self)
    }
    public func encode(to encoder: any Encoder) throws {
        var coordinates = encoder.unkeyedContainer()
        try coordinates.encode(x)
        try coordinates.encode(y)
    }

    public static let zero = Self(x: 0, y: 0), center = Self(x: 0.5, y: 0.5)
    public static let top = Self(x: 0.5, y: 0), bottom = Self(x: 0.5, y: 1)
    public static let leading = Self(x: 0, y: 0.5), trailing = Self(x: 1, y: 0.5)
    public static let topLeading = zero, topTrailing = Self(x: 1, y: 0)
    public static let bottomLeading = Self(x: 0, y: 1), bottomTrailing = Self(x: 1, y: 1)
}
public struct Alignment: Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) { self.horizontal = horizontal; self.vertical = vertical }
    public static let center = Self(horizontal: .center, vertical: .center)
    public static let leading = Self(horizontal: .leading, vertical: .center), trailing = Self(horizontal: .trailing, vertical: .center)
    public static let top = Self(horizontal: .center, vertical: .top), bottom = Self(horizontal: .center, vertical: .bottom)
    public static let topLeading = Self(horizontal: .leading, vertical: .top), topTrailing = Self(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Self(horizontal: .leading, vertical: .bottom), bottomTrailing = Self(horizontal: .trailing, vertical: .bottom)
    public static var centerFirstTextBaseline: Self { .init(horizontal: .center, vertical: .firstTextBaseline) }
    public static var centerLastTextBaseline: Self { .init(horizontal: .center, vertical: .lastTextBaseline) }
    public static var leadingFirstTextBaseline: Self { .init(horizontal: .leading, vertical: .firstTextBaseline) }
    public static var leadingLastTextBaseline: Self { .init(horizontal: .leading, vertical: .lastTextBaseline) }
    public static var trailingFirstTextBaseline: Self { .init(horizontal: .trailing, vertical: .firstTextBaseline) }
    public static var trailingLastTextBaseline: Self { .init(horizontal: .trailing, vertical: .lastTextBaseline) }

    func rect(_ size: CGSize, in bounds: CGRect, direction: LayoutDirection = .leftToRight) -> CGRect {
        rect(ViewDimensions(size: size), in: bounds, alignedTo: ViewDimensions(size: bounds.size), direction: direction)
    }
    func rect(_ child: ViewDimensions, in bounds: CGRect, alignedTo parent: ViewDimensions, direction: LayoutDirection) -> CGRect {
        let rect = CGRect(x: bounds.minX + parent[horizontal] - child[horizontal],
                          y: bounds.minY + parent[vertical] - child[vertical], width: child.width, height: child.height)
        return direction.position(rect, in: bounds)
    }
}
public enum Axis: Int8, CaseIterable, Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Self(rawValue: 1), vertical = Self(rawValue: 2)
    }
    var main: WritableKeyPath<CGSize, CGFloat> { self == .horizontal ? \.width : \.height }
    var cross: WritableKeyPath<CGSize, CGFloat> { self == .horizontal ? \.height : \.width }
    var proposed: WritableKeyPath<ProposedViewSize, CGFloat?> { self == .horizontal ? \.width : \.height }
}

@MainActor final class Element {
    let sizing: (ProposedViewSize) -> CGSize
    let place: (CGRect, ProposedViewSize) -> Void
    var guides: [AlignmentKey: (ProposedViewSize, CGSize) -> CGFloat?] = [:]
    var selectedGuide: ((AlignmentKey, ProposedViewSize, CGSize) -> CGFloat?)?
    var baselines: ((ProposedViewSize, CGSize) -> TextBaselines?)?
    var values: [ObjectIdentifier: Any] = [:]
    var sizesGroupToPositionedContent = false
    var isSpacer = false
    var priority: Double = 0
    var zIndex: Double = 0
    private var measured: [ProposedViewSize: CGSize] = [:]
    init(size: @escaping (ProposedViewSize) -> CGSize, place: @escaping (CGRect, ProposedViewSize) -> Void) {
        self.sizing = size; self.place = place
    }
    func wrapping(size: @escaping (ProposedViewSize) -> CGSize,
                  baselines: ((ProposedViewSize, CGSize) -> TextBaselines?)? = nil, place: @escaping (CGRect, ProposedViewSize) -> Void) -> Element {
        let wrapper = Element(size: size, place: place)
        wrapper.baselines = baselines ?? self.baselines
        wrapper.guides = guides
        wrapper.selectedGuide = selectedGuide
        wrapper.values = values
        wrapper.isSpacer = isSpacer
        wrapper.priority = priority
        wrapper.zIndex = zIndex
        return wrapper
    }
    func measure(_ proposal: ProposedViewSize) -> CGSize {
        if let known = measured[proposal] { return known }
        let size = sizing(proposal)
        measured[proposal] = size
        return size
    }
}

extension View {
    public func zIndex(_ value: Double) -> some View {
        Transform(content: self) { view, context in
            let children = view.resolve(context)
            for child in children { child.zIndex = value }
            return children
        }
    }
}

@MainActor private struct Placement {
    let child: Element
    let rect: CGRect
    let proposal: ProposedViewSize

    static func draw(_ placements: [Self]) {
        let ordered = placements.contains { $0.child.zIndex != 0 } ? placements.sorted { $0.child.zIndex < $1.child.zIndex } : placements
        for item in ordered { item.child.place(item.rect, item.proposal) }
    }
}

private extension Element {
    func combineGuides(from children: [Element], direction: LayoutDirection,
                       placements: @escaping (ProposedViewSize, CGSize) -> [Placement]) {
        func propagates(_ key: AlignmentKey) -> Bool {
            key.custom != nil || key == VerticalAlignment.firstTextBaseline.key || key == VerticalAlignment.lastTextBaseline.key
        }
        func combined(_ key: AlignmentKey, _ proposal: ProposedViewSize, _ size: CGSize) -> CGFloat? {
            guard propagates(key) else { return nil }
            let values = placements(proposal, size).map { item -> CGFloat? in
                let x = direction == .leftToRight ? item.rect.minX : size.width - item.rect.maxX
                let offset = key.vertical ? item.rect.minY : x
                return item.child.explicitValue(key, item.proposal, item.rect.size).map { $0 + offset }
            }
            return key.combine(values)
        }
        for key in Set(children.flatMap { $0.guides.keys }) where propagates(key) {
            guides[key] = { combined(key, $0, $1) }
        }
        if children.contains(where: { $0.selectedGuide != nil }) { selectedGuide = combined }
    }
}

// Reserve children's minimum sizes, then offer the remaining space to the least flexible
// children first. A spacer receives the space that intrinsic-size controls decline.
@MainActor func stacked(_ children: [Element], axis: Axis, alignment: Alignment, spacing: CGFloat,
                        direction: LayoutDirection = .leftToRight) -> Element {
    if children.count == 1 { return children[0] }
    let gap = spacing * CGFloat(max(0, children.count - 1))
    func arrange(_ proposal: ProposedViewSize) -> [(CGSize, ProposedViewSize)] {
        guard let available = proposal[keyPath: axis.proposed], available.isFinite else {
            return children.map { ($0.measure(proposal), proposal) }
        }
        var low = proposal, high = proposal
        low[keyPath: axis.proposed] = 0
        high[keyPath: axis.proposed] = .infinity
        let minimum = children.map { $0.measure(low)[keyPath: axis.main] }
        let flexibility = children.enumerated().map { $0.element.measure(high)[keyPath: axis.main] - minimum[$0.offset] }
        let order = children.indices.sorted { a, b in
            if children[a].priority != children[b].priority { return children[a].priority > children[b].priority }
            if children[a].isSpacer != children[b].isSpacer { return children[b].isSpacer }
            return flexibility[a] < flexibility[b]
        }
        var result = [(CGSize, ProposedViewSize)](repeating: (.zero, proposal), count: children.count)
        var spare = available - minimum.reduce(0, +) - gap
        var remainingContent: [Double: Int] = [:], remainingSpacers: [Double: Int] = [:]
        for child in children {
            if child.isSpacer { remainingSpacers[child.priority, default: 0] += 1 }
            else { remainingContent[child.priority, default: 0] += 1 }
        }
        for i in order {
            let priority = children[i].priority
            var p = proposal
            let count = children[i].isSpacer ? remainingSpacers[priority]! : remainingContent[priority]!
            p[keyPath: axis.proposed] = max(0, minimum[i] + max(0, spare) / CGFloat(count))
            let size = children[i].measure(p)
            spare -= size[keyPath: axis.main] - minimum[i]
            if children[i].isSpacer { remainingSpacers[priority]! -= 1 }
            else { remainingContent[priority]! -= 1 }
            result[i] = (size, p)
        }
        return result
    }
    typealias Item = (CGSize, ProposedViewSize)
    let crossGuide = axis == .horizontal ? alignment.vertical.key : alignment.horizontal.key
    let fixedGuides = crossGuide.custom != nil || (axis == .horizontal && alignment.vertical.isBaseline)
        || children.contains { $0.guides[crossGuide] != nil }
    let variableGuides = children.indices.filter { children[$0].selectedGuide != nil }
    func alignsGuides(_ items: [Item]) -> Bool {
        fixedGuides || variableGuides.contains { i in children[i].selectedGuide?(crossGuide, items[i].1, items[i].0) != nil }
    }
    func offsets(_ items: [Item]) -> [CGFloat] {
        zip(children, items).map { child, item in
            child.coordinate(crossGuide, item.1, item.0)
        }
    }
    func placements(in bounds: CGRect, items: [Item]) -> [Placement] {
        var cursor = axis == .horizontal ? bounds.minX : bounds.minY
        let aligned = alignsGuides(items)
        let guides = aligned ? offsets(items) : []
        let shared = guides.max() ?? 0
        return children.indices.map { i in
            let (size, offer) = items[i]
            var rect = alignment.rect(size, in: bounds)
            if axis == .horizontal {
                rect.origin.x = cursor
                if aligned { rect.origin.y = bounds.minY + shared - guides[i] }
            } else {
                rect.origin.y = cursor
                if aligned { rect.origin.x = bounds.minX + shared - guides[i] }
            }
            cursor += size[keyPath: axis.main] + spacing
            return Placement(child: children[i], rect: direction.position(rect, in: bounds), proposal: offer)
        }
    }
    let stack = Element { p in
        let items = arrange(p)
        var size = CGSize.zero
        size[keyPath: axis.main] = gap + items.reduce(0) { $0 + $1.0[keyPath: axis.main] }
        size[keyPath: axis.cross] = items.map { $0.0[keyPath: axis.cross] }.max() ?? 0
        if alignsGuides(items) {
            let guides = offsets(items)
            let after = zip(items, guides).map { $0.0.0[keyPath: axis.cross] - $0.1 }.max() ?? 0
            size[keyPath: axis.cross] = (guides.max() ?? 0) + after
        }
        return size
    } place: { bounds, p in Placement.draw(placements(in: bounds, items: arrange(p))) }
    stack.baselines = { proposal, size in
        TextBaselines.combining(placements(in: CGRect(origin: .zero, size: size), items: arrange(proposal))
            .compactMap { $0.child.baselines?($0.proposal, $0.rect.size)?.offset(by: $0.rect.minY) })
    }
    stack.combineGuides(from: children, direction: direction) { p, size in
        placements(in: .init(origin: .zero, size: size), items: arrange(p))
    }
    return stack
}

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
public struct LayoutSubview: Equatable {
    fileprivate struct Entry: Sendable {
        let element: Element
        let place: @MainActor (CGRect, ProposedViewSize) -> Void
    }

    fileprivate let source: LayoutSubviews.Source
    fileprivate let index: Int
    fileprivate let direction: LayoutDirection
    private var entry: Entry { source.entries[index] }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source === rhs.source && lhs.index == rhs.index && lhs.direction == rhs.direction
    }
    @MainActor public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = entry.element.measure(proposal)
        return entry.element.dimensions(proposal, size)
    }
    @MainActor public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { entry.element.measure(proposal) }
    @MainActor public subscript<K: LayoutValueKey>(_ key: K.Type) -> K.Value {
        entry.element.values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
    }
    @MainActor public var priority: Double { entry.element.priority }
    @MainActor func stackElement() -> Element {
        entry.element.wrapping(size: entry.element.measure) { rect, offer in
            self.place(at: rect.origin, proposal: offer)
        }
    }
    @MainActor public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let size = sizeThatFits(proposal)
        entry.place(CGRect(x: position.x - size.width * anchor.x, y: position.y - size.height * anchor.y,
                             width: size.width, height: size.height), proposal)
    }
}
public struct LayoutSubviews: Equatable, RandomAccessCollection, Sendable {
    public typealias Index = Int
    public typealias SubSequence = LayoutSubviews
    fileprivate final class Source: Sendable {
        let entries: [LayoutSubview.Entry]
        init(_ entries: [LayoutSubview.Entry]) { self.entries = entries }
    }

    public var layoutDirection: LayoutDirection
    fileprivate let source: Source
    fileprivate var selection: [Int]?
    public var startIndex: Int { 0 }
    public var endIndex: Int { selection?.count ?? source.entries.count }

    private func sourceIndex(_ index: Int) -> Int { selection?[index] ?? index }

    public subscript(index: Int) -> LayoutSubview {
        LayoutSubview(source: source, index: sourceIndex(index), direction: layoutDirection)
    }
    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        precondition(bounds.lowerBound >= 0 && bounds.upperBound <= endIndex)
        return selecting(bounds)
    }
    public subscript<S>(_ indices: S) -> LayoutSubviews where S: Sequence, S.Element == Int {
        selecting(indices)
    }
    private func selecting<S>(_ indices: S) -> LayoutSubviews where S: Sequence, S.Element == Int {
        let selection = indices.map { index in
            precondition(index >= 0 && index < endIndex)
            return sourceIndex(index)
        }
        return LayoutSubviews(layoutDirection: layoutDirection, source: source, selection: selection)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source === rhs.source && lhs.layoutDirection == rhs.layoutDirection && lhs.selection == rhs.selection
    }
}
public struct LayoutProperties: Sendable {
    public var stackOrientation: Axis?
    public init() {}
}

@MainActor public protocol Layout {
    static var layoutProperties: LayoutProperties { get }
    typealias Subviews = LayoutSubviews
    associatedtype Cache = Void
    func makeCache(subviews: Subviews) -> Cache
    func updateCache(_ cache: inout Cache, subviews: Subviews)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}
extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) {}
}
extension Layout {
    public static var layoutProperties: LayoutProperties { .init() }
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }
    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        LayoutContainer(layout: self, content: content())
    }
}
@MainActor private final class MountedLayoutCache<L: Layout> {
    var value: L.Cache
    init(_ value: L.Cache) { self.value = value }
}

private struct LayoutContainer<L: Layout, Content: View>: Primitive {
    let layout: L
    let content: Content
    func elements(in context: Context) -> [Element] {
        let stack = (layout as? any StackLayoutSource)?.stackConfiguration
        let axis = stack?.axis ?? (layout as? AnyLayout)?.orientation ?? L.layoutProperties.stackOrientation
        let children = content.resolve(axis.map { context.with(\.stackAxis, $0) } ?? context)
        if let stack {
            return [stacked(children, axis: stack.axis, alignment: stack.alignment, spacing: stack.spacing ?? 8,
                            direction: context.environment.layoutDirection)]
        }
        var placements = [Placement?](repeating: nil, count: children.count)
        var layoutBounds = CGRect.zero
        let direction = context.environment.layoutDirection
        let entries = children.enumerated().map { index, child in
            LayoutSubview.Entry(element: child) { rect, proposal in
                placements[index] = Placement(child: child, rect: direction.position(rect, in: layoutBounds), proposal: proposal)
            }
        }
        let subviews = LayoutSubviews(layoutDirection: direction, source: .init(entries))
        let cache: MountedLayoutCache<L>
        context.host.liveStorage.insert(context.path)
        if let existing = context.host.storage[context.path] as? MountedLayoutCache<L> {
            cache = existing
            layout.updateCache(&cache.value, subviews: subviews)
        } else {
            cache = MountedLayoutCache(layout.makeCache(subviews: subviews))
            context.host.storage[context.path] = cache
        }
        return [Element { layout.sizeThatFits(proposal: $0, subviews: subviews, cache: &cache.value) }
                place: { bounds, proposal in
                    for index in placements.indices { placements[index] = nil }
                    layoutBounds = bounds
                    layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache.value)
                    for i in subviews.indices where placements[i] == nil {
                        subviews[i].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: proposal)
                    }
                    Placement.draw(placements.compactMap { $0 })
                }]
    }
}
public struct HStack<Content: View>: Primitive {
    let alignment: VerticalAlignment, spacing: CGFloat?, content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    func elements(in context: Context) -> [Element] {
        [stacked(content.resolve(context.with(\.stackAxis, .horizontal)), axis: .horizontal,
                 alignment: .init(horizontal: .leading, vertical: alignment), spacing: spacing ?? 8, direction: context.environment.layoutDirection)]
    }
}
public struct VStack<Content: View>: Primitive {
    let alignment: HorizontalAlignment, spacing: CGFloat?, content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    func elements(in context: Context) -> [Element] {
        [stacked(content.resolve(context.with(\.stackAxis, .vertical)), axis: .vertical,
                 alignment: .init(horizontal: alignment, vertical: .top), spacing: spacing ?? 8, direction: context.environment.layoutDirection)]
    }
}
public struct ZStack<Content: View>: Primitive {
    let alignment: Alignment, content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) { self.alignment = alignment; self.content = content() }
    func elements(in context: Context) -> [Element] {
        let children = content.resolve(context)
        if children.count == 1 { return children }
        func extents(_ p: ProposedViewSize) -> CGRect {
            var extent = CGRect.null
            var unboundedWidth = false, unboundedHeight = false
            for child in children {
                let size = child.measure(p)
                // Alignment on an infinite axis can give an origin of -infinity.
                // Union only finite intervals and preserve unbounded axes for the parent’s sizing probe.
                unboundedWidth = unboundedWidth || size.width.isInfinite
                unboundedHeight = unboundedHeight || size.height.isInfinite
                let x = size.width.isInfinite ? 0 : -child.coordinate(alignment.horizontal.key, p, size)
                let y = size.height.isInfinite ? 0 : -child.coordinate(alignment.vertical.key, p, size)
                extent = extent.union(CGRect(x: x, y: y, width: size.width.isInfinite ? 0 : size.width,
                                             height: size.height.isInfinite ? 0 : size.height))
            }
            if unboundedWidth { extent.size.width = .infinity }
            if unboundedHeight { extent.size.height = .infinity }
            return extent
        }
        func placements(_ bounds: CGRect, _ p: ProposedViewSize) -> [Placement] {
            let extent = extents(p)
            return children.map { child in
                let size = child.measure(p)
                let rect = CGRect(x: bounds.minX - extent.minX - child.coordinate(alignment.horizontal.key, p, size),
                                  y: bounds.minY - extent.minY - child.coordinate(alignment.vertical.key, p, size),
                                  width: size.width, height: size.height)
                return Placement(child: child, rect: context.environment.layoutDirection.position(rect, in: bounds), proposal: p)
            }
        }
        let stack = Element { extents($0).size } place: { Placement.draw(placements($0, $1)) }
        stack.combineGuides(from: children, direction: context.environment.layoutDirection) { p, size in
            placements(.init(origin: .zero, size: size), p)
        }
        stack.baselines = { p, size in
            TextBaselines.combining(placements(.init(origin: .zero, size: size), p)
                .compactMap { $0.child.baselines?(p, $0.rect.size)?.offset(by: $0.rect.minY) })
        }
        return [stack]
    }
}
public struct Spacer: Primitive {
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) { self.minLength = minLength }
    func elements(in context: Context) -> [Element] {
        let axis = context.environment.stackAxis
        let spacer = Element { p in
            var size = CGSize.zero
            size[keyPath: axis.main] = max(minLength ?? 8, p[keyPath: axis.proposed] ?? 0)
            return size
        } place: { _, _ in }
        spacer.isSpacer = true
        return [spacer]
    }
}
