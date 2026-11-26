import QtBridge

public enum HoverPhase: Equatable {
    case active(CGPoint)
    case ended
}

private nonisolated struct ContinuousHoverView<Content: View>: View {
    let content: Content
    let coordinateSpace: CoordinateSpace
    let action: (HoverPhase) -> Void

    @MainActor var body: some View {
        Transform(content: content) { view, context in
            let group = context.widget(QSGroup, continuousHover: { widget, inside in
                guard inside else { action(.ended); return }
                let point = qs_hover_location(widget)
                let origin = context.origin(of: coordinateSpace, widget: widget)
                action(.active(CGPoint(x: point.width - origin.x, y: point.height - origin.y)))
            })
            qs_continuous_hover(group)
            return context.children(of: view, inside: group)
        }
    }
}

extension View {
    nonisolated public func onContinuousHover(coordinateSpace: some CoordinateSpaceProtocol = .local,
                                              perform action: @escaping (HoverPhase) -> Void) -> some View {
        onContinuousHover(coordinateSpace: coordinateSpace.coordinateSpace, perform: action)
    }

    @_disfavoredOverload nonisolated public func onContinuousHover(coordinateSpace: CoordinateSpace = .local,
                                                                   perform action: @escaping (HoverPhase) -> Void) -> some View {
        ContinuousHoverView(content: self, coordinateSpace: coordinateSpace, action: action)
    }
}
