import QtBridge

public struct DragGesture: Gesture, NativeGesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        private let speed: CGSize
        fileprivate init(sample: QSDragSample, transform: CGAffineTransform) {
            time = Date(timeIntervalSince1970: sample.time)
            location = CGPoint(x: sample.x, y: sample.y).applying(transform)
            startLocation = CGPoint(x: sample.startX, y: sample.startY).applying(transform)
            speed = CGSize(width: sample.velocityX, height: sample.velocityY).applying(transform)
        }
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        public var velocity: CGSize { speed }
        public var predictedEndLocation: CGPoint { CGPoint(x: location.x + speed.width / 4, y: location.y + speed.height / 4) }
        public var predictedEndTranslation: CGSize {
            CGSize(width: predictedEndLocation.x - startLocation.x, height: predictedEndLocation.y - startLocation.y)
        }
    }
    private var inputs: GestureInputKinds = .all
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    @_disfavoredOverload public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.init(minimumDistance: minimumDistance, coordinateSpace: coordinateSpace.coordinateSpace)
    }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local, inputKinds: GestureInputKinds = .all) {
        self.init(minimumDistance: minimumDistance, coordinateSpace: coordinateSpace.coordinateSpace)
        inputs = inputKinds
    }
    func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(inputs: inputs, dragDistance: max(0, minimumDistance), drag: { sample, context, widget in
            let value = Value(sample: sample, transform: context.windowToSpace(coordinateSpace, widget: widget))
            if sample.ended != 0 { ended(value) } else { changed(value) }
        }, ended: {})
    }
}

extension Gesture where Value: Equatable {
    nonisolated public func onChanged(_ action: @escaping (Value) -> Void) -> _ChangedGesture<Self> {
        .init(content: self, action: action)
    }
}

nonisolated public struct _ChangedGesture<Content: Gesture>: Gesture, NativeGesture where Content.Value: Equatable {
    public typealias Body = Never
    public typealias Value = Content.Value
    fileprivate let content: Content
    fileprivate let action: (Value) -> Void
    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        let path = context.path
        context.host.liveStorage.insert(path)
        let history = context.host.storage[path] as? GestureHistory<Value> ?? GestureHistory()
        context.host.storage[path] = history
        var recognizer = content.resolve(in: context, changed: { value in
            if let typed = value as? Value, history.last != .some(typed) {
                history.last = .some(typed)
                action(typed)
            }
            changed(value)
        }, ended: ended)
        let reset = recognizer.reset
        recognizer.reset = { history.last = nil; reset?() }
        return recognizer
    }
}

private final class GestureHistory<Value> {
    var last: Value?
}
