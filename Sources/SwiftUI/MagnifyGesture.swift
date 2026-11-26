import QtBridge

nonisolated public struct MagnifyGesture: Gesture, NativeGesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }

    public var minimumScaleDelta: CGFloat
    private var inputs: GestureInputKinds
    public init(minimumScaleDelta: CGFloat = 0.01) {
        self.init(minimumScaleDelta: minimumScaleDelta, inputKinds: .all)
    }
    public init(minimumScaleDelta: CGFloat = 0.01, inputKinds: GestureInputKinds = .all) {
        self.minimumScaleDelta = minimumScaleDelta
        inputs = inputKinds
    }

    @MainActor func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(inputs: inputs, magnifyDelta: max(0, minimumScaleDelta), magnify: { sample in
            let value = Value(time: Date(timeIntervalSinceReferenceDate: sample.time), magnification: sample.factor,
                              velocity: sample.velocity, startAnchor: UnitPoint(x: sample.anchorX, y: sample.anchorY),
                              startLocation: CGPoint(x: sample.x, y: sample.y))
            if sample.ended != 0 { ended(value) } else { changed(value) }
        }, ended: {})
    }
}

nonisolated public struct MagnificationGesture: Gesture, NativeGesture {
    public typealias Body = Never
    public typealias Value = CGFloat
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
    @MainActor func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(magnifyDelta: max(0, minimumScaleDelta), magnify: { sample in
            let value = CGFloat(sample.factor)
            if sample.ended != 0 { ended(value) } else { changed(value) }
        }, ended: {})
    }
}
