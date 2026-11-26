import QtBridge

public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)

    fileprivate func rect(in bounds: CGRect, direction: LayoutDirection) -> CGRect {
        switch self {
        case .rect(let source): return direction.position(source.value(bounds), in: bounds)
        case .point(let point):
            let x = direction == .leftToRight ? point.x : 1 - point.x
            return CGRect(x: bounds.minX + x * bounds.width, y: bounds.minY + point.y * bounds.height, width: 0, height: 0)
        }
    }
}

@MainActor final class PresentationInteraction {
    var dismissalDisabled = false
}

private protocol PopoverSelection {
    associatedtype Item: Identifiable
    @MainActor var item: Item? { get }
    @MainActor func dismiss()
}
private struct BooleanSelection: PopoverSelection {
    struct Token: Identifiable { let id = 0 }
    let binding: Binding<Bool>
    @MainActor var item: Token? { binding.wrappedValue ? Token() : nil }
    @MainActor func dismiss() { binding.wrappedValue = false }
}
private struct ItemSelection<Item: Identifiable>: PopoverSelection {
    let binding: Binding<Item?>
    @MainActor var item: Item? { binding.wrappedValue }
    @MainActor func dismiss() { binding.wrappedValue = nil }
}

private nonisolated struct PopoverView<Source: View, Selection: PopoverSelection, Content: View>: Primitive {
    let source: Source
    let selection: Selection
    let attachment: PopoverAttachmentAnchor
    let edge: Edge?
    let content: (Selection.Item) -> Content

    @MainActor func elements(in context: Context) -> [Element] {
        var children = source.resolve(context)
        guard let item = selection.item, let anchor = children.first else { return children }
        var inner = context.descending(.property("popover"))
        let dismiss: @MainActor () -> Void = { if selection.item?.id == item.id { selection.dismiss() } }
        let popup = inner.widget(QSPopover, action: { _ in dismiss() })
        let interaction = PresentationInteraction()
        inner.presentation = interaction
        inner.parent = popup
        inner.verticalViewport = nil
        inner.scrollTargets = nil
        inner.registerScrollArea = []
        inner.spaces = [:]
        inner.environment.closePresentation = dismiss
        inner.environment.isPresented = true
        let panel = stacked(content(item).resolve(inner.descending(.id(AnyHashable(item.id)))),
                            axis: .vertical, alignment: .center, spacing: 8, direction: inner.environment.layoutDirection)
        qs_popover_dismiss_disabled(popup, interaction.dismissalDisabled ? 1 : 0)
        let direction = context.environment.layoutDirection
        let side: QSPopoverEdge
        switch edge ?? .top {
        case .top: side = QSPopoverAbove
        case .bottom: side = QSPopoverBelow
        case .leading: side = direction == .leftToRight ? QSPopoverLeft : QSPopoverRight
        case .trailing: side = direction == .leftToRight ? QSPopoverRight : QSPopoverLeft
        }
        children[0] = anchor.wrapping(size: anchor.measure) { bounds, proposal in
            anchor.place(bounds, proposal)
            let rect = attachment.rect(in: bounds, direction: direction)
            let size = panel.measure(.unspecified)
            let area = qs_present_popover(popup, context.host.window, context.parent,
                QSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
                QSSize(width: size.width, height: size.height), side, context.environment.colorScheme == .dark ? 1 : 0)
            let panelBounds = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            panel.place(panelBounds, ProposedViewSize(panelBounds.size))
        }
        return children
    }
}

extension View {
    nonisolated public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        Transform(content: self) { view, context in
            if isDisabled { context.presentation?.dismissalDisabled = true }
            return view.resolve(context)
        }
    }

    nonisolated public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                   arrowEdge: Edge? = nil, @ContentBuilder content: @escaping () -> Content) -> some View {
        PopoverView(source: self, selection: BooleanSelection(binding: isPresented), attachment: attachmentAnchor,
                    edge: arrowEdge, content: { _ in content() })
    }

    nonisolated public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge? = nil,
        @ContentBuilder content: @escaping (Item) -> Content) -> some View {
        PopoverView(source: self, selection: ItemSelection(binding: item), attachment: attachmentAnchor,
                    edge: arrowEdge, content: content)
    }
}
