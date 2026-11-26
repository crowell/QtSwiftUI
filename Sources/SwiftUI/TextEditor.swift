import QtBridge

public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic, visible, hidden
}

extension View {
    public func scrollContentBackground(_ visibility: Visibility) -> some View {
        environment(\.scrollBackground, visibility)
    }
}

@MainActor func boundEditor(_ kind: QSKind, text: Binding<String>, selection: EditorSelection? = nil, in context: Context) -> UnsafeMutableRawPointer {
    func synchronize(_ widget: UnsafeMutableRawPointer) {
        let value = text.wrappedValue
        value.withCString { qs_editor_text(widget, $0, value.utf8.count) }
    }
    func updateText(_ editor: UnsafeMutableRawPointer) {
        var count = 0
        let bytes = qs_editor_value(editor, &count)
        let value = String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        if value != text.wrappedValue {
            text.wrappedValue = value
            if value != text.wrappedValue { synchronize(editor) }
        }
    }
    let widget = context.widget(kind, cursorChanged: { editor in
        guard let selection else { return }
        updateText(editor)
        selection.changed(editor)
    }, tap: updateText)
    synchronize(widget)
    selection?.apply(to: widget)
    qs_autocorrection(widget, context.environment.autocorrectionDisabled ? 1 : 0)
    return widget
}

public nonisolated struct TextEditor: Primitive {
    private enum Content {
        case plain(Binding<String>, Binding<TextSelection?>?)
        case attributed(Binding<AttributedString>, Binding<AttributedTextSelection>?)
    }
    private let content: Content
    public nonisolated init(text: Binding<String>) { content = .plain(text, nil) }
    public nonisolated init(text: Binding<String>, selection: Binding<TextSelection?>) { content = .plain(text, selection) }
    public nonisolated init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil) {
        content = .attributed(text, selection)
    }

    @MainActor func elements(in context: Context) -> [Element] {
        let widget: UnsafeMutableRawPointer
        let value: String
        switch content {
        case .plain(let text, let selection):
            let cursor = selection.map { EditorSelection(binding: $0, text: text, affinity: context.environment.selectionAffinity) }
            widget = boundEditor(QSTextEditor, text: text, selection: cursor, in: context)
            value = text.wrappedValue
        case .attributed(let text, let selection):
            let key = context.path + [.property("attributedEditor")]
            let storage = context.host.storage[key] as? AttributedEditorStorage ?? AttributedEditorStorage()
            if !context.host.isMeasuringAlternative {
                context.host.liveStorage.insert(key)
                context.host.storage[key] = storage
            }
            widget = storage.editor(text: text, selection: selection, context: context)
            value = String(text.wrappedValue.characters)
        }
        let font = context.environment.font
        context.with(\.font, font ?? .custom("Helvetica", fixedSize: 12)).style(widget)
        qs_scroll_background(widget, context.environment.scrollBackground == .hidden ? 0 : 1,
                             context.environment.colorScheme == .dark ? 1 : 0)
        qs_scroll_input(widget, context.environment.isScrollEnabled ? 1 : 0)
        qs_scroll_bounce(widget, -1, context.environment.verticalScrollBounceBehavior.policy)
        qs_editor_indicators(widget, context.environment.isScrollEnabled && context.environment.verticalScrollIndicatorVisibility.showsBar ? 1 : 0)
        let ideal = font == nil ? CGFloat(12 * (value.filter(\.isNewline).count + 1)) : qs_measure(widget, -1).height
        return [Element { proposal in
            CGSize(width: proposal.width ?? 0, height: proposal.height ?? ideal)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }]
    }
}
