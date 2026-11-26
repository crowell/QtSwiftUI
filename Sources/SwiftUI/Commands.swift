import QtBridge

extension View {
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
