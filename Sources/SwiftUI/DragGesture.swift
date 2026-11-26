import QtBridge

public struct DragGesture: Gesture, NativeGesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        private let speed: CGSize
        fileprivate init(sample: QSDragSample, origin: CGPoint) {
            time = Date(timeIntervalSince1970: sample.time)
            location = CGPoint(x: sample.x - origin.x, y: sample.y - origin.y)
            startLocation = CGPoint(x: sample.startX - origin.x, y: sample.startY - origin.y)
            speed = CGSize(width: sample.velocityX, height: sample.velocityY)
        }
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        public var velocity: CGSize { speed }
        public var predictedEndLocation: CGPoint { CGPoint(x: location.x + speed.width / 4, y: location.y + speed.height / 4) }
        public var predictedEndTranslation: CGSize {
            CGSize(width: predictedEndLocation.x - startLocation.x, height: predictedEndLocation.y - startLocation.y)
        }
    }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    @_disfavoredOverload public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.init(minimumDistance: minimumDistance, coordinateSpace: coordinateSpace.coordinateSpace)
    }
    func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(dragDistance: max(0, minimumDistance), drag: { sample, context, widget in
            let origin: CGPoint
            switch coordinateSpace {
            case .global: origin = .zero
            case .local:
                let position = qs_origin(widget)
                origin = CGPoint(x: position.width, y: position.height)
            case .named(let name): origin = context.spaces[name]?.point ?? .zero
            }
            let value = Value(sample: sample, origin: origin)
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
    @MainActor func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        content.resolve(changed: { value in
            if let typed = value as? Value { action(typed) }
            changed(value)
        }, ended: ended)
    }
}
