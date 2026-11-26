public nonisolated struct Grid<Content: View>: Primitive {
    private let layout: GridLayout
    private let content: Content

    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
                @ContentBuilder content: () -> Content) {
        layout = GridLayout(alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing)
        self.content = content()
    }

    @MainActor func elements(in context: Context) -> [Element] {
        layout { content }.resolve(context)
    }
}

private final class RowIdentity {
    let alignment: VerticalAlignment?
    init(_ alignment: VerticalAlignment?) { self.alignment = alignment }
}
private enum RowKey: LayoutValueKey { static var defaultValue: RowIdentity? { nil } }
private enum SpanKey: LayoutValueKey { static let defaultValue = 1 }
private enum CellAnchorKey: LayoutValueKey { static var defaultValue: UnitPoint? { nil } }
private enum ColumnAlignmentKey: LayoutValueKey { static var defaultValue: HorizontalAlignment? { nil } }
private enum UnsizedAxesKey: LayoutValueKey { static let defaultValue: Axis.Set = [] }

public nonisolated struct GridRow<Content: View>: Primitive {
    private let alignment: VerticalAlignment?
    private let content: Content

    public init(alignment: VerticalAlignment? = nil, @ContentBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    @MainActor func elements(in context: Context) -> [Element] {
        // Like Group, a row exposes each cell to its enclosing layout.
        content.layoutValue(key: RowKey.self, value: RowIdentity(alignment)).resolve(context)
    }
}

private nonisolated struct GridTrait<Content: View, Key: LayoutValueKey>: View {
    let content: Content
    let key: Key.Type
    let value: Key.Value
    @MainActor var body: some View { content.layoutValue(key: key, value: value) }
}

extension View {
    nonisolated public func gridCellColumns(_ count: Int) -> some View {
        GridTrait(content: self, key: SpanKey.self, value: max(1, count))
    }
    nonisolated public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
        GridTrait(content: self, key: CellAnchorKey.self, value: anchor)
    }
    nonisolated public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        GridTrait(content: self, key: ColumnAlignmentKey.self, value: guide)
    }
    nonisolated public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
        GridTrait(content: self, key: UnsizedAxesKey.self, value: axes)
    }
}

