import Foundation

enum FieldValue {
    case text(Binding<String>)
    case formatted(display: () -> String, edit: (String) -> String?)

    init<F: ParseableFormatStyle>(_ value: Binding<F.FormatInput>, format: F) where F.FormatOutput == String {
        self = .formatted(display: { format.format(value.wrappedValue) }, edit: { text in
            do {
                let parsed = try format.parseStrategy.parse(text)
                value.wrappedValue = parsed
                return format.format(value.isConstant ? value.wrappedValue : parsed)
            } catch {
                return nil
            }
        })
    }

    init<F: ParseableFormatStyle>(_ value: Binding<F.FormatInput?>, format: F) where F.FormatOutput == String {
        self = .formatted(display: { value.wrappedValue.map(format.format) ?? "" }, edit: { text in
            let parsed = try? format.parseStrategy.parse(text)
            value.wrappedValue = parsed
            let accepted = value.isConstant ? value.wrappedValue : parsed
            return accepted.map(format.format) ?? ""
        })
    }

    @MainActor func resolve(in context: Context, callbacks: TextFieldCallbacks?) -> (Binding<String>, TextFieldEditingSession?) {
        switch self {
        case .text(let binding):
            return (binding, callbacks?.session(in: context))
        case .formatted(let display, let edit):
            let editing = (callbacks ?? TextFieldCallbacks()).session(in: context)
            // Keep the user's spelling, even when parsing it changes the model.
            let text = Binding {
                let current = display()
                if let draft = editing.draft, draft.formatted == nil || draft.formatted == current { return draft.text }
                editing.draft = nil
                return current
            } set: { raw in
                editing.draft = (raw, edit(raw))
            }
            return (text, editing)
        }
    }
}

extension TextField where Label == Text {
    nonisolated public init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: .text(Text(titleKey)), value: FieldValue(value, format: format), prompt: prompt)
    }

    nonisolated public init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil)
    where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: .text(Text(titleKey)), value: FieldValue(value, format: format), prompt: prompt)
    }

    @_disfavoredOverload nonisolated public init<S, F>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where S: StringProtocol, F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: .text(Text(verbatim: String(title))), value: FieldValue(value, format: format), prompt: prompt)
    }

    @_disfavoredOverload nonisolated public init<S, F>(_ title: S, value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil)
    where S: StringProtocol, F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: .text(Text(verbatim: String(title))), value: FieldValue(value, format: format), prompt: prompt)
    }
}

extension TextField {
    nonisolated public init<F>(value: Binding<F.FormatInput>, format: F, prompt: Text? = nil, @ContentBuilder label: () -> Label)
    where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: FieldTitle(label()), value: FieldValue(value, format: format), prompt: prompt)
    }

    nonisolated public init<F>(value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil, @ContentBuilder label: () -> Label)
    where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(configuration: FieldTitle(label()), value: FieldValue(value, format: format), prompt: prompt)
    }
}
