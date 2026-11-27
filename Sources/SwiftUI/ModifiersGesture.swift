extension Gesture {
    @preconcurrency public func modifiers(_ modifiers: EventModifiers) -> _ModifiersGesture<Self> {
        _ModifiersGesture(content: self, modifiers: modifiers)
    }
}

nonisolated public struct _ModifiersGesture<Content: Gesture>: Gesture, NativeGesture {
    public typealias Body = Never
    public typealias Value = Content.Value
    fileprivate let content: Content
    fileprivate let modifiers: EventModifiers

    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        var recognizer = content.resolve(in: context, changed: changed, ended: ended)
        recognizer.modifiers.formUnion(modifiers)
        return recognizer
    }
}
