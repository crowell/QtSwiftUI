struct TextFieldCallbacks {
    var changed: ((Bool) -> Void)?
    var committed: (() -> Void)?

    @MainActor func session(in context: Context) -> TextFieldEditingSession {
        let key = context.path + [.property("text field editing")]
        let session = context.host.storage[key] as? TextFieldEditingSession ?? TextFieldEditingSession()
        if !context.host.isMeasuringAlternative {
            context.host.liveStorage.insert(key)
            context.host.storage[key] = session
            session.callbacks = self
        }
        return session
    }
}

@MainActor final class TextFieldEditingSession {
    var callbacks = TextFieldCallbacks()
    private var focused = false
    private var typing = false

    func focus(_ active: Bool) {
        guard active != focused else { return }
        focused = active
        if active { callbacks.changed?(true) } else { commit() }
    }

    // AppKit begins a new editing session on the first edit, including after Return
    // when the field still has keyboard focus.
    func beginTyping() {
        guard !typing else { return }
        typing = true
        callbacks.changed?(true)
    }

    func commit() {
        typing = false
        callbacks.changed?(false)
        callbacks.committed?()
    }
}

extension TextField where Label == Text {
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) {
        self.init(titleKey, text: text)
        callbacks = .init(changed: onEditingChanged, committed: onCommit)
    }
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) {
        self.init(titleKey, text: text)
        callbacks = .init(changed: onEditingChanged)
    }
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(titleKey, text: text)
        callbacks = .init(committed: onCommit)
    }
    @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) {
        self.init(title, text: text)
        callbacks = .init(changed: onEditingChanged, committed: onCommit)
    }
    @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) {
        self.init(title, text: text)
        callbacks = .init(changed: onEditingChanged)
    }
    @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(title, text: text)
        callbacks = .init(committed: onCommit)
    }
}

extension SecureField where Label == Text {
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(titleKey, text: text)
        callbacks = .init(committed: onCommit)
    }
    @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(title, text: text)
        callbacks = .init(committed: onCommit)
    }
}
