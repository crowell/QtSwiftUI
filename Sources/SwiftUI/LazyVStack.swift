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
    var scrollID: (@MainActor () -> AnyHashable?)?
    var section: [Part]?
    var pin: PinnedScrollableViews = []
}

@MainActor private protocol LazyRowSource {
    func rows(at path: [Part]) -> [LazyRow]
}
@MainActor private func rows<V: View>(_ view: V, at path: [Part]) -> [LazyRow] {
    if let group = view as? any LazyRowSource { return group.rows(at: path) }
    var row = LazyRow(id: path, render: { view.resolve($0) })
    if let source = view as? any ScrollIdentitySource { row.scrollID = { source.explicitScrollID } }
    return [row]
}
extension Group: LazyRowSource {
    @MainActor fileprivate func rows(at path: [Part]) -> [LazyRow] { SwiftUI.rows(content, at: path) }
}
extension TupleView: LazyRowSource {}
extension TupleContent: LazyRowSource where repeat each Content: View {}
private extension TupleViewChildren {
    func rows(at path: [Part]) -> [LazyRow] {
        var result: [LazyRow] = []
        forEachChild { index, child in
            result += SwiftUI.rows(child, at: path + [.position(index)])
        }
        return result
    }
}
extension EmptyView: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] { [] }
}
extension Optional: LazyRowSource where Wrapped: View {
    fileprivate func rows(at path: [Part]) -> [LazyRow] { map { SwiftUI.rows($0, at: path) } ?? [] }
}
extension _ConditionalContent: LazyRowSource where TrueContent: View, FalseContent: View {
    @MainActor fileprivate func rows(at path: [Part]) -> [LazyRow] {
        switch storage {
        case .first(let view): SwiftUI.rows(view, at: path + [.position(0)])
        case .second(let view): SwiftUI.rows(view, at: path + [.position(1)])
        }
    }
}
extension AnyView: LazyRowSource {
    @MainActor fileprivate func rows(at path: [Part]) -> [LazyRow] { SwiftUI.rows(content, at: path) }
}
extension ForEach: LazyRowSource {
    fileprivate func rows(at path: [Part]) -> [LazyRow] {
        data.flatMap { item -> [LazyRow] in
            let id = path + [.id(AnyHashable(item[keyPath: key]))]
            if Content.self is any LazyRowSource.Type { return SwiftUI.rows(content(item), at: id) }
            var row = LazyRow(id: id, render: { context in content(item).resolve(context) })
            if Content.self is any ScrollIdentitySource.Type {
                row.scrollID = { (content(item) as? any ScrollIdentitySource)?.explicitScrollID }
            }
            return [row]
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
        lazyVerticalContent(content, columns: nil, alignment: alignment, spacing: spacing, pinnedViews: pinnedViews, in: context)
    }
}

@MainActor func lazyVerticalContent(_ content: some View, columns: [GridItem]?, alignment: HorizontalAlignment,
                                    spacing: CGFloat?, pinnedViews: PinnedScrollableViews, in context: Context) -> [Element] {
    let items = rows(content, at: [])
    let base = context.descending(.property("rows"))
    let measurements = context.path + [.property("measurements")]
    let cache = context.host.storage[measurements] as? RowMeasurements ?? RowMeasurements()
    context.host.storage[measurements] = cache
    context.host.liveStorage.insert(measurements)
    let ids = Set(items.map(\.id))
    cache.sizes = cache.sizes.filter { ids.contains($0.key) }
    let gap = spacing ?? 8
    let direction = context.environment.layoutDirection
    let rowAlignment = Alignment(horizontal: alignment, vertical: .top)
    var visible: [Int: Element] = [:]

    func element(_ index: Int) -> Element {
        if let element = visible[index] { return element }
        let item = items[index]
        let ctx = base.descending(.id(AnyHashable(item.id))).preferenceBranch()
        let element = stacked(item.render(ctx), axis: .vertical, alignment: rowAlignment, spacing: gap, direction: direction)
        visible[index] = element
        return element
    }

    func tracks(_ width: CGFloat?) -> GridTracks? {
        columns.map { specs in
            GridTracks(specs, proposed: width, cellCount: items.count) { index in
                guard items.indices.contains(index) else { return 10 }
                return element(index).measure(.unspecified).width
            }
        }
    }

    // Headers and footers occupy a whole row, even when they are not pinned.
    func lines(_ tracks: GridTracks?) -> [Range<Int>] {
        let count = tracks?.tracks.count ?? 1
        guard count > 0 else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        while start < items.count {
            var end = start + 1
            if items[start].pin.isEmpty {
                while end < items.count && end - start < count && items[end].pin.isEmpty && items[end].section == items[start].section {
                    end += 1
                }
            }
            result.append(start..<end)
            start = end
        }
        return result
    }

    func offer(_ index: Int, line: Range<Int>, tracks: GridTracks?, width: CGFloat?) -> ProposedViewSize {
        let trackWidth = items[index].pin.isEmpty ? tracks?.tracks[index - line.lowerBound].width : nil
        return ProposedViewSize(width: trackWidth ?? width, height: nil)
    }

    func averageHeight() -> CGFloat {
        guard !cache.sizes.isEmpty else { return 44 }
        return cache.sizes.values.reduce(0) { $0 + $1.height } / CGFloat(cache.sizes.count)
    }

    func estimatedHeight(_ line: Range<Int>, average: CGFloat) -> CGFloat {
        line.reduce(0) { max($0, cache.sizes[items[$1].id]?.height ?? average) }
    }

    func measuredSize(_ line: Range<Int>, tracks: GridTracks?, width: CGFloat?, record: Bool) -> CGSize {
        var result = CGSize.zero
        for index in line {
            let size = element(index).measure(offer(index, line: line, tracks: tracks, width: width))
            if record { cache.sizes[items[index].id] = size }
            result.width = max(result.width, size.width)
            result.height = max(result.height, size.height)
        }
        return result
    }

    return [Element { proposal in
        if columns != nil && proposal.width?.isFinite == false { return .zero }
        let plan = tracks(proposal.width)
        let rows = lines(plan)
        var height = gap * CGFloat(max(0, rows.count - 1)), idealWidth: CGFloat = 0
        if context.verticalViewport == nil {
            for line in rows {
                let size = measuredSize(line, tracks: plan, width: proposal.width, record: false)
                height += size.height
                idealWidth = max(idealWidth, size.width)
            }
        } else {
            let average = averageHeight()
            for line in rows { height += estimatedHeight(line, average: average) }
            idealWidth = cache.sizes.values.map(\.width).max() ?? 0
            if plan == nil, proposal.width == nil, cache.sizes.isEmpty, !items.isEmpty {
                idealWidth = element(0).measure(.unspecified).width
            }
        }
        return CGSize(width: plan?.width ?? proposal.width ?? idealWidth, height: max(0, height))
    } place: { bounds, _ in
        let plan = tracks(bounds.width)
        let rows = lines(plan)
        let viewport: CGRect
        if let scroll = context.verticalViewport {
            let rect = qs_scroll_viewport(scroll)
            let origin = qs_origin(qs_scroll_content(scroll))
            viewport = CGRect(x: 0, y: origin.height + rect.y - context.windowOffset.y - bounds.minY, width: rect.width, height: rect.height)
        } else { viewport = CGRect(x: 0, y: 0, width: bounds.width, height: .greatestFiniteMagnitude) }

        let oldAverage = averageHeight()
        let previousHeight = rows.reduce(0) { $0 + estimatedHeight($1, average: oldAverage) }
        if cache.width != bounds.width {
            cache.width = bounds.width
            cache.sizes.removeAll(keepingCapacity: true)
        }
        let average = averageHeight()
        var y: CGFloat = 0
        var pinned: [(Range<Int>, CGFloat)] = []
        var sectionBounds: [[Part]: ClosedRange<CGFloat>] = [:]

        @MainActor func recordTarget(_ index: Int, rect: CGRect, estimated: Bool) {
            guard let targets = context.scrollTargets else { return }
            let path = items[index].id
            if estimated, let name = items[index].scrollID {
                targets.registerLazyID(name, bounds: rect, context: context, path: base.path + path)
            }
            for part in path.reversed() {
                if case .id(let id) = part {
                    targets.record(id, bounds: rect, context: context, path: base.path + path, estimated: estimated)
                    return
                }
            }
        }

        @MainActor func place(_ line: Range<Int>, at y: CGFloat, height: CGFloat) {
            let area = CGRect(x: bounds.minX, y: bounds.minY + y, width: bounds.width, height: height)
            // Compute the group's leading-to-trailing coordinates before mirroring the whole row.
            let groupSize = CGSize(width: plan?.usedWidth ?? bounds.width, height: height)
            let leading = rowAlignment.rect(groupSize, in: area).minX
            for index in line {
                let proposal = offer(index, line: line, tracks: plan, width: bounds.width)
                let item = element(index)
                let size = item.measure(proposal)
                var cell = area
                var alignment = rowAlignment
                if let plan, items[index].pin.isEmpty {
                    let track = plan.tracks[index - line.lowerBound]
                    cell.origin.x = leading + track.x
                    cell.size.width = track.width
                    alignment = track.alignment
                }
                let frame = direction.position(alignment.rect(size, in: cell), in: area)
                recordTarget(index, rect: frame, estimated: false)
                item.place(frame, proposal)
            }
        }

        for line in rows {
            let first = items[line.lowerBound]
            var height = estimatedHeight(line, average: average)
            if !pinnedViews.intersection(first.pin).isEmpty { pinned.append((line, y)) }
            else if y <= viewport.maxY && y + height >= viewport.minY {
                height = measuredSize(line, tracks: plan, width: bounds.width, record: true).height
                place(line, at: y, height: height)
            } else if context.scrollTargets != nil {
                let area = CGRect(x: bounds.minX, y: bounds.minY + y, width: bounds.width, height: height)
                for index in line {
                    var cell = area
                    if let plan {
                        let track = plan.tracks[index - line.lowerBound]
                        cell.origin.x += rowAlignment.rect(CGSize(width: plan.usedWidth, height: height), in: area).minX - area.minX + track.x
                        cell.size.width = track.width
                    }
                    recordTarget(index, rect: direction.position(cell, in: area), estimated: true)
                }
            }
            let end = y + height
            if let section = first.section {
                sectionBounds[section] = min(sectionBounds[section]?.lowerBound ?? y, y)...max(y, end)
            }
            y = end + gap
        }
        for (line, origin) in pinned {
            let row = items[line.lowerBound]
            guard let section = row.section, let span = sectionBounds[section],
                  span.upperBound >= viewport.minY, span.lowerBound <= viewport.maxY else { continue }
            let height = measuredSize(line, tracks: plan, width: bounds.width, record: true).height
            let position = row.pin == .sectionHeaders ? max(origin, min(viewport.minY, span.upperBound - height))
                : min(origin, max(span.lowerBound, viewport.maxY - height))
            place(line, at: position, height: height)
        }
        // Cell identity survives scrolling and changes in the number of columns.
        let offscreen = ids.subtracting(visible.keys.map { items[$0].id })
        if !offscreen.isEmpty {
            let prefix = base.path
            for path in context.host.storage.keys where path.count > prefix.count && path.starts(with: prefix) {
                if case .id(let key) = path[prefix.count], let id = key.base as? [Part], offscreen.contains(id) {
                    context.host.liveStorage.insert(path)
                }
            }
        }
        if let scroll = context.verticalViewport {
            let average = averageHeight()
            if rows.reduce(0, { $0 + estimatedHeight($1, average: average) }) != previousHeight {
                qs_scroll_refining(scroll)
                context.host.update()
            }
        }
    }]
}
