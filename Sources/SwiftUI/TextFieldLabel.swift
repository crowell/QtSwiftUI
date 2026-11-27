import QtBridge

// The desktop field uses the first Text in the label's drawing order as its prompt.
enum FieldTitle {
    case text(Text)
    case view(AnyView)

    init<Label: View>(_ label: Label) {
        if let text = label as? Text { self = .text(text) }
        else { self = .view(AnyView(label)) }
    }

    @MainActor func resolve(in context: Context) -> (text: Text, locale: Locale)? {
        switch self {
        case .text(let text):
            return (text, context.environment.locale)
        case .view(let label):
            let reader = FieldLabelReader()
            var inner = context.descending(.property("text field label"))
            inner.environment.focus = nil
            inner.environment.keyboardShortcut = nil
            let container = inner.widget(QSGroup)
            qs_drawing_only(container)
            inner.parent = container
            inner.fieldLabelReader = reader
            for element in label.resolve(inner) {
                let size = element.measure(.unspecified)
                element.place(CGRect(origin: .zero, size: size), .unspecified)
            }
            return reader.first
        }
    }
}

@MainActor final class FieldLabelReader {
    var first: (text: Text, locale: Locale)?
}

extension TextField {
    nonisolated public init(text: Binding<String>, prompt: Text? = nil, @ContentBuilder label: () -> Label) {
        self.init(configuration: FieldTitle(label()), value: .text(text), prompt: prompt)
    }
    nonisolated public init(text: Binding<String>, prompt: Text? = nil, axis: Axis, @ContentBuilder label: () -> Label) {
        self.init(configuration: FieldTitle(label()), value: .text(text), prompt: prompt, axis: axis)
    }
    nonisolated public init(text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil, @ContentBuilder label: () -> Label) {
        self.init(configuration: FieldTitle(label()), value: .text(text), selection: selection, prompt: prompt, axis: axis ?? .horizontal)
    }
}

extension SecureField {
    nonisolated public init(text: Binding<String>, prompt: Text? = nil, @ContentBuilder label: () -> Label) {
        title = FieldTitle(label())
        self.text = text
        self.prompt = prompt
    }
}
