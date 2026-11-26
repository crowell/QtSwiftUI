import QtBridge

public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = Self(rawValue: 1)
    public static let sectionFooters = Self(rawValue: 2)
}

private struct LazyRow {
    let id: [Part]
    let render: @MainActor (Context) -> [Element]
    var section: [Part]?
    var pin: PinnedScrollableViews = []
}

@MainActor private protocol LazyRowSource {
    func rows(at path: [Part]) -> [LazyRow]
}
@MainActor private func rows<V: View>(_ view: V, at path: [Part]) -> [LazyRow] {
    if let group = view as? any LazyRowSource { return group.rows(at: path) }
    return [LazyRow(id: path, render: { view.resolve($0) })]
}
extension Group: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] { SwiftUI.rows(content, at: path) }
}
extension TupleView: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] {
        Mirror(reflecting: value).children.enumerated().flatMap { index, child -> [LazyRow] in
            guard let child = child.value as? any View else { return [] }
            return SwiftUI.rows(child, at: path + [.position(index)])
        }
    }
}
extension EmptyView: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] { [] }
}
extension Optional: LazyRowSource where Wrapped: View {
    fileprivate func rows(at path: [Part]) -> [LazyRow] { map { SwiftUI.rows($0, at: path) } ?? [] }
}
extension ForEach: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] {
        data.flatMap { item -> [LazyRow] in
            let id = path + [.id(AnyHashable(item[keyPath: key]))]
            if Content.self is any LazyRowSource.Type { return SwiftUI.rows(content(item), at: id) }
            return [LazyRow(id: id, render: { context in content(item).resolve(context) })]
        }
    }
}

