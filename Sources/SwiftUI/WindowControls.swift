import QtBridge

struct WindowControls: PreferenceKey {
    var dismiss: Bool?
    var minimize: Bool?

    static var defaultValue: Self { Self() }
    static func reduce(value: inout Self, nextValue: () -> Self) {
        value.fillDefaults(from: nextValue())
    }

    mutating func fillDefaults(from other: Self) {
        dismiss = dismiss ?? other.dismiss
        minimize = minimize ?? other.minimize
    }

    func apply(to window: OpaquePointer?) {
        qs_window_controls(window, dismiss == false ? 0 : 1, minimize == false ? 0 : 1)
    }
}

private nonisolated struct WindowControlView<Content: View>: View {
    let content: Content
    let controls: WindowControls
    @MainActor var body: some View {
        content.transformPreference(WindowControls.self) { $0.fillDefaults(from: controls) }
    }
}

extension View {
    nonisolated public func windowDismissBehavior(_ behavior: WindowInteractionBehavior) -> some View {
        WindowControlView(content: self, controls: WindowControls(dismiss: behavior.enabled))
    }
    nonisolated public func windowMinimizeBehavior(_ behavior: WindowInteractionBehavior) -> some View {
        WindowControlView(content: self, controls: WindowControls(minimize: behavior.enabled))
    }
}
