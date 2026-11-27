import QtBridge

nonisolated public struct SpatialTapGesture: Gesture, NativeGesture {
    public typealias Body = Never
    public struct Value: Equatable, Sendable { public var location: CGPoint }
    private var inputs: GestureInputKinds = .all
    public var count: Int
    public var coordinateSpace: CoordinateSpace
    @_disfavoredOverload public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace
    }
    public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.init(count: count, coordinateSpace: coordinateSpace.coordinateSpace)
    }
    public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local, inputKinds: GestureInputKinds = .all) {
        self.init(count: count, coordinateSpace: coordinateSpace.coordinateSpace)
        inputs = inputKinds
    }
    @MainActor func recognizer(in context: Context, changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(inputs: inputs, taps: count, spatialTap: { context, widget in
            let transform = context.windowToSpace(coordinateSpace, widget: widget)
            let point = qs_tap_location(widget)
            ended(Value(location: CGPoint(x: point.width, y: point.height).applying(transform)))
        }, ended: {})
    }
}

private nonisolated struct SpatialTapView<Content: View>: View {
    let content: Content
    let gesture: SpatialTapGesture
    let perform: (CGPoint) -> Void
    @MainActor var body: some View { content.gesture(gesture.onEnded { perform($0.location) }) }
}

extension View {
    nonisolated public func onTapGesture(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local,
                                         inputKinds: GestureInputKinds = .all, perform action: @escaping (CGPoint) -> Void) -> some View {
        SpatialTapView(content: self, gesture: SpatialTapGesture(count: count, coordinateSpace: coordinateSpace, inputKinds: inputKinds), perform: action)
    }
    @_disfavoredOverload nonisolated public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local,
                                                               perform action: @escaping (CGPoint) -> Void) -> some View {
        SpatialTapView(content: self, gesture: SpatialTapGesture(count: count, coordinateSpace: coordinateSpace), perform: action)
    }
    nonisolated public func onTapGesture(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local,
                                         perform action: @escaping (CGPoint) -> Void) -> some View {
        onTapGesture(count: count, coordinateSpace: coordinateSpace.coordinateSpace, perform: action)
    }
}
