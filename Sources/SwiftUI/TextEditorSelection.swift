import QtBridge

public enum TextSelectionAffinity: Hashable, Sendable { case automatic, upstream, downstream }

public struct TextSelection: Equatable, Hashable {
    public enum Indices: Equatable, Hashable {
        case selection(Range<String.Index>)
        case multiSelection(RangeSet<String.Index>)
    }
    public var indices: Indices
    public internal(set) var affinity: TextSelectionAffinity = .automatic
    public init(range: Range<String.Index>) { indices = .selection(range) }
    public init(ranges: RangeSet<String.Index>) { indices = .multiSelection(ranges) }
    public init(insertionPoint: String.Index) { indices = .selection(insertionPoint..<insertionPoint) }
    public var isInsertion: Bool {
        if case .selection(let range) = indices { return range.isEmpty }
        return false
    }

    func offsets(in text: String) -> [QSTextRange] {
        let ranges: [Range<String.Index>]
        switch indices {
        case .selection(let range): ranges = [range]
        case .multiSelection(let set): ranges = Array(set.ranges)
        }
        return ranges.compactMap { range in
            guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex,
                  let start = range.lowerBound.samePosition(in: text.utf16),
                  let end = range.upperBound.samePosition(in: text.utf16) else { return nil }
            return QSTextRange(start: Int32(clamping: start.utf16Offset(in: text)), end: Int32(clamping: end.utf16Offset(in: text)))
        }
    }
}

extension View {
    nonisolated public func textSelectionAffinity(_ affinity: TextSelectionAffinity) -> some View {
        Transform(content: self) { view, context in view.resolve(context.with(\.selectionAffinity, affinity)) }
    }
}

@MainActor func nativeEditorText(_ widget: UnsafeMutableRawPointer) -> String {
    var count = 0
    let bytes = qs_editor_value(widget, &count)
    return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
}

@MainActor struct EditorSelection {
    let binding: Binding<TextSelection?>
    let text: Binding<String>
    let affinity: TextSelectionAffinity

    func apply(to widget: UnsafeMutableRawPointer) {
        guard let selection = binding.wrappedValue else { return }
        let ranges = selection.offsets(in: text.wrappedValue)
        ranges.withUnsafeBufferPointer { qs_editor_select(widget, $0.baseAddress, $0.count, affinity == .upstream ? 1 : 0) }
    }

    // The native cursor indexes the edited string. A binding can still read the previous render.
    func changed(_ widget: UnsafeMutableRawPointer, text: String) {
        let range = qs_editor_selection(widget)
        guard range.start >= 0, range.end >= range.start, Int(range.end) <= text.utf16.count else { return }
        let start = String.Index(utf16Offset: Int(range.start), in: text)
        let end = String.Index(utf16Offset: Int(range.end), in: text)
        var selection = TextSelection(range: start..<end)
        selection.affinity = affinity
        if binding.wrappedValue != selection { binding.wrappedValue = selection }
    }
}
