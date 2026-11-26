import Observation

@dynamicMemberLookup @propertyWrapper public struct Bindable<Value> where Value: AnyObject, Value: Observable {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(_ wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var projectedValue: Self { self }
    public subscript<Member>(dynamicMember path: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        Binding(get: { wrappedValue[keyPath: path] }, set: { wrappedValue[keyPath: path] = $0 })
    }
}
extension View {
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        Transform(content: self) { view, ctx in
            var ctx = ctx
            ctx.environment.objects[ObjectIdentifier(T.self)] = object
            return view.resolve(ctx)
        }
    }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        Transform(content: self) { view, ctx in
            ctx.host.lifetime(at: ctx.path, appear: { action?() }, disappear: {})
            return view.resolve(ctx)
        }
    }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        Transform(content: self) { view, ctx in
            ctx.host.lifetime(at: ctx.path, appear: {}, disappear: { action?() })
            return view.resolve(ctx)
        }
    }
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @MainActor () async -> Void) -> some View {
        task(id: false, priority: priority, action)
    }
    public func task<ID: Equatable>(id: ID, priority: TaskPriority = .userInitiated,
                                    _ action: @escaping @MainActor () async -> Void) -> some View {
        ViewTask(content: self, id: id, priority: priority, action: action)
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        ChangeObserver(content: self, value: value, initial: initial, action: action)
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
        onChange(of: value, initial: initial) { _, _ in action() }
    }
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        onChange(of: value) { _, next in action(next) }
    }
}
@MainActor private final class TaskSlot<ID> {
    var id: ID
    var task: Task<Void, Never>?
    init(_ id: ID) { self.id = id }
}
private struct ViewTask<Content: View, ID: Equatable>: Primitive {
    let content: Content, id: ID, priority: TaskPriority
    let action: @MainActor () async -> Void
    func elements(in ctx: Context) -> [Element] {
        guard !ctx.host.isMeasuringAlternative else { return content.resolve(ctx) }
        let slot = ctx.host.storage[ctx.path] as? TaskSlot<ID> ?? TaskSlot(id)
        ctx.host.liveStorage.insert(ctx.path)
        ctx.host.storage[ctx.path] = slot
        func start() { slot.task = Task(priority: priority) { await action() } }
        if slot.id != id {
            slot.id = id
            slot.task?.cancel()
            start()
        }
        ctx.host.lifetime(at: ctx.path, appear: start, disappear: { slot.task?.cancel() })
        return content.resolve(ctx)
    }
}
@MainActor private final class Previous<V> {
    var value: V
    init(_ value: V) { self.value = value }
}
private struct ChangeObserver<Content: View, Value: Equatable>: Primitive {
    let content: Content, value: Value, initial: Bool, action: (Value, Value) -> Void
    func elements(in ctx: Context) -> [Element] {
        guard !ctx.host.isMeasuringAlternative else { return content.resolve(ctx) }
        ctx.host.liveStorage.insert(ctx.path)
        if let previous = ctx.host.storage[ctx.path] as? Previous<Value> {
            let old = previous.value
            if old != value {
                previous.value = value
                action(old, value)
            }
        } else {
            ctx.host.storage[ctx.path] = Previous(value)
            if initial { action(value, value) }
        }
        return content.resolve(ctx)
    }
}
