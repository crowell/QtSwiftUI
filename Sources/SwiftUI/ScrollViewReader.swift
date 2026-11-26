import QtBridge

@MainActor final class ScrollAreaTargets {
    struct Target {
        var rect: CGRect
        let path: [Part]
        var estimated: Bool
    }

    let widget: UnsafeMutableRawPointer
    let axes: Axis.Set
    let direction: LayoutDirection
    private var targets: [AnyHashable: Target] = [:]
    private var marked = Set<AnyHashable>()
    private var markedOrder: [AnyHashable] = []
    private var lazyIDs: [(name: @MainActor () -> AnyHashable?, target: Target)] = []

    init(_ widget: UnsafeMutableRawPointer, axes: Axis.Set, direction: LayoutDirection) {
        self.widget = widget
        self.axes = axes
        self.direction = direction
    }

    func record(_ id: AnyHashable, bounds: CGRect, context: Context, path: [Part], estimated: Bool = false) {
        let origin = qs_origin(qs_scroll_content(widget)), parent = context.windowOffset
        let rect = bounds.offsetBy(dx: parent.x - origin.width, dy: parent.y - origin.height)
        if context.isScrollTargetLayout, !estimated, marked.insert(id).inserted { markedOrder.append(id) }
        if var previous = targets[id] {
            guard previous.path == path else { return }
            if previous.estimated != estimated {
                if !estimated { targets[id] = Target(rect: rect, path: path, estimated: false) }
            } else {
                previous.rect = previous.rect.union(rect)
                targets[id] = previous
            }
        } else {
            targets[id] = Target(rect: rect, path: path, estimated: estimated)
        }
    }

    func registerLazyID(_ name: @escaping @MainActor () -> AnyHashable?, bounds: CGRect, context: Context, path: [Part]) {
        let origin = qs_origin(qs_scroll_content(widget)), parent = context.windowOffset
        let rect = bounds.offsetBy(dx: parent.x - origin.width, dy: parent.y - origin.height)
        lazyIDs.append((name, Target(rect: rect, path: path, estimated: true)))
    }

    func snapshot(in viewport: CGRect) -> ScrollVisibilitySnapshot {
        let entries = markedOrder.compactMap { id in targets[id].map { ScrollVisibilitySnapshot.Entry(id: id, rect: $0.rect) } }
        return ScrollVisibilitySnapshot(entries: entries, viewport: viewport)
    }

    func target(for id: AnyHashable) -> Target? {
        if let known = targets[id] { return known }
        // Only build row descriptions when an offscreen explicit ID differs
        // from the ForEach ID. This never mounts its widgets or evaluates its body.
        return lazyIDs.first { $0.name() == id }?.target
    }

    func scroll(to rect: CGRect, anchor: UnitPoint?) {
        let viewport = qs_scroll_viewport(widget)
        func offset(start: CGFloat, size: CGFloat, current: CGFloat, length: CGFloat, fraction: CGFloat?) -> CGFloat {
            if let fraction { return start + fraction * (size - length) }
            let end = start + size, far = current + length
            if start >= current && end <= far || start <= current && end >= far { return current }
            return abs(start - current) < abs(end - far) ? start : end - length
        }
        let x = axes.contains(.horizontal) ? offset(start: rect.minX, size: rect.width, current: viewport.x,
            length: viewport.width, fraction: anchor.map { direction == .leftToRight ? $0.x : 1 - $0.x }) : viewport.x
        let y = axes.contains(.vertical) ? offset(start: rect.minY, size: rect.height, current: viewport.y,
            length: viewport.height, fraction: anchor?.y) : viewport.y
        qs_scroll_set_offset(widget, x, y)
    }
}

@MainActor private final class ScrollReaderTargets {
    var areas: [ScrollAreaTargets] = []
    private var pending: (AnyHashable, UnitPoint?)?

    func scroll(_ id: AnyHashable, anchor: UnitPoint?) {
        pending = nil
        for area in areas {
            if let target = area.target(for: id) {
                area.scroll(to: target.rect, anchor: anchor)
                if target.estimated { pending = (id, anchor) }
                return
            }
        }
    }

    func refine() {
        if let (id, anchor) = pending { scroll(id, anchor: anchor) }
    }
}

public struct ScrollViewProxy {
    fileprivate weak var targets: ScrollReaderTargets?
    public func scrollTo<ID>(_ id: ID, anchor: UnitPoint? = nil) where ID: Hashable {
        // Hash the caller’s ID and read Qt geometry on the UI thread. The caller
        // retains ownership of non-Sendable IDs until the synchronous lookup ends.
        nonisolated(unsafe) let key = AnyHashable(id)
        let scroll: @MainActor @Sendable () -> Void = { [weak targets] in targets?.scroll(key, anchor: anchor) }
        if Thread.isMainThread { MainActor.assumeIsolated(scroll) }
        else { DispatchQueue.main.sync { MainActor.assumeIsolated(scroll) } }
    }
}

public nonisolated struct ScrollViewReader<Content: View>: View {
    public var content: (ScrollViewProxy) -> Content
    public init(@ContentBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }
    public var body: some View { ReaderBody(content: content) }
}

private nonisolated struct ReaderBody<Content: View>: Primitive {
    let content: (ScrollViewProxy) -> Content
    @MainActor func elements(in context: Context) -> [Element] {
        let targets = context.host.storage[context.path] as? ScrollReaderTargets ?? ScrollReaderTargets()
        context.host.storage[context.path] = targets
        context.host.liveStorage.insert(context.path)
        targets.areas.removeAll(keepingCapacity: true)
        var inner = context
        inner.registerScrollArea.append { targets.areas.append($0) }
        let children = content(ScrollViewProxy(targets: targets)).resolve(inner)
        context.host.afterLayout { targets.refine() }
        return children
    }
}

@MainActor protocol ScrollIdentitySource { var explicitScrollID: AnyHashable { get } }

nonisolated struct IdentifiedView<Content: View, ID: Hashable>: Primitive, SubviewSource, ScrollIdentitySource {
    let content: Content
    let id: ID
    @MainActor var explicitScrollID: AnyHashable { AnyHashable(id) }

    @MainActor func elements(in context: Context) -> [Element] {
        let key = AnyHashable(id), inner = context.descending(.id(key))
        return inner.identified(content.resolve(inner), by: key)
    }

    @MainActor func subviews(in context: Context) -> [Subview] {
        let key = AnyHashable(id)
        return content.collectSubviews(in: context.descending(.id(key))).map { child in
            child.applying { view, destination in
                let inner = destination.descending(.id(key))
                return inner.identified(view.resolve(inner), by: key)
            }
        }
    }
}

extension Context {
    func identified(_ children: [Element], by id: AnyHashable) -> [Element] {
        guard let scrollTargets else { return children }
        return children.map { child in
            child.wrapping(size: child.measure) { bounds, proposal in
                scrollTargets.record(id, bounds: bounds, context: self, path: path)
                child.place(bounds, proposal)
            }
        }
    }
}
