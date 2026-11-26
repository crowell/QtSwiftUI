import Observation
import Synchronization

private final class BodyObservation: Sendable {
    private let invalidated = Mutex(false)
    var changed: Bool { invalidated.withLock { $0 } }
    func invalidate() { invalidated.withLock { $0 = true } }
}

@MainActor private final class EquatableBody<Content: View & Equatable> {
    let content: Content
    let body: Content.Body
    let observation = BodyObservation()

    init(_ content: Content, context: Context) {
        self.content = content
        let observation = observation
        let host = context.host
        body = withObservationTracking {
            context.preparing(content).body
        } onChange: { [weak host, weak observation] in
            guard let observation else { return }
            observation.invalidate()
            let transaction = Transaction.current
            Task { @MainActor in host?.update(transaction: transaction) }
        }
    }
}

public nonisolated struct EquatableView<Content: Equatable & View>: Primitive {
    public var content: Content
    public init(content: Content) { self.content = content }

    @MainActor func elements(in context: Context) -> [Element] {
        // Primitive widgets still need placement and event registration each pass.
        // Dynamic properties install fresh environment values and bindings here.
        if content is any Primitive || Mirror(reflecting: content).children.contains(where: { $0.value is any DynamicProperty }) {
            return content.resolve(context)
        }
        let child = context.descending(.type(ObjectIdentifier(Content.self)))
        let path = child.path
        let cache: EquatableBody<Content>
        if let previous = context.host.storage[path] as? EquatableBody<Content>,
           !previous.observation.changed, previous.content == content {
            cache = previous
        } else {
            cache = EquatableBody(content, context: child)
            if !context.host.isMeasuringAlternative { context.host.storage[path] = cache }
        }
        if !context.host.isMeasuringAlternative { context.host.liveStorage.insert(path) }
        return cache.body.resolve(child)
    }
}

extension View where Self: Equatable {
    nonisolated public func equatable() -> EquatableView<Self> { EquatableView(content: self) }
}
