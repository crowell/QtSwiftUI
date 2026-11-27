import QtBridge

public struct FocusInteractions: OptionSet, Sendable {
    public typealias ArrayLiteralElement = FocusInteractions
    public typealias Element = FocusInteractions
    public typealias RawValue = Int
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
        fileprivate let resetValue: Value
        public var wrappedValue: Value {
            get { state.wrappedValue }
            nonmutating set { state.wrappedValue = newValue }
        }
        public var projectedValue: Self { self }
        func target(for value: Value) -> FocusTarget { FocusTarget(state: state.identity, value: AnyHashable(value)) }
    }
    private var state: State<Value>
    private let resetValue: Value
    public init() where Value == Bool {
        resetValue = false
        state = State(wrappedValue: false)
    }
    public init<T>() where Value == T?, T: Hashable {
        resetValue = nil
        state = State(wrappedValue: nil)
    }
    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    public var projectedValue: Binding { Binding(state: state, resetValue: resetValue) }
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
    nonisolated public func focusable(_ isFocusable: Bool = true) -> some View {
        focusable(isFocusable, interactions: .automatic)
    }

    nonisolated public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        Focusable(content: self, enabled: isFocusable, interactions: interactions, change: nil)
    }

    nonisolated public func focusable(_ isFocusable: Bool = true, onFocusChange: @escaping (_ isFocused: Bool) -> Void = { _ in }) -> some View {
        Focusable(content: self, enabled: isFocusable, interactions: .automatic, change: onFocusChange)
    }
    nonisolated public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.isFocusEffectEnabled, ctx.environment.isFocusEffectEnabled && !disabled))
        }
    }
    nonisolated public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        focused(condition, equals: true)
    }
    nonisolated public func focused<Value>(_ binding: FocusState<Value>.Binding, equals value: Value) -> some View where Value: Hashable {
        environment(\.focus, FocusLink(target: binding.target(for: value), active: { binding.wrappedValue == value }, change: { active in
            if active && binding.wrappedValue != value { binding.wrappedValue = value }
            if !active && binding.wrappedValue == value && value != binding.resetValue { binding.wrappedValue = binding.resetValue }
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

extension View {
    func resolveFocusChildren(in incoming: Context, focused: Bool) -> [Element] {
        if self is any Primitive { return resolve(incoming.with(\.isFocused, focused)) }
        let context = incoming.descending(.type(ObjectIdentifier(Self.self)))
        // The view declaring the focus target still reads its own ancestor.
        // Its body supplies the environment for the target’s children.
        return context.preparing(self).body.resolve(context.with(\.isFocused, focused))
    }
}

private nonisolated struct Focusable<Content: View>: Primitive, SubviewSource {
    let content: Content
    let enabled: Bool
    let interactions: FocusInteractions
    let change: ((Bool) -> Void)?

    @MainActor func elements(in context: Context) -> [Element] { wrap(content, in: context) }
    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { $0.applying { view, destination in wrap(view, in: destination) } }
    }
    @MainActor private func wrap(_ view: any View, in context: Context) -> [Element] {
        let group = context.widget(QSGroup, focusChanged: change)
        let acceptsFocus = enabled && !interactions.isEmpty
        let children = acceptsFocus ? context.with(\.focus, nil) : context
        let elements = children.children(of: view, inside: group,
                                         focusForDescendants: acceptsFocus ? qs_widget_has_focus(group) != 0 : nil)
        qs_group_focus(group, enabled ? 1 : 0, Int32(truncatingIfNeeded: interactions.rawValue))
        return elements
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
