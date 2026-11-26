import QtBridge

extension Text {
    public enum TruncationMode: Hashable, Sendable {
        case head, tail, middle

        var nativeMode: QSTextTruncation {
            switch self {
            case .head: QSTruncateHead
            case .middle: QSTruncateMiddle
            case .tail: QSTruncateTail
            }
        }
    }
}

extension View {
    nonisolated public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        let apply: @MainActor (Context) -> Context = { $0.with(\.truncationMode, mode) }
        return Transform(content: self, readingContext: apply) { $0.resolve(apply($1)) }
    }
}
