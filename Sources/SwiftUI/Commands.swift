import QtBridge

extension View {
    public func onExitCommand(perform action: (() -> Void)?) -> some View {
        Transform(content: self) { view, ctx in
            let scope = ctx.widget(QSGroup, exitCommand: action)
            qs_exit_scope(scope, action == nil ? 0 : 1)
            var childContext = ctx.descending(.position(0))
            childContext.parent = scope
            let child = stacked(view.resolve(childContext), axis: .vertical, alignment: .center, spacing: 8)
            return [Element(size: child.measure) { bounds, proposal in
                qs_place(scope, bounds.minX, bounds.minY, bounds.width, bounds.height)
                child.place(CGRect(origin: .zero, size: bounds.size), proposal)
            }]
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
