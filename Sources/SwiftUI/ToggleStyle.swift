@MainActor @preconcurrency public protocol ToggleStyle {
    associatedtype Body: View
    typealias Configuration = ToggleStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

public struct ToggleStyleConfiguration {
    public struct Label: View {
        let content: AnyView
        let plainText: Text?
        public var body: some View { content }
    }
    public let label: Label
    @Binding public var isOn: Bool
}

extension Toggle where Label == ToggleStyleConfiguration.Label {
    public init(_ configuration: ToggleStyleConfiguration) {
        self.init(isOn: configuration.$isOn) { configuration.label }
    }
}

public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Toggle(configuration) }
}
public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Toggle(configuration) }
}
extension ToggleStyle where Self == CheckboxToggleStyle {
    public static var checkbox: Self { Self() }
}
extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: Self { Self() }
}
private nonisolated struct StyledToggle<Content: View, Style: ToggleStyle>: View {
    let content: Content
    let style: Style
    @MainActor var body: some View {
        Transform(content: content) { view, ctx in
            view.resolve(ctx.with(\.toggleStyle, { configuration in
                AnyView(ctx.preparing(style).makeBody(configuration: configuration))
            }))
        }
    }
}
extension View {
    nonisolated public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View { StyledToggle(content: self, style: style) }
}
