public protocol ContainerValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct ContainerValues {
    private var storage: [ObjectIdentifier: Any] = [:]
    public subscript<Key: ContainerValueKey>(key: Key.Type) -> Key.Value {
        get { (storage[ObjectIdentifier(key)] as? Key.Value) ?? Key.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue as Any }
    }
}

@MainActor protocol SubviewSource {
    func subviews(in context: Context) -> [Subview]
}

extension View {
    func collectSubviews(in incoming: Context) -> [Subview] {
        let context = incoming.descending(.type(ObjectIdentifier(Self.self)))
        if let source = self as? any SubviewSource { return source.subviews(in: context) }
        if let primitive = self as? any Primitive {
            return [Subview(id: .init(path: context.path), render: { primitive.elements(in: $0) })]
        }
        return context.preparing(self).body.collectSubviews(in: context)
    }
}

private struct RenderLeaf: Primitive {
    let render: (Context) -> [Element]
    func elements(in context: Context) -> [Element] { render(context) }
}

nonisolated public struct Subview: Primitive, Identifiable {
    public struct ID: Hashable { fileprivate var path: [Part] }
    public let id: ID
    public internal(set) var containerValues = ContainerValues()
    fileprivate var render: @MainActor (Context) -> [Element]

    @MainActor func elements(in context: Context) -> [Element] {
        render(context.descending(.id(AnyHashable(id))))
    }
    @MainActor func applying(_ transform: @escaping (any View, Context) -> [Element]) -> Self {
        var result = self
        result.render = { context in transform(RenderLeaf(render: render), context) }
        return result
    }
}

nonisolated public struct SubviewsCollection: RandomAccessCollection, Primitive {
    fileprivate let items: [Subview]
    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public func index(before i: Int) -> Int { i - 1 }
    public func index(after i: Int) -> Int { i + 1 }
    public subscript(index: Int) -> Subview { items[index] }
    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice { .init(items: items[bounds]) }
    @MainActor func elements(in context: Context) -> [SwiftUI.Element] { self[startIndex..<endIndex].elements(in: context) }
}

nonisolated public struct SubviewsCollectionSlice: RandomAccessCollection, Primitive {
    fileprivate let items: ArraySlice<Subview>
    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public func index(before i: Int) -> Int { i - 1 }
    public func index(after i: Int) -> Int { i + 1 }
    public subscript(index: Int) -> Subview { items[index] }
    public subscript(bounds: Range<Int>) -> Self { .init(items: items[bounds]) }
    @MainActor func elements(in context: Context) -> [SwiftUI.Element] { items.flatMap { $0.elements(in: context.preferenceBranch()) } }
}

public struct GroupElementsOfContent<Subviews: View, Content: View>: Primitive {
    let base: Subviews
    let transform: (SubviewsCollection) -> Content
    func elements(in context: Context) -> [Element] {
        let items = base.collectSubviews(in: context).map { child in
            child.applying { view, destination in
                var source = destination
                source.environment = context.environment
                return view.resolve(source)
            }
        }
        return transform(.init(items: items)).resolve(context)
    }
}

extension Group {
    public init<Base: View, Result: View>(subviews view: Base, @ViewBuilder transform: @escaping (SubviewsCollection) -> Result)
        where Content == GroupElementsOfContent<Base, Result> {
        content = .init(base: view, transform: transform)
    }
}

private struct ContainerValueWriter<Content: View>: Primitive, SubviewSource {
    let content: Content
    let write: (inout ContainerValues) -> Void
    func elements(in context: Context) -> [Element] { content.resolve(context) }
    func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { child in
            var result = child
            write(&result.containerValues)
            return result
        }
    }
}

extension View {
    public func containerValue<V>(_ keyPath: WritableKeyPath<ContainerValues, V>, _ value: V) -> some View {
        ContainerValueWriter(content: self) { $0[keyPath: keyPath] = value }
    }
}

extension EmptyView: SubviewSource {
    func subviews(in context: Context) -> [Subview] { [] }
}
extension Group: SubviewSource {
    func subviews(in context: Context) -> [Subview] { content.collectSubviews(in: context) }
}
extension TupleView: SubviewSource {
    func subviews(in context: Context) -> [Subview] {
        Mirror(reflecting: value).children.enumerated().flatMap { index, child in
            (child.value as? any View)?.collectSubviews(in: context.descending(.position(index))) ?? []
        }
    }
}
extension Optional: SubviewSource where Wrapped: View {
    func subviews(in context: Context) -> [Subview] { self?.collectSubviews(in: context) ?? [] }
}
extension ForEach: SubviewSource {
    func subviews(in context: Context) -> [Subview] {
        data.flatMap { item in content(item).collectSubviews(in: context.descending(.id(AnyHashable(item[keyPath: key])))) }
    }
}
