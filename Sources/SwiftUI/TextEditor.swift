import QtBridge

public enum Visibility: Hashable, CaseIterable, Sendable {
    case automatic, visible, hidden
}

extension View {
    public func scrollContentBackground(_ visibility: Visibility) -> some View {
        environment(\.scrollBackground, visibility)
    }
}

public struct TextEditor: Primitive {
    private let text: Binding<String>
    public nonisolated init(text: Binding<String>) { self.text = text }

    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSTextEditor, tap: { editor in
            var count = 0
            let bytes = qs_editor_value(editor, &count)
            let value = String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
            if value != text.wrappedValue { text.wrappedValue = value }
        })
        let value = text.wrappedValue
        value.withCString { qs_editor_text(widget, $0, value.utf8.count) }
        let font = context.environment.font
        context.with(\.font, font ?? .custom("Helvetica", fixedSize: 12)).style(widget)
        qs_scroll_background(widget, context.environment.scrollBackground == .hidden ? 0 : 1,
                             context.environment.colorScheme == .dark ? 1 : 0)
        qs_editor_indicators(widget, context.environment.verticalScrollIndicatorVisibility.showsBar ? 1 : 0)
        let ideal = font == nil ? CGFloat(12 * (value.filter(\.isNewline).count + 1)) : qs_measure(widget, -1).height
        return [Element { proposal in
            CGSize(width: proposal.width ?? 0, height: proposal.height ?? ideal)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }]
    }
}
