@frozen nonisolated public struct AnyGesture<Value>: Gesture, NativeGesture {
    public typealias Body = Never
    private let content: any Gesture<Value>

    public init<T: Gesture>(_ gesture: T) where T.Value == Value {
        content = gesture
    }

    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        content.resolve(in: context, changed: changed, ended: ended)
    }
}

extension Gesture {
    nonisolated public func map<T>(_ body: @escaping (Value) -> T) -> _MapGesture<Self, T> {
        _MapGesture(content: self, transform: body)
    }
}

nonisolated public struct _MapGesture<Content: Gesture, Value>: Gesture, NativeGesture {
    public typealias Body = Never
    fileprivate let content: Content
    fileprivate let transform: (Content.Value) -> Value

    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        content.resolve(in: context, changed: { value in
            if let value = value as? Content.Value { changed(transform(value) as Any) }
        }, ended: { value in
            if let value = value as? Content.Value { ended(transform(value) as Any) }
        })
    }
}

extension Optional: Gesture, NativeGesture where Wrapped: Gesture {
    public typealias Body = Never
    public typealias Value = Wrapped.Value

    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        self?.resolve(in: context, changed: changed, ended: ended) ?? Recognizer(ended: {})
    }
}
