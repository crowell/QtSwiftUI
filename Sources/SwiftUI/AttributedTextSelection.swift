import Foundation

public struct AttributedTextSelection: Equatable, Sendable {
    @frozen public enum Indices: Equatable, Sendable {
        case insertionPoint(AttributedString.Index)
        case ranges(RangeSet<AttributedString.Index>)
    }

    private var stored: Indices?
    fileprivate var typing: AttributeContainer?
    var selectionAffinity = TextSelectionAffinity.automatic

    public init() {}
    public init(insertionPoint: AttributedString.Index, typingAttributes: AttributeContainer? = nil) {
        stored = .insertionPoint(insertionPoint)
        typing = typingAttributes
    }
    public init(ranges: RangeSet<AttributedString.Index>) { stored = .ranges(ranges) }
    public init(range: Range<AttributedString.Index>) {
        stored = range.isEmpty ? .insertionPoint(range.lowerBound) : .ranges(RangeSet(range))
    }
    public func indices(in text: AttributedString) -> Indices {
        switch stored {
        case .insertionPoint(let point) where point.isValid(within: text): return .insertionPoint(point)
        case .ranges(let ranges) where ranges.isValid(within: text): return .ranges(ranges)
        default: return .insertionPoint(text.endIndex)
        }
    }
    public func affinity(in text: AttributedString) -> TextSelectionAffinity { selectionAffinity }

    public func typingAttributes(in text: AttributedString) -> AttributeContainer {
        switch indices(in: text) {
        case .insertionPoint(let point):
            if let typing { return typing }
            guard !text.characters.isEmpty else { return AttributeContainer() }
            return text.runs[point == text.startIndex ? point : text.index(beforeUnicodeScalar: point)].attributes
        case .ranges(let ranges):
            guard let first = ranges.ranges.first else { return AttributeContainer() }
            return text.runs[first.lowerBound].attributes
        }
    }

    public struct Attributes<Text>: Sequence {
        fileprivate let values: [AttributeContainer]
        public func makeIterator() -> some IteratorProtocol<AttributeContainer> { values.makeIterator() }
        public subscript<K: AttributedStringKey>(type: KeyPath<AttributeDynamicLookup, K>) -> some Sequence<K.Value?> where K.Value: Sendable {
            values.lazy.map { $0[dynamicMember: type] }
        }
        public subscript<K: AttributedStringKey>(type: K.Type) -> some Sequence<K.Value?> where K.Value: Sendable {
            values.lazy.map { $0[type] }
        }
    }

    public func attributes(in text: AttributedString) -> Attributes<AttributedString> {
        switch indices(in: text) {
        case .insertionPoint: return Attributes(values: [typingAttributes(in: text)])
        case .ranges(let ranges): return Attributes(values: text[ranges].runs.map(\.attributes))
        }
    }
}

extension AttributedString {
    public subscript(selection: AttributedTextSelection) -> DiscontiguousAttributedSubstring {
        switch selection.indices(in: self) {
        case .insertionPoint: return self[RangeSet<Index>()]
        case .ranges(let ranges): return self[ranges]
        }
    }

    public mutating func transform<E: Error>(updating selection: inout AttributedTextSelection,
                                              body: (inout AttributedString) throws(E) -> Void) throws(E) {
        let affinity = selection.selectionAffinity
        switch selection.indices(in: self) {
        case .insertionPoint(let point):
            var range = point..<point
            defer { selection = .init(insertionPoint: range.lowerBound, typingAttributes: selection.typing); selection.selectionAffinity = affinity }
            try transform(updating: &range, body: body)
        case .ranges(let set):
            var ranges = Array(set.ranges)
            defer { selection = .init(ranges: RangeSet(ranges)); selection.selectionAffinity = affinity }
            try transform(updating: &ranges, body: body)
        }
    }

    public mutating func transformAttributes<E: Error>(in selection: inout AttributedTextSelection,
                                                        body: (inout AttributeContainer) throws(E) -> Void) throws(E) {
        switch selection.indices(in: self) {
        case .insertionPoint(let point):
            var attributes = selection.typingAttributes(in: self)
            try body(&attributes)
            selection = .init(insertionPoint: point, typingAttributes: attributes)
        case .ranges(let ranges):
            // Character offsets can cross grapheme boundaries between formatted runs.
            // Scalar offsets stay valid when assigning attributes invalidates Foundation indices.
            let runs = ranges.ranges.flatMap { self[$0].runs }.map {
                (scalarOffset($0.range.lowerBound), scalarOffset($0.range.upperBound), $0.attributes)
            }
            try transform(updating: &selection) { (text: inout AttributedString) throws(E) in
                for (lower, upper, var attributes) in runs {
                    try body(&attributes)
                    let range = text.scalarIndex(lower)..<text.scalarIndex(upper)
                    text[range].setAttributes(attributes)
                }
            }
        }
    }

    public mutating func replaceSelection(_ selection: inout AttributedTextSelection, withCharacters newContent: some Collection<Character>) {
        let replacement = AttributedString(String(newContent), attributes: selection.typingAttributes(in: self))
        replaceSelection(&selection, with: replacement)
    }

    public mutating func replaceSelection(_ selection: inout AttributedTextSelection, with newContent: some AttributedStringProtocol) {
        let ranges: [Range<Index>]
        switch selection.indices(in: self) {
        case .insertionPoint(let point): ranges = [point..<point]
        case .ranges(let set): ranges = set.isEmpty ? [endIndex..<endIndex] : Array(set.ranges)
        }
        let offsets = ranges.map { scalarOffset($0.lowerBound)..<scalarOffset($0.upperBound) }
        let first = offsets[0]
        for span in offsets.dropFirst().reversed() { removeSubrange(scalarIndex(span.lowerBound)..<scalarIndex(span.upperBound)) }
        replaceSubrange(scalarIndex(first.lowerBound)..<scalarIndex(first.upperBound), with: newContent)
        let end = scalarIndex(first.lowerBound + newContent.unicodeScalars.count)
        selection = first.isEmpty || newContent.unicodeScalars.isEmpty ? .init(insertionPoint: end)
            : .init(range: scalarIndex(first.lowerBound)..<end)
    }

    private func scalarOffset(_ index: Index) -> Int { unicodeScalars.distance(from: startIndex, to: index) }
    private func scalarIndex(_ offset: Int) -> Index { index(startIndex, offsetByUnicodeScalars: offset) }
}
