import Combine
import Foundation

@frozen public nonisolated struct SubscriptionView<PublisherType: Publisher, Content: View>: Primitive where PublisherType.Failure == Never {
    public typealias Body = Never
    public var content: Content
    public var publisher: PublisherType
    public var action: (PublisherType.Output) -> Void

    nonisolated public init(content: Content, publisher: PublisherType, action: @escaping (PublisherType.Output) -> Void) {
        self.content = content
        self.publisher = publisher
        self.action = action
    }

    @MainActor func elements(in context: Context) -> [Element] {
        let elements = content.resolve(context)
        if !context.host.isMeasuringAlternative {
            context.host.subscriptions.stage(self, at: context.path)
        }
        return elements
    }
}

extension View {
    nonisolated public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View where P.Failure == Never {
        SubscriptionView(content: self, publisher: publisher, action: action)
    }
}

@MainActor final class ViewSubscriptions {
    private var active: [[Part]: AnyObject] = [:]
    private var pending: [[Part]: () -> Void] = [:]
    private var order: [[Part]] = []

    func stage<P, Content>(_ view: SubscriptionView<P, Content>, at path: [Part]) {
        if pending[path] == nil { order.append(path) }
        let slot = active[path] as? SubscriptionSlot<P> ?? SubscriptionSlot<P>()
        active[path] = slot
        pending[path] = { slot.update(view.publisher, action: view.action) }
    }

    func commit() {
        active = active.filter { pending[$0.key] != nil }
        let updates = order.compactMap { pending[$0] }
        order.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        for update in updates { update() }
    }

    func close() {
        order.removeAll()
        pending.removeAll()
        active.removeAll()
    }
}

// Combine permits non-Sendable outputs. Deliver each received value to the
// view's main actor without imposing another constraint on the public API.
private struct Received<Output>: @unchecked Sendable {
    let value: Output
}

@MainActor private final class SubscriptionSlot<P: Publisher> where P.Failure == Never {
    private var publisher: P?
    private var action: ((P.Output) -> Void)?
    private var cancellable: AnyCancellable?
    private var generation = 0
    private var completed = false

    func update(_ next: P, action: @escaping (P.Output) -> Void) {
        self.action = action
        if let publisher, !completed && samePublisherValue(publisher, next) { return }
        generation += 1
        cancellable?.cancel()
        publisher = next
        completed = false
        let generation = generation
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.generation == generation else { return }
            self.completed = true
        }
        let receive: @MainActor @Sendable (Received<P.Output>) -> Void = { [weak self] received in
            guard let self, self.generation == generation else { return }
            self.action?(received.value)
        }
        cancellable = next.sink(receiveCompletion: { @Sendable _ in
            deliverPublisherEvent(finish)
        }, receiveValue: { @Sendable output in
            let received = Received(value: output)
            deliverPublisherEvent { receive(received) }
        })
    }

}

private func deliverPublisherEvent(_ work: @escaping @Sendable @MainActor () -> Void) {
    if Thread.isMainThread { MainActor.assumeIsolated(work) }
    else { DispatchQueue.main.async(execute: work) }
}

private func samePublisherValue(_ lhs: Any, _ rhs: Any) -> Bool {
    guard type(of: lhs) == type(of: rhs) else { return false }
    if let value = lhs as? any Equatable {
        func equals<T: Equatable>(_ value: T) -> Bool { (rhs as? T) == value }
        return equals(value)
    }
    if type(of: lhs) is AnyClass { return (lhs as AnyObject) === (rhs as AnyObject) }
    let left = Mirror(reflecting: lhs), right = Mirror(reflecting: rhs)
    switch left.displayStyle {
    case .struct, .tuple, .optional:
        return left.children.count == right.children.count &&
            zip(left.children, right.children).allSatisfy { samePublisherValue($0.0.value, $0.1.value) }
    default:
        return false
    }
}