public struct Section<Parent, Content, Footer> {
    let header: Parent
    let content: Content
    let footer: Footer
    public init(@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent, @ContentBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }
    public init(@ContentBuilder content: () -> Content, @ContentBuilder header: () -> Parent) where Footer == EmptyView {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
    public init(@ContentBuilder content: () -> Content, @ContentBuilder footer: () -> Footer) where Parent == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
    public init(@ContentBuilder content: () -> Content) where Parent == EmptyView, Footer == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}
extension Section: View, Primitive, LazyRowSource where Parent: View, Content: View, Footer: View {
    fileprivate func rows(at path: [Part]) -> [LazyRow] {
        var result: [LazyRow] = []
        if !(header is EmptyView) {
            result.append(LazyRow(id: path + [.position(0)], render: { header.resolve($0) }, section: path, pin: .sectionHeaders))
        }
        result += SwiftUI.rows(content, at: path + [.position(1)]).map { row in
            var child = row
            if child.section == nil { child.section = path }
            return child
        }
        if !(footer is EmptyView) {
            result.append(LazyRow(id: path + [.position(2)], render: { footer.resolve($0) }, section: path, pin: .sectionFooters))
        }
        return result
    }
    func elements(in context: Context) -> [Element] {
        header.resolve(context.descending(.position(0))) + content.resolve(context.descending(.position(1))) + footer.resolve(context.descending(.position(2)))
    }
}

private final class RowMeasurements {
    var width: CGFloat?
    var sizes: [[Part]: CGSize] = [:]
}

public nonisolated struct LazyVStack<Content: View>: Primitive {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let pinnedViews: PinnedScrollableViews
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(),
                @ContentBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    @MainActor func elements(in context: Context) -> [Element] {
        let rows = SwiftUI.rows(content, at: [])
        let base = context.descending(.property("rows"))
        let measurements = context.path + [.property("measurements")]
        let cache = context.host.storage[measurements] as? RowMeasurements ?? RowMeasurements()
        context.host.storage[measurements] = cache
        context.host.liveStorage.insert(measurements)
        let ids = Set(rows.map(\.id))
        cache.sizes = cache.sizes.filter { ids.contains($0.key) }
        let gap = spacing ?? 8
        var visible: [Int: Element] = [:]
        func element(_ index: Int) -> Element {
            if let element = visible[index] { return element }
            let row = rows[index]
            let ctx = base.descending(.id(AnyHashable(row.id))).preferenceBranch()
            let element = stacked(row.render(ctx), axis: .vertical, alignment: Alignment(horizontal: alignment, vertical: .center),
                                  spacing: gap, direction: context.environment.layoutDirection)
            visible[index] = element
            return element
        }
        func estimate() -> CGFloat {
            guard !cache.sizes.isEmpty else { return 44 }
            return cache.sizes.values.reduce(0) { $0 + $1.height } / CGFloat(cache.sizes.count)
        }
        func size(_ width: CGFloat?) -> CGSize {
            let known = cache.sizes.values
            let height = known.reduce(0) { $0 + $1.height } + CGFloat(rows.count - known.count) * estimate()
            return CGSize(width: width ?? known.map(\.width).max() ?? 0, height: max(0, height + CGFloat(max(0, rows.count - 1)) * gap))
        }
        return [Element { proposal in
            if context.verticalViewport == nil {
                let offer = ProposedViewSize(width: proposal.width, height: nil)
                for index in rows.indices { cache.sizes[rows[index].id] = element(index).measure(offer) }
            } else if proposal.width == nil, cache.sizes.isEmpty, !rows.isEmpty {
                return CGSize(width: element(0).measure(.unspecified).width, height: size(nil).height)
            }
            return size(proposal.width)
        } place: { bounds, _ in
            let previousSize = size(bounds.width)
            if cache.width != bounds.width {
                cache.width = bounds.width
                cache.sizes.removeAll(keepingCapacity: true)
            }
            let viewport: CGRect
            if let scroll = context.verticalViewport {
                let rect = qs_scroll_viewport(scroll)
                let origin = qs_origin(qs_scroll_content(scroll))
                viewport = CGRect(x: 0, y: origin.height + rect.y - context.windowOffset.y - bounds.minY, width: rect.width, height: rect.height)
            } else { viewport = CGRect(x: 0, y: 0, width: bounds.width, height: .greatestFiniteMagnitude) }
            let offer = ProposedViewSize(width: bounds.width, height: nil)
            let average = estimate()
            var y: CGFloat = 0
            var pinned: [(Int, CGFloat)] = []
            var sectionBounds: [[Part]: ClosedRange<CGFloat>] = [:]
            @MainActor func place(_ index: Int, at offset: CGFloat) {
                let row = element(index)
                let measured = row.measure(offer)
                cache.sizes[rows[index].id] = measured
                let frame = CGRect(x: bounds.minX, y: bounds.minY + offset, width: bounds.width, height: measured.height)
                row.place(Alignment(horizontal: alignment, vertical: .top).rect(measured, in: frame, direction: context.environment.layoutDirection), offer)
            }
            for (index, row) in rows.enumerated() {
                let height = cache.sizes[row.id]?.height ?? average
                if !pinnedViews.intersection(row.pin).isEmpty { pinned.append((index, y)) }
                else if y <= viewport.maxY && y + height >= viewport.minY { place(index, at: y) }
                let end = y + (cache.sizes[row.id]?.height ?? height)
                if let section = row.section {
                    sectionBounds[section] = min(sectionBounds[section]?.lowerBound ?? y, y)...max(y, end)
                }
                y = end + gap
            }
            for (index, origin) in pinned {
                let row = rows[index]
                guard let section = row.section, let span = sectionBounds[section],
                      span.upperBound >= viewport.minY, span.lowerBound <= viewport.maxY else { continue }
                let height = element(index).measure(offer).height
                let position = row.pin == .sectionHeaders ? max(origin, min(viewport.minY, span.upperBound - height))
                    : min(origin, max(span.lowerBound, viewport.maxY - height))
                place(index, at: position)
            }
            // Keep state for scrolled-out identities and release it when the model removes them.
            let offscreen = ids.subtracting(visible.keys.map { rows[$0].id })
            if !offscreen.isEmpty {
                let prefix = base.path
                for path in context.host.storage.keys where path.count > prefix.count && path.starts(with: prefix) {
                    if case .id(let key) = path[prefix.count], let id = key.base as? [Part], offscreen.contains(id) {
                        context.host.liveStorage.insert(path)
                    }
                }
            }
            if size(bounds.width) != previousSize {
                // Resizing the estimated document must keep an active jump to its bottom.
                if let scroll = context.verticalViewport { qs_scroll_refining(scroll) }
                context.host.update()
            }
        }]
    }
}
