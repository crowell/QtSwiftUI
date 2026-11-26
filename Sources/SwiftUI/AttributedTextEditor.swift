import Foundation
import QtBridge

@MainActor final class AttributedEditorStorage {
    private var ids: [AttributeContainer: Int32] = [:]
    private var attributes: [AttributeContainer] = [AttributeContainer()]
    private var lastValue: AttributedString?
    private var nativeRevision: Int32?
    private var lastFont: Font?
    private var lastScheme: ColorScheme?

    private func format(_ attributes: AttributeContainer, on widget: UnsafeMutableRawPointer, in environment: EnvironmentValues) -> Int32 {
        let id: Int32
        if let existing = ids[attributes] {
            id = existing
        } else {
            id = Int32(self.attributes.count)
            self.attributes.append(attributes)
            ids[attributes] = id
        }
        let font = attributes.font, underline = attributes.underlineStyle, strike = attributes.strikethroughStyle
        qs_rich_define(widget, id, attributes.link?.absoluteString ?? "", attributes.foregroundColor?.hex(environment.colorScheme) ?? "",
                       attributes.backgroundColor?.hex(environment.colorScheme) ?? "", font?.qtFamily ?? "", Double(font?.size ?? 0),
                       font?.qtWeight ?? -1, font?.slanted == true ? 1 : 0,
                       underline?.pattern.qt ?? 0, underline?.color?.hex(environment.colorScheme) ?? "",
                       strike?.pattern.qt ?? 0, strike?.color?.hex(environment.colorScheme) ?? "", Double(attributes.tracking ?? attributes.kern ?? .nan))
        return id
    }

    private func synchronize(_ value: AttributedString, on widget: UnsafeMutableRawPointer, in environment: EnvironmentValues) {
        guard lastValue != value || lastFont != environment.font || lastScheme != environment.colorScheme else { return }
        qs_rich_begin(widget)
        for run in value.runs {
            let id = format(run.attributes, on: widget, in: environment)
            let text = String(value[run.range].characters)
            text.withCString { qs_rich_append(widget, id, $0, text.utf8.count) }
        }
        qs_rich_finish(widget)
        nativeRevision = qs_rich_revision(widget)
        lastValue = value
        lastFont = environment.font
        lastScheme = environment.colorScheme
    }

    private func read(_ widget: UnsafeMutableRawPointer) -> AttributedString {
        struct Reader {
            let attributes: [AttributeContainer]
            var value = AttributedString()
        }
        var reader = Reader(attributes: attributes)
        withUnsafeMutablePointer(to: &reader) { state in
            qs_rich_read(widget, state) { pointer, id, bytes, count in
                let reader = pointer!.assumingMemoryBound(to: Reader.self)
                let text = String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
                let index = Int(id)
                let attributes = reader.pointee.attributes.indices.contains(index) ? reader.pointee.attributes[index] : AttributeContainer()
                reader.pointee.value += AttributedString(text, attributes: attributes)
            }
        }
        return reader.value
    }

    private func applySelection(_ cursor: AttributedTextSelection, in value: AttributedString, to widget: UnsafeMutableRawPointer, environment: EnvironmentValues) {
        let ranges: [Range<AttributedString.Index>]
        switch cursor.indices(in: value) {
        case .insertionPoint(let point): ranges = [point..<point]
        case .ranges(let set): ranges = Array(set.ranges)
        }
        let plain = String(value.characters)
        let offsets = ranges.compactMap { range -> QSTextRange? in
            guard let plainRange = Range<String.Index>(range, in: plain) else { return nil }
            let ns = NSRange(plainRange, in: plain)
            return QSTextRange(start: Int32(clamping: ns.location), end: Int32(clamping: NSMaxRange(ns)))
        }
        offsets.withUnsafeBufferPointer { qs_editor_select(widget, $0.baseAddress, $0.count, environment.selectionAffinity == .upstream ? 1 : 0) }
        if case .insertionPoint = cursor.indices(in: value) {
            qs_rich_typing(widget, format(cursor.typingAttributes(in: value), on: widget, in: environment))
        }
    }

    func editor(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>?, context: Context) -> UnsafeMutableRawPointer {
        func updateText(_ widget: UnsafeMutableRawPointer) -> Bool {
            let revision = qs_rich_revision(widget)
            guard revision != nativeRevision else { return true }
            nativeRevision = revision
            let value = read(widget)
            lastValue = value
            if text.wrappedValue != value { text.wrappedValue = value }
            let accepted = text.wrappedValue
            guard accepted != value else { return true }
            synchronize(accepted, on: widget, in: context.environment)
            if let selection { applySelection(selection.wrappedValue, in: accepted, to: widget, environment: context.environment) }
            return false
        }
        let widget = context.widget(QSRichEditor, cursorChanged: { widget in
            guard let selection, updateText(widget) else { return }
            let value = text.wrappedValue
            let offsets = qs_editor_selection(widget)
            let plain = String(value.characters)
            guard let plainRange = Range(NSRange(location: Int(offsets.start), length: Int(offsets.end - offsets.start)), in: plain),
                  let range = Range<AttributedString.Index>(plainRange, in: value) else { return }
            var cursor = AttributedTextSelection(range: range)
            cursor.selectionAffinity = context.environment.selectionAffinity
            if selection.wrappedValue != cursor { selection.wrappedValue = cursor }
        }, tap: { _ = updateText($0) })
        synchronize(text.wrappedValue, on: widget, in: context.environment)
        if let selection { applySelection(selection.wrappedValue, in: text.wrappedValue, to: widget, environment: context.environment) }
        qs_autocorrection(widget, context.environment.autocorrectionDisabled ? 1 : 0)
        return widget
    }
}