public nonisolated struct GridLayout: Layout {
    public var alignment: Alignment
    public var horizontalSpacing: CGFloat?
    public var verticalSpacing: CGFloat?

    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    fileprivate struct Cell {
        let index: Int
        let row: Int
        var columns: Range<Int>
        let fullWidth: Bool
    }
    fileprivate struct Geometry {
        let columns: [CGFloat]
        let rows: [CGFloat]
        let size: CGSize
    }
    public struct Cache {
        fileprivate var cells: [Cell] = []
        fileprivate var rowAlignments: [VerticalAlignment] = []
        fileprivate var columnAlignments: [Int: HorizontalAlignment] = [:]
        fileprivate var count = 0
        fileprivate var measured: [ProposedViewSize: Geometry] = [:]
    }

    @MainActor public func makeCache(subviews: Subviews) -> Cache {
        var cache = Cache()
        var previous: RowIdentity?
        var column = 0
        for (index, child) in subviews.enumerated() {
            let row = child[RowKey.self]
            if row == nil || row !== previous {
                cache.rowAlignments.append(row?.alignment ?? alignment.vertical)
                column = 0
            }
            let end = column + (row == nil ? 1 : child[SpanKey.self])
            cache.cells.append(.init(index: index, row: cache.rowAlignments.count - 1, columns: column..<end, fullWidth: row == nil))
            if let guide = child[ColumnAlignmentKey.self], end == column + 1 {
                cache.columnAlignments[column] = guide
            }
            cache.count = max(cache.count, end)
            previous = row
            column = end
        }
        for index in cache.cells.indices where cache.cells[index].fullWidth {
            cache.cells[index].columns = 0..<cache.count
        }
        return cache
    }

    @MainActor public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private var hGap: CGFloat { horizontalSpacing ?? 8 }
    private var vGap: CGFloat { verticalSpacing ?? 8 }
    private func gaps(_ count: Int, _ gap: CGFloat) -> CGFloat { CGFloat(max(0, count - 1)) * gap }

    // Fixed cells establish the individual tracks. A spanning cell shares any
    // additional width it needs equally among the columns that it covers.
    private func require(_ amount: CGFloat, across range: Range<Int>, tracks: inout [CGFloat]) {
        let occupied = tracks[range].reduce(gaps(range.count, hGap), +)
        guard amount > occupied else { return }
        let extra = (amount - occupied) / CGFloat(range.count)
        for column in range { tracks[column] += extra }
    }

    private func fit(minimum: [CGFloat], maximum: [CGFloat], offer: CGFloat?, gap: CGFloat) -> [CGFloat] {
        guard let offer, offer.isFinite else { return maximum }
        var sizes = minimum
        var spare = offer - minimum.reduce(gaps(minimum.count, gap), +)
        let order = sizes.indices.sorted { maximum[$0] - minimum[$0] < maximum[$1] - minimum[$1] }
        for (position, track) in order.enumerated() where spare > 0 {
            let extra = min(max(0, maximum[track] - sizes[track]), spare / CGFloat(order.count - position))
            sizes[track] += extra
            spare -= extra
        }
        return sizes
    }

    @MainActor private func geometry(_ p: ProposedViewSize, _ children: Subviews, _ cache: inout Cache) -> Geometry {
        if let known = cache.measured[p] { return known }
        var narrow = Array(repeating: CGFloat.zero, count: cache.count)
        var wide = narrow
        let cells = cache.cells.sorted { $0.columns.count < $1.columns.count }
        for cell in cells {
            let child = children[cell.index]
            let minWidth = child.sizeThatFits(.init(width: 0, height: nil)).width
            require(minWidth, across: cell.columns, tracks: &narrow)
            let width = child[UnsizedAxesKey.self].contains(.horizontal) ? minWidth :
                child.sizeThatFits(.init(width: p.width, height: nil)).width
            require(max(minWidth, width), across: cell.columns, tracks: &wide)
        }
        let columns = fit(minimum: narrow, maximum: wide, offer: p.width, gap: hGap)
        var low = Array(repeating: CGFloat.zero, count: cache.rowAlignments.count)
        var high = low
        for cell in cells {
            let child = children[cell.index], row = cell.row
            let width = columns[cell.columns].reduce(gaps(cell.columns.count, hGap), +)
            let minimum = child.sizeThatFits(.init(width: width, height: 0)).height
            let maximum = child[UnsizedAxesKey.self].contains(.vertical) ? minimum :
                child.sizeThatFits(.init(width: width, height: p.height)).height
            low[row] = max(low[row], minimum)
            high[row] = max(high[row], maximum)
        }
        let rows = fit(minimum: low, maximum: high, offer: p.height, gap: vGap)
        let size = CGSize(width: columns.reduce(gaps(columns.count, hGap), +), height: rows.reduce(gaps(rows.count, vGap), +))
        let result = Geometry(columns: columns, rows: rows, size: size)
        cache.measured[p] = result
        return result
    }

    @MainActor public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        geometry(proposal, subviews, &cache).size
    }

    private struct GuideExtent {
        var before: CGFloat = 0
        var after: CGFloat = 0
        var length: CGFloat { before + after }
        mutating func include(_ guide: CGFloat, length: CGFloat) {
            before = max(before, guide)
            after = max(after, length - guide)
        }
    }

    @MainActor public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let g = geometry(proposal, subviews, &cache)
        func origins(_ sizes: [CGFloat], start: CGFloat, spacing: CGFloat) -> [CGFloat] {
            var cursor = start
            return sizes.map { size in defer { cursor += size + spacing }; return cursor }
        }
        let x = origins(g.columns, start: bounds.minX, spacing: hGap)
        let y = origins(g.rows, start: bounds.minY, spacing: vGap)
        var rowGuides = Array(repeating: GuideExtent(), count: g.rows.count)
        var columnGuides: [Range<Int>: GuideExtent] = [:]
        func horizontalGuide(_ cell: Cell) -> HorizontalAlignment {
            cell.columns.count == 1 ? cache.columnAlignments[cell.columns.lowerBound] ?? alignment.horizontal : alignment.horizontal
        }
        let offers = cache.cells.map { cell in
            ProposedViewSize(width: g.columns[cell.columns].reduce(gaps(cell.columns.count, hGap), +), height: g.rows[cell.row])
        }
        let dimensions = zip(cache.cells, offers).map { cell, offer in
            let d = subviews[cell.index].dimensions(in: offer)
            if subviews[cell.index][CellAnchorKey.self] == nil {
                rowGuides[cell.row].include(d[cache.rowAlignments[cell.row]], length: d.height)
                columnGuides[cell.columns, default: GuideExtent()].include(d[horizontalGuide(cell)], length: d.width)
            }
            return d
        }
        for cell in cache.cells {
            let child = subviews[cell.index], d = dimensions[cell.index], offer = offers[cell.index]
            let column = cell.columns.lowerBound, row = cell.row
            let area = CGSize(width: offer.width!, height: offer.height!)
            var point = CGPoint(x: x[column], y: y[row])
            if let anchor = child[CellAnchorKey.self] {
                point.x += (area.width - d.width) * anchor.x
                point.y += (area.height - d.height) * anchor.y
            } else {
                let h = horizontalGuide(cell), v = cache.rowAlignments[row]
                let columnExtent = columnGuides[cell.columns]!, rowExtent = rowGuides[row]
                let track = ViewDimensions(size: area)
                let natural = ViewDimensions(size: CGSize(width: columnExtent.length, height: rowExtent.length))
                point.x += track[h] - natural[h] + columnExtent.before - d[h]
                point.y += track[v] - natural[v] + rowExtent.before - d[v]
            }
            child.place(at: point, proposal: offer)
        }
    }
}
