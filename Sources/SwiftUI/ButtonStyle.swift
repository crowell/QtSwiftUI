@MainActor public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}
public struct ButtonStyleConfiguration {
    public struct Label: View {
        let content: AnyView
        public var body: some View { content }
    }
    public let label: Label
    public let isPressed: Bool
}
public struct PlainButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}
extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: Self { Self() }
}
extension View {
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.buttonStyle, { AnyView(style.makeBody(configuration: $0)) }))
        }
    }
}
