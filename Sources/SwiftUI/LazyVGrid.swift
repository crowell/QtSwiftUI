public struct GridItem: Sendable, Equatable {
    public enum Size: Sendable, Equatable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: Size
    public var spacing: CGFloat?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

public nonisolated struct LazyVGrid<Content: View>: Primitive {
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let pinnedViews: PinnedScrollableViews
    let content: Content

    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = .init(), @ContentBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    @MainActor func elements(in context: Context) -> [Element] {
        lazyVerticalContent(content, columns: columns, alignment: alignment, spacing: spacing,
                            pinnedViews: pinnedViews, in: context)
    }
}

struct GridTracks {
    struct Track {
        var x: CGFloat
        var width: CGFloat
        var alignment: Alignment
    }

    var tracks: [Track] = []
    var usedWidth: CGFloat = 0
    var width: CGFloat = 0

    init(_ columns: [GridItem], proposed: CGFloat?, cellCount: Int, ideal: (Int) -> CGFloat) {
        guard !columns.isEmpty else { return }
        let gaps = columns.dropLast().reduce(0) { $0 + ($1.spacing ?? 8) }
        var available = (proposed ?? 0) - gaps
        var variable = 0
        for column in columns {
            if case .fixed(let fixed) = column.size { available -= max(0, fixed) }
            else { variable += 1 }
        }

        for (index, column) in columns.enumerated() {
            let gap = column.spacing ?? 8
            let allocation: CGFloat
            let count: CGFloat
            let cellWidth: CGFloat
            switch column.size {
            case .fixed(let fixed):
                allocation = max(0, fixed)
                count = 1
                cellWidth = allocation
            case .flexible(let minimum, let maximum):
                let share = proposed == nil ? ideal(index) : available / CGFloat(variable)
                allocation = max(0, min(max(share, minimum), maximum))
                count = 1
                cellWidth = allocation
                variable -= 1
                available -= allocation
            case .adaptive(let minimum, let maximum):
                allocation = max(0, proposed == nil ? ideal(index) : available / CGFloat(variable))
                count = minimum + gap > 0 ? max(1, floor((allocation + gap) / (minimum + gap))) : 1
                cellWidth = max(0, min(maximum, (allocation + gap) / count - gap))
                variable -= 1
                available -= allocation
            }
            // A large proposal may describe more columns than there are views to place.
            let populated = Int(min(CGFloat(max(0, cellCount - tracks.count)), count))
            for offset in 0..<populated {
                tracks.append(Track(x: usedWidth + CGFloat(offset) * (cellWidth + gap),
                                    width: cellWidth, alignment: column.alignment ?? .center))
            }
            usedWidth += count * cellWidth + (count - 1) * gap
            if index < columns.count - 1 { usedWidth += gap }
        }
        width = max(proposed ?? 0, usedWidth)
    }
}
