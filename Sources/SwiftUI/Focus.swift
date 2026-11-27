import QtBridge

public struct FocusInteractions: OptionSet, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let activate = Self(rawValue: 1), edit = Self(rawValue: 2)
    public static var automatic: Self { [.activate, .edit] }
}

struct FocusLink {
    var target: FocusTarget
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
        func target(for value: Value) -> FocusTarget { FocusTarget(state: state.identity, value: AnyHashable(value)) }
    }
    private var state: State<Value>
    public init() where Value == Bool { state = State(wrappedValue: false) }
    public init<T>() where Value == T?, T: Hashable { state = State(wrappedValue: nil) }
    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    public var projectedValue: Binding { Binding(state: state) }
    mutating func install(in context: Context) { state.install(in: context) }
}
public struct SubmitTriggers: OptionSet, Sendable {
    public typealias RawValue = Int
    public typealias Element = SubmitTriggers
    public typealias ArrayLiteralElement = SubmitTriggers
    public let rawValue: RawValue
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    public static let text = Self(rawValue: 1), search = Self(rawValue: 4)
}

public struct SubmitLabel: Sendable {
    let key: QSEnterKey
    public static var done: SubmitLabel { Self(key: QSEnterDone) }
    public static var go: SubmitLabel { Self(key: QSEnterGo) }
    public static var send: SubmitLabel { Self(key: QSEnterSend) }
    public static var join: SubmitLabel { Self(key: QSEnterGo) }
    public static var route: SubmitLabel { Self(key: QSEnterGo) }
    public static var search: SubmitLabel { Self(key: QSEnterSearch) }
    public static var `return`: SubmitLabel { Self(key: QSEnterReturn) }
    public static var next: SubmitLabel { Self(key: QSEnterNext) }
    public static var `continue`: SubmitLabel { Self(key: QSEnterNext) }
}
extension View {
    public func focusable(_ isFocusable: Bool = true) -> some View { focusable(isFocusable, interactions: .automatic) }
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            let elements = ctx.children(of: view, inside: group)
            qs_group_focus(group, isFocusable ? 1 : 0, Int32(truncatingIfNeeded: interactions.rawValue))
            return elements
        }
    }
    public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.isFocusEffectEnabled, ctx.environment.isFocusEffectEnabled && !disabled))
        }
    }
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        environment(\.focus, FocusLink(target: condition.target(for: true), active: { condition.wrappedValue }, change: {
            if condition.wrappedValue != $0 { condition.wrappedValue = $0 }
        }))
    }
    public func focused<T>(_ binding: FocusState<T?>.Binding, equals value: T) -> some View {
        environment(\.focus, FocusLink(target: binding.target(for: value), active: { binding.wrappedValue == value }, change: { active in
            if active && binding.wrappedValue != value { binding.wrappedValue = value }
            if !active && binding.wrappedValue == value { binding.wrappedValue = nil }
        }))
    }
    nonisolated public func submitScope(_ isBlocking: Bool = true) -> some View {
        let apply: @MainActor (Context) -> Context = { isBlocking ? $0.with(\.submit, nil) : $0 }
        return Transform(content: self, readingContext: apply) { $0.resolve(apply($1)) }
    }
    nonisolated public func submitLabel(_ submitLabel: SubmitLabel) -> some View {
        environment(\.submitLabel, submitLabel)
    }
    nonisolated public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        SubmitHandler(content: self, triggers: triggers, action: action)
    }
}

private nonisolated struct SubmitHandler<Content: View>: Primitive, SubviewSource {
    let content: Content
    let triggers: SubmitTriggers
    let action: () -> Void

    @MainActor func scoped(_ context: Context) -> Context {
        let parent = context.environment.submit
        return context.with(\.submit, { trigger in
            guard !triggers.intersection(trigger).isEmpty else { return }
            parent?(trigger)
            action()
        })
    }

    @MainActor func elements(in context: Context) -> [Element] { content.resolve(scoped(context)) }
    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: scoped(context)).map { child in
            child.applying { view, destination in view.resolve(scoped(destination)) }
        }
    }
}
