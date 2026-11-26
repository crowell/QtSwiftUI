import QtBridge

@MainActor public protocol Gesture<Value> {
    associatedtype Value = Body.Value
    associatedtype Body: Gesture
    var body: Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none: Self = []
    public static let gesture = Self(rawValue: 1)
    public static let subviews = Self(rawValue: 2)
    public static let all: Self = [.gesture, .subviews]
}

public struct GestureInputKinds: OptionSet, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let directTouch = Self(rawValue: 1), indirectTouch = Self(rawValue: 2)
    public static let pencil = Self(rawValue: 4), pointer = Self(rawValue: 8)
    public static let all = Self(rawValue: .max)
}

struct Recognizer {
    var inputs: GestureInputKinds = .all
    var taps = 0
    var spatialTap: ((Context, UnsafeMutableRawPointer) -> Void)?
    var movesWindow = false
    var dragDistance: CGFloat?
    var drag: ((QSDragSample, Context, UnsafeMutableRawPointer) -> Void)?
    var magnifyDelta: CGFloat?
    var magnify: ((QSMagnifySample) -> Void)?
    var reset: (() -> Void)?
    var ended: () -> Void
}

@MainActor protocol NativeGesture {
    func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer
}

extension Gesture {
    func resolve(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        if let primitive = self as? any NativeGesture { return primitive.recognizer(changed: changed, ended: ended) }
        return body.resolve(changed: changed, ended: ended)
    }
    nonisolated public func onEnded(_ action: @escaping (Value) -> Void) -> _EndedGesture<Self> {
        _EndedGesture(content: self, action: action)
    }
}

extension Gesture where Body == Never {
    public var body: Never { fatalError("Primitive gestures are recognized by Qt") }
}

nonisolated public struct TapGesture: Gesture, NativeGesture {
    public typealias Value = Void
    public typealias Body = Never
    public var count: Int
    private var inputs: GestureInputKinds = .all
    public init(count: Int = 1) { self.count = count }
    public init(count: Int = 1, inputKinds: GestureInputKinds = .all) {
        self.count = count
        inputs = inputKinds
    }
    func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(inputs: inputs, taps: count) { ended(()) }
    }
}

private struct WindowMove: Gesture, NativeGesture {
    typealias Body = Never
    typealias Value = WindowDragGesture.Value
    func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        Recognizer(movesWindow: true) { ended(Value()) }
    }
}

nonisolated public struct WindowDragGesture: Gesture {
    public struct Value: Equatable {}
    public init() {}
    public var body: some Gesture<Value> { WindowMove() }
}

nonisolated public struct _EndedGesture<Content: Gesture>: Gesture, NativeGesture {
    public typealias Body = Never
    public typealias Value = Content.Value
    fileprivate let content: Content
    fileprivate let action: (Value) -> Void
    @MainActor func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        content.resolve(changed: changed) { value in
            if let typed = value as? Value { action(typed) }
            ended(value)
        }
    }
}

extension View {
    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        recognizing(gesture, mask: mask, simultaneous: false)
    }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        recognizing(gesture, mask: mask, simultaneous: true)
    }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View {
        simultaneousGesture(gesture, including: isEnabled ? .all : .subviews)
    }
    private func recognizing<T: Gesture>(_ gesture: T, mask: GestureMask, simultaneous: Bool) -> some View {
        Transform(content: self) { view, ctx in
            let inner = ctx.with(\.gesturesEnabled, ctx.environment.gesturesEnabled && mask.contains(.subviews))
            let enabled = ctx.environment.isEnabled && ctx.environment.gesturesEnabled && mask.contains(.gesture)
            let recognizer = enabled ? gesture.resolve(changed: { _ in }, ended: { _ in }) : nil
            let reset = recognizer?.reset
            if let reset { ctx.host.lifetime(at: ctx.path, appear: {}, disappear: reset) }
            let group = ctx.widget(QSGroup, tap: recognizer?.spatialTap.map { callback in { widget in callback(ctx, widget) } },
                                   drag: recognizer?.drag.map { callback in { sample, widget in
                                       callback(sample, ctx, widget)
                                       if sample.ended != 0 { reset?() }
                                   } }, magnify: recognizer?.magnify.map { callback in { sample in
                                       callback(sample)
                                       if sample.ended != 0 { reset?() }
                                   } }, cancelGesture: reset,
                                   action: { _ in recognizer?.ended(); reset?() })
            qs_group_gesture(group, Int32(clamping: recognizer?.taps ?? 0), recognizer?.movesWindow == true ? 1 : 0,
                             simultaneous ? 1 : 0, recognizer?.dragDistance ?? -1, recognizer?.magnifyDelta ?? -1, Int32(recognizer?.inputs.rawValue ?? 0))
            return inner.children(of: view, inside: group)
        }
    }
    public func gesture<T: Gesture>(_ gesture: T, isEnabled: Bool) -> some View {
        self.gesture(gesture, including: isEnabled ? .all : .subviews)
    }
}
