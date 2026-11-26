@propertyWrapper public struct GestureState<Value>: MountedProperty {
    private struct Phase {
        let initial: Value
        var current: Value
        var active = false
    }
    private let phase: State<Phase>
    private let resetTransaction: (Value) -> Transaction

    public init(wrappedValue: Value) { self.init(wrappedValue: wrappedValue, resetTransaction: Transaction()) }
    public init(wrappedValue: Value, resetTransaction: Transaction) {
        self.init(wrappedValue: wrappedValue, reset: { _, transaction in transaction = resetTransaction })
    }
    public init(wrappedValue: Value, reset: @escaping (Value, inout Transaction) -> Void) {
        phase = State(wrappedValue: Phase(initial: wrappedValue, current: wrappedValue))
        resetTransaction = { value in
            var transaction = Transaction()
            reset(value, &transaction)
            return transaction
        }
    }
    public init(initialValue: Value) { self.init(wrappedValue: initialValue) }
    public init(initialValue: Value, resetTransaction: Transaction) { self.init(wrappedValue: initialValue, resetTransaction: resetTransaction) }
    public init(initialValue: Value, reset: @escaping (Value, inout Transaction) -> Void) { self.init(wrappedValue: initialValue, reset: reset) }
    public var wrappedValue: Value { phase.wrappedValue.current }
    public var projectedValue: Self { self }
    func install(in context: Context) { phase.install(in: context) }

    fileprivate func change(_ update: (inout Value, inout Transaction) -> Void) {
        var next = phase.wrappedValue
        var transaction = Transaction.current ?? Transaction()
        update(&next.current, &transaction)
        next.active = true
        withTransaction(transaction) { phase.wrappedValue = next }
    }
    fileprivate func reset() {
        let last = phase.wrappedValue
        guard last.active else { return }
        withTransaction(resetTransaction(last.current)) {
            phase.wrappedValue = Phase(initial: last.initial, current: last.initial)
        }
    }
}

extension GestureState where Value: ExpressibleByNilLiteral {
    public init(resetTransaction: Transaction = Transaction()) { self.init(wrappedValue: nil, resetTransaction: resetTransaction) }
    public init(reset: @escaping (Value, inout Transaction) -> Void) { self.init(wrappedValue: nil, reset: reset) }
}

extension Gesture {
    public func updating<State>(_ state: GestureState<State>, body: @escaping (Value, inout State, inout Transaction) -> Void) -> GestureStateGesture<Self, State> {
        GestureStateGesture(base: self, state: state, body: body)
    }
}

nonisolated public struct GestureStateGesture<Base: Gesture, State>: Gesture, NativeGesture {
    public typealias Body = Never
    public typealias Value = Base.Value
    public var base: Base
    public var state: GestureState<State>
    public var body: (Value, inout State, inout Transaction) -> Void

    public init(base: Base, state: GestureState<State>, body: @escaping (Value, inout State, inout Transaction) -> Void) {
        self.base = base
        self.state = state
        self.body = body
    }

    @MainActor func recognizer(changed: @escaping (Any) -> Void, ended: @escaping (Any) -> Void) -> Recognizer {
        var result = base.resolve(changed: { value in
            if let typed = value as? Value { state.change { body(typed, &$0, &$1) } }
            changed(value)
        }, ended: ended)
        let previous = result.reset
        result.reset = { previous?(); state.reset() }
        return result
    }
}
