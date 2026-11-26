/// The context SwiftUI associates with a synchronous change to view state.
public struct Transaction {
    public var animation: Animation?
    public var disablesAnimations = false
    public var isContinuous = false
    public init() {}
    public init(animation: Animation?) { self.animation = animation }

    private static let threadKey = "org.qtswiftui.current-transaction"
    private final class Scope {
        let transaction: Transaction
        init(_ transaction: Transaction) { self.transaction = transaction }
    }
    static var current: Transaction? { (Thread.current.threadDictionary[threadKey] as? Scope)?.transaction }
    static func perform<Result>(_ value: Self, _ body: () throws -> Result) rethrows -> Result {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[threadKey]
        dictionary[threadKey] = Scope(value)
        defer { dictionary[threadKey] = previous }
        return try body()
    }
}

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    try Transaction.perform(transaction, body)
}

public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    var transaction = Transaction.current ?? Transaction()
    transaction.animation = animation
    return try withTransaction(transaction, body)
}

extension View {
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        Transform(content: self) { view, ctx in
            var inner = ctx
            transform(&inner.transaction)
            return view.resolve(inner)
        }
    }
}

extension Binding {
    public func transaction(_ transaction: Transaction) -> Self {
        var copy = self
        copy.transaction = transaction
        return copy
    }
    public func animation(_ animation: Animation? = .default) -> Self {
        var transaction = self.transaction
        transaction.animation = animation
        return self.transaction(transaction)
    }
}

extension Binding: @unchecked Sendable where Value: Sendable {}
