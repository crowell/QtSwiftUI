import QtBridge

public struct FocusInteractions: OptionSet, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let activate = Self(rawValue: 1), edit = Self(rawValue: 2)
    public static var automatic: Self { [.activate, .edit] }
}

struct FocusLink {
    var active: () -> Bool
    var change: (Bool) -> Void
}
@propertyWrapper public struct FocusState<Value: Hashable>: MountedProperty {
    @propertyWrapper public struct Binding {
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
    public func focusable(_ isFocusable: Bool = true) -> some View { focusable(isFocusable, interactions: .automatic) }
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            let elements = ctx.children(of: view, inside: group)
            qs_group_focus(group, isFocusable ? 1 : 0, Int32(truncatingIfNeeded: interactions.rawValue))
            if let focus = ctx.environment.focus { qs_focus(group, focus.active() ? 1 : 0) }
            return elements
        }
    }
    public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.isFocusEffectEnabled, ctx.environment.isFocusEffectEnabled && !disabled))
        }
    }
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
