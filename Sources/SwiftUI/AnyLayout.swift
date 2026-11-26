struct StackConfiguration {
    let axis: Axis
    let alignment: Alignment
    let spacing: CGFloat?
    @MainActor func element(_ subviews: LayoutSubviews) -> Element {
        stacked(subviews.map { $0.stackElement() }, axis: axis, alignment: alignment, spacing: spacing ?? 8)
    }
}

@MainActor protocol StackLayoutSource {
    var stackConfiguration: StackConfiguration? { get }
}

public struct HStackLayout: Layout, StackLayoutSource {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
    private var configuration: StackConfiguration { .init(axis: .horizontal, alignment: .init(horizontal: .leading, vertical: alignment), spacing: spacing) }
    var stackConfiguration: StackConfiguration? { configuration }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        configuration.element(subviews).measure(proposal)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        configuration.element(subviews).place(bounds, proposal)
    }
}

public struct VStackLayout: Layout, StackLayoutSource {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
    private var configuration: StackConfiguration { .init(axis: .vertical, alignment: .init(horizontal: alignment, vertical: .top), spacing: spacing) }
    var stackConfiguration: StackConfiguration? { configuration }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        configuration.element(subviews).measure(proposal)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        configuration.element(subviews).place(bounds, proposal)
    }
}

public struct AnyLayout: Layout, Sendable, StackLayoutSource {
    public struct Cache: Sendable {
        fileprivate var storage: CacheStorage
    }
    @MainActor fileprivate class CacheStorage: Sendable {}
    @MainActor private final class TypedCache<L: Layout>: CacheStorage {
        var value: L.Cache
        init(_ value: L.Cache) { self.value = value }
    }

    private let make: @MainActor @Sendable (Subviews) -> Cache
    private let update: @MainActor @Sendable (inout Cache, Subviews) -> Void
    private let size: @MainActor @Sendable (ProposedViewSize, Subviews, inout Cache) -> CGSize
    private let place: @MainActor @Sendable (CGRect, ProposedViewSize, Subviews, inout Cache) -> Void
    let orientation: Axis?
    let stackConfiguration: StackConfiguration?

    public init<L>(_ layout: L) where L: Layout {
        stackConfiguration = (layout as? any StackLayoutSource)?.stackConfiguration
        orientation = (layout as? AnyLayout)?.orientation ?? L.layoutProperties.stackOrientation
        @MainActor func typed(_ cache: inout Cache, _ subviews: Subviews) -> TypedCache<L> {
            let unique = isKnownUniquelyReferenced(&cache.storage)
            if let stored = cache.storage as? TypedCache<L> {
                if unique { return stored }
                let copy = TypedCache<L>(stored.value)
                cache.storage = copy
                return copy
            }
            let stored = TypedCache<L>(layout.makeCache(subviews: subviews))
            cache.storage = stored
            return stored
        }
        make = { Cache(storage: TypedCache<L>(layout.makeCache(subviews: $0))) }
        update = { cache, children in
            let sameLayout = cache.storage is TypedCache<L>
            let stored = typed(&cache, children)
            if sameLayout { layout.updateCache(&stored.value, subviews: children) }
        }
        size = { p, children, cache in layout.sizeThatFits(proposal: p, subviews: children, cache: &typed(&cache, children).value) }
        place = { bounds, p, children, cache in layout.placeSubviews(in: bounds, proposal: p, subviews: children, cache: &typed(&cache, children).value) }
    }

    public func makeCache(subviews: Subviews) -> Cache { make(subviews) }
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { update(&cache, subviews) }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize { size(proposal, subviews, &cache) }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        place(bounds, proposal, subviews, &cache)
    }
}
