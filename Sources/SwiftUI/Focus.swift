struct FocusLink {
    var active: () -> Bool
    var change: (Bool) -> Void
}
@propertyWrapper @MainActor public struct FocusState<Value: Hashable>: MountedProperty {
    @propertyWrapper @MainActor public struct Binding {
        fileprivate let state: State<Value>
        public var wrappedValue: Value {
            get { state.wrappedValue }
            nonmutating set { state.wrappedValue = newValue }
        }
        public var projectedValue: Self { self }
    }
    private let state: State<Value>
    public init() where Value == Bool { state = State(wrappedValue: false) }
    public init<T>() where Value == T?, T: Hashable { state = State(wrappedValue: nil) }
    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    public var projectedValue: Binding { Binding(state: state) }
    func install(in context: Context) { state.install(in: context) }
}
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let text = Self(rawValue: 1), search = Self(rawValue: 2)
}
extension View {
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        environment(\.focus, FocusLink(active: { condition.wrappedValue }, change: {
            if condition.wrappedValue != $0 { condition.wrappedValue = $0 }
        }))
    }
    public func focused<T>(_ binding: FocusState<T?>.Binding, equals value: T) -> some View {
        environment(\.focus, FocusLink(active: { binding.wrappedValue == value }, change: { active in
            if active && binding.wrappedValue != value { binding.wrappedValue = value }
            if !active && binding.wrappedValue == value { binding.wrappedValue = nil }
        }))
    }
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        Transform(content: self) { view, context in
            guard triggers.contains(.text) else { return view.resolve(context) }
            let parent = context.environment.submit
            return view.resolve(context.with(\.submit, { parent?(); action() }))
        }
    }
}
