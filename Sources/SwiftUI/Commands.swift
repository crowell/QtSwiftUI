import QtBridge

public enum MoveCommandDirection: Hashable, Sendable {
    case up, down, left, right

    init?(qtDirection: String) {
        switch qtDirection {
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        default: return nil
        }
    }
}

private nonisolated struct MoveCommandScope<Content: View>: Primitive, SubviewSource {
    let content: Content
    let action: ((MoveCommandDirection) -> Void)?

    @MainActor func elements(in context: Context) -> [Element] { wrap(content, in: context) }
    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { $0.applying { view, destination in wrap(view, in: destination) } }
    }
    @MainActor private func wrap(_ view: any View, in context: Context) -> [Element] {
        let group = context.widget(QSGroup, moveCommand: action)
        qs_move_scope(group, action == nil ? 0 : 1)
        return context.children(of: view, inside: group)
    }
}

extension View {
    nonisolated public func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
        MoveCommandScope(content: self, action: action)
    }

    public func onExitCommand(perform action: (() -> Void)?) -> some View {
        Transform(content: self) { view, ctx in
            let scope = ctx.widget(QSGroup, exitCommand: action)
            qs_exit_scope(scope, action == nil ? 0 : 1)
            return ctx.children(of: view, inside: scope)
        }
    }
}
@MainActor public struct DismissAction {
    var perform: () -> Void
    public func callAsFunction() { perform() }
}
extension EnvironmentValues {
    @MainActor public var dismiss: DismissAction { DismissAction(perform: closePresentation) }
}
