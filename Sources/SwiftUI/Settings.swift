public nonisolated struct Settings<Content: View>: SceneCollection {
    private let view: Content

    public init(@ContentBuilder content: () -> Content) { view = content() }

    public var body: Never { fatalError("Primitive settings scene") }

    @MainActor var windows: [WindowScene] {
        [WindowScene(title: "Settings", id: nil, single: true, isSettings: true,
                     resizability: .contentSize, content: { view.resolve($0) })]
    }
}

@MainActor public struct OpenSettingsAction {
    fileprivate let present: @MainActor () -> Void

    public func callAsFunction() { present() }
}

extension EnvironmentValues {
    public var openSettings: OpenSettingsAction { OpenSettingsAction(present: presentSettings ?? {}) }
}

public nonisolated struct DefaultSettingsLinkLabel: View {
    public var body: some View { Label("Settings…", systemImage: "gearshape") }
}

public nonisolated struct SettingsLink<Label: View>: View {
    private let label: Label

    public init() where Label == DefaultSettingsLinkLabel { label = DefaultSettingsLinkLabel() }
    public init(@ContentBuilder label: () -> Label) { self.label = label() }

    @MainActor public var body: some View {
        Transform(content: label) { _, context in
            let open = context.environment.openSettings
            return Button(action: { open() }) { label }
                .disabled(context.environment.presentSettings == nil)
                .resolve(context)
        }
    }
}
