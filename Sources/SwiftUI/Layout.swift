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
public struct UnitPoint: Hashable, Sendable {
    public var x, y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = Self(x: 0, y: 0), center = Self(x: 0.5, y: 0.5)
    public static let top = Self(x: 0.5, y: 0), bottom = Self(x: 0.5, y: 1)
    public static let leading = Self(x: 0, y: 0.5), trailing = Self(x: 1, y: 0.5)
    public static let topLeading = zero, topTrailing = Self(x: 1, y: 0)
    public static let bottomLeading = Self(x: 0, y: 1), bottomTrailing = Self(x: 1, y: 1)
}
public struct HorizontalAlignment: Hashable, Sendable {
    let factor: CGFloat
    public static let leading = Self(factor: 0), center = Self(factor: 0.5), trailing = Self(factor: 1)
}
public struct VerticalAlignment: Hashable, Sendable {
    let factor: CGFloat
    public static let top = Self(factor: 0), center = Self(factor: 0.5), bottom = Self(factor: 1)
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
    func rect(_ size: CGSize, in bounds: CGRect, direction: LayoutDirection = .leftToRight) -> CGRect {
        let rect = CGRect(x: bounds.minX + (bounds.width - size.width) * horizontal.factor,
                          y: bounds.minY + (bounds.height - size.height) * vertical.factor, width: size.width, height: size.height)
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
    var values: [ObjectIdentifier: Any] = [:]
    var isSpacer = false
    var priority: Double = 0
    private var measured: [ProposedViewSize: CGSize] = [:]
    init(size: @escaping (ProposedViewSize) -> CGSize, place: @escaping (CGRect, ProposedViewSize) -> Void) {
        self.sizing = size; self.place = place
    }
    func wrapping(size: @escaping (ProposedViewSize) -> CGSize, place: @escaping (CGRect, ProposedViewSize) -> Void) -> Element {
        let wrapper = Element(size: size, place: place)
        wrapper.values = values
        wrapper.isSpacer = isSpacer
        wrapper.priority = priority
        return wrapper
    }
    func measure(_ proposal: ProposedViewSize) -> CGSize {
        if let known = measured[proposal] { return known }
        let size = sizing(proposal)
        measured[proposal] = size
        return size
    }
}

private enum ZIndexKey: LayoutValueKey { static let defaultValue = 0.0 }

extension View {
    public func zIndex(_ value: Double) -> some View { layoutValue(key: ZIndexKey.self, value: value) }
}

@MainActor private struct Placement {
    let child: Element
    let rect: CGRect
    let proposal: ProposedViewSize
    var depth: Double { child.values[ObjectIdentifier(ZIndexKey.self)] as? Double ?? 0 }

    static func draw(_ placements: [Self]) {
        let ordered = placements.contains { $0.depth != 0 } ? placements.sorted { $0.depth < $1.depth } : placements
        for item in ordered { item.child.place(item.rect, item.proposal) }
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
    return Element { p in
        let items = arrange(p)
        var size = CGSize.zero
        size[keyPath: axis.main] = gap + items.reduce(0) { $0 + $1.0[keyPath: axis.main] }
        size[keyPath: axis.cross] = items.map { $0.0[keyPath: axis.cross] }.max() ?? 0
        return size
    } place: { bounds, p in
        var cursor = axis == .horizontal ? bounds.minX : bounds.minY
        var placements: [Placement] = []
        for (child, (size, offer)) in zip(children, arrange(p)) {
            var rect = alignment.rect(size, in: bounds)
            if axis == .horizontal { rect.origin.x = cursor } else { rect.origin.y = cursor }
            placements.append(Placement(child: child, rect: direction.position(rect, in: bounds), proposal: offer))
            cursor += size[keyPath: axis.main] + spacing
        }
        Placement.draw(placements)
    }
}

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
@MainActor public struct LayoutSubview {
    let element: Element
    let placeElement: (CGRect, ProposedViewSize) -> Void
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { element.measure(proposal) }
    public subscript<K: LayoutValueKey>(_ key: K.Type) -> K.Value {
        element.values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
    }
    public var priority: Double { element.priority }
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let size = sizeThatFits(proposal)
        placeElement(CGRect(x: position.x - size.width * anchor.x, y: position.y - size.height * anchor.y,
                             width: size.width, height: size.height), proposal)
    }
}
public struct LayoutSubviews: RandomAccessCollection {
    public typealias Index = Int
    public var layoutDirection: LayoutDirection
    let items: [LayoutSubview]
    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public subscript(position: Int) -> LayoutSubview { items[position] }
}
@MainActor public protocol Layout {
    typealias Subviews = LayoutSubviews
    associatedtype Cache = Void
    func makeCache(subviews: Subviews) -> Cache
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}
extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) {}
}
extension Layout {
    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        LayoutContainer(layout: self, content: content())
    }
}
private struct LayoutContainer<L: Layout, Content: View>: Primitive {
    let layout: L
    let content: Content
    func elements(in context: Context) -> [Element] {
        let children = content.resolve(context)
        var placements = [Placement?](repeating: nil, count: children.count)
        var layoutBounds = CGRect.zero
        let direction = context.environment.layoutDirection
        let subviews = LayoutSubviews(layoutDirection: direction, items: children.enumerated().map { index, child in
            LayoutSubview(element: child) { rect, proposal in
                placements[index] = Placement(child: child, rect: direction.position(rect, in: layoutBounds), proposal: proposal)
            }
        })
        var cache = layout.makeCache(subviews: subviews)
        return [Element { layout.sizeThatFits(proposal: $0, subviews: subviews, cache: &cache) }
                place: { bounds, proposal in
                    for index in placements.indices { placements[index] = nil }
                    layoutBounds = bounds
                    layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
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
        return [Element { p in
            children.map { $0.measure(p) }.reduce(.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        } place: { bounds, p in
            Placement.draw(children.map { Placement(child: $0, rect: alignment.rect($0.measure(p), in: bounds, direction: context.environment.layoutDirection), proposal: p) })
        }]
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
