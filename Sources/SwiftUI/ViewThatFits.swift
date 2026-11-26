@frozen public nonisolated struct ViewThatFits<Content: View>: Primitive {
    public typealias Body = Never
    @usableFromInline let axes: Axis.Set
    @usableFromInline let content: Content

    public nonisolated init(in axes: Axis.Set = [.horizontal, .vertical], @ContentBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    @MainActor func elements(in context: Context) -> [Element] {
        let children = content.collectSubviews(in: context)
        guard !children.isEmpty else { return [] }
        var sizingContext = context
        sizingContext.preferences.removeAll()
        sizingContext.registerScrollArea.removeAll()
        var measurements: [Int: Element] = [:]
        var selections: [ProposedViewSize: Int] = [:]

        func element(_ index: Int, in destination: Context) -> Element {
            stacked(children[index].elements(in: destination), axis: .vertical, alignment: .center,
                    spacing: 8, direction: destination.environment.layoutDirection)
        }

        func measurement(_ index: Int) -> Element {
            if let existing = measurements[index] { return existing }
            let child = element(index, in: sizingContext)
            measurements[index] = child
            return child
        }

        func selection(_ proposal: ProposedViewSize) -> Int {
            if let existing = selections[proposal] { return existing }
            let horizontal = axes.contains(.horizontal), vertical = axes.contains(.vertical)
            let ideal = ProposedViewSize(width: horizontal ? nil : proposal.width, height: vertical ? nil : proposal.height)
            let index = children.indices.dropLast().first { index in
                let size = measurement(index).measure(ideal)
                return (!horizontal || size.width <= (proposal.width ?? .infinity)) &&
                    (!vertical || size.height <= (proposal.height ?? .infinity))
            } ?? children.endIndex - 1
            selections[proposal] = index
            return index
        }

        let fitting = Element { proposal in
            context.host.measuringAlternative { measurement(selection(proposal)).measure(proposal) }
        } place: { bounds, proposal in
            let index = context.host.measuringAlternative { selection(proposal) }
            let chosen = element(index, in: context)
            chosen.place(bounds, proposal)
        }
        fitting.selectedGuide = { key, proposal, size in
            context.host.measuringAlternative { measurement(selection(proposal)).explicitValue(key, proposal, size) }
        }
        fitting.baselines = { proposal, size in
            context.host.measuringAlternative { measurement(selection(proposal)).baselines?(proposal, size) }
        }
        return [fitting]
    }
}
