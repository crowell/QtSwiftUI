public enum ControlSize: CaseIterable, Comparable, Sendable {
    case mini, small, regular, large, extraLarge

    var qtScale: Double {
        switch self {
        case .mini: 0.7
        case .small: 0.85
        case .regular: 1
        case .large: 1.15
        case .extraLarge: 1.35
        }
    }
}

public protocol TextFieldStyle {
    associatedtype _Body: View
    typealias _Label = _TextFieldStyleLabel
    @ContentBuilder func _body(configuration: TextField<Self._Label>) -> _Body
}

public nonisolated struct _TextFieldStyleLabel: Primitive {
    @MainActor func elements(in context: Context) -> [Element] { [] }
}

enum FieldBorder: Int32 {
    case square, plain, rounded
}

extension TextField where Label == _TextFieldStyleLabel {
    fileprivate func border(_ border: FieldBorder) -> some View {
        environment(\.fieldBorder, border)
    }
}

public struct BorderedTextFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<_Label>) -> some View { configuration.border(.rounded) }
}

extension TextFieldStyle where Self == BorderedTextFieldStyle {
    public static var bordered: BorderedTextFieldStyle { .init() }
}

public struct SquareBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<_Label>) -> some View { configuration.border(.square) }
}

extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    public static var squareBorder: SquareBorderTextFieldStyle { .init() }
}

public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<_Label>) -> some View {
        configuration.border(.plain)
    }
}

public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<_Label>) -> some View {
        configuration.border(.rounded)
    }
}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: Self { Self() }
}

public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
    public func _body(configuration: TextField<_Label>) -> some View { configuration }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}
extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

private nonisolated struct StyledField<Content: View, Style: TextFieldStyle>: View {
    let content: Content
    let style: Style
    @MainActor var body: some View {
        Transform(content: content) { view, ctx in
            view.resolve(ctx.with(\.fieldStyle, { AnyView(style._body(configuration: $0)) }))
        }
    }
}

extension View {
    nonisolated public func controlSize(_ controlSize: ControlSize) -> some View {
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.controlSize, controlSize)) }
    }
    nonisolated public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        StyledField(content: self, style: style)
    }
    nonisolated public func scrollDisabled(_ disabled: Bool) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.isScrollEnabled, ctx.environment.isScrollEnabled && !disabled))
        }
    }
}
