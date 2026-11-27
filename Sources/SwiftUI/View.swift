@_exported import CoreGraphics
import QtBridge

@MainActor public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {}

@MainActor protocol Primitive: View where Body == Never {
    func elements(in context: Context) -> [Element]
}

extension View where Body == Never {
    public var body: Never { fatalError("Primitive views are rendered directly") }
}

extension View {
    func resolve(_ incoming: Context) -> [Element] {
        let context = incoming.descending(.type(ObjectIdentifier(Self.self)))
        if let entries = context.menuEntries, let item = self as? any MenuEntrySource {
            item.collect(in: context, into: entries)
            return []
        }
        if let primitive = self as? any Primitive { return primitive.elements(in: context) }
        return context.preparing(self).body.resolve(context)
    }
}

public typealias EmptyContent = EmptyView
public typealias ContentBuilder = ViewBuilder

@resultBuilder public struct ViewBuilder {
    public static func buildExpression<Content>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyContent { EmptyContent() }
    public static func buildBlock<Content>(_ content: Content) -> Content { content }
    @_disfavoredOverload public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleView<(repeat each Content)> where repeat each Content: View {
        TupleView((repeat each content))
    }
    public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleContent<repeat each Content> {
        TupleContent((repeat each content))
    }
    public static func buildIf<Content>(_ content: Content?) -> Content? { content }
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(first: first)
    }
    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> {
        .init(second: second)
    }
    public static func buildLimitedAvailability<Content>(_ content: Content) -> AnyView where Content: View { AnyView(content) }
}

public struct EmptyView: Primitive {
    public nonisolated init() {}
    func elements(in context: Context) -> [Element] { [] }
}

@MainActor protocol TupleViewChildren {
    func forEachChild(_ visit: (Int, any View) -> Void)
}

extension TupleViewChildren {
    func elements(in context: Context) -> [Element] {
        var result: [Element] = []
        forEachChild { index, view in
            result += view.resolve(context.descending(.position(index)).preferenceBranch())
        }
        return result
    }

    func subviews(in context: Context) -> [Subview] {
        var result: [Subview] = []
        forEachChild { index, view in
            result += view.collectSubviews(in: context.descending(.position(index)))
        }
        return result
    }
}

public nonisolated struct TupleView<T>: Primitive, SubviewSource, TupleViewChildren {
    public var value: T
    public init(_ value: T) { self.value = value }
    @MainActor func forEachChild(_ visit: (Int, any View) -> Void) {
        for (index, child) in Mirror(reflecting: value).children.enumerated() {
            if let view = child.value as? any View { visit(index, view) }
        }
    }
}
public struct TupleContent<each Content> {
    public var content: (repeat each Content)
    public init(_ content: (repeat each Content)) { self.content = content }
    @_disfavoredOverload public init(_ content: repeat each Content) { self.init((repeat each content)) }
    public var body: Never { fatalError("TupleContent is rendered directly") }
}
extension TupleContent: Sendable where repeat each Content: Sendable {}
extension TupleContent: View, Primitive, SubviewSource, TupleViewChildren where repeat each Content: View {
    @MainActor func forEachChild(_ visit: (Int, any View) -> Void) {
        var index = 0
        for view in repeat each content {
            visit(index, view)
            index += 1
        }
    }
}

public nonisolated struct _ConditionalContent<TrueContent, FalseContent> {
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    init(first: TrueContent) { storage = .first(first) }
    init(second: FalseContent) { storage = .second(second) }
}
extension _ConditionalContent: View, Primitive, SubviewSource where TrueContent: View, FalseContent: View {
    @MainActor func subviews(in context: Context) -> [Subview] {
        switch storage {
        case .first(let view): view.collectSubviews(in: context.descending(.position(0)))
        case .second(let view): view.collectSubviews(in: context.descending(.position(1)))
        }
    }
    @MainActor func elements(in context: Context) -> [Element] {
        switch storage {
        case .first(let view): view.resolve(context.descending(.position(0)))
        case .second(let view): view.resolve(context.descending(.position(1)))
        }
    }
}
extension Optional: View, Primitive where Wrapped: View {
    func elements(in context: Context) -> [Element] { self?.resolve(context) ?? [] }
}
public nonisolated struct AnyView: Primitive, SubviewSource {
    @MainActor func subviews(in context: Context) -> [Subview] { content.collectSubviews(in: context) }
    let content: any View
    public init<V: View>(_ view: V) { content = view }
    @MainActor func elements(in context: Context) -> [Element] { content.resolve(context) }
}
public nonisolated struct Group<Content: View>: Primitive {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    @MainActor func elements(in context: Context) -> [Element] { content.resolve(context) }
}
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: Primitive {
    public var data: Data
    public var content: (Data.Element) -> Content
    let key: KeyPath<Data.Element, ID>
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        key = id
    }
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.init(data, id: \.id, content: content)
    }
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) where Data == Range<Int>, ID == Int {
        self.init(data, id: \.self, content: content)
    }
    func elements(in context: Context) -> [Element] {
        data.flatMap { item in
            let id = AnyHashable(item[keyPath: key])
            let inner = context.descending(.id(id)).preferenceBranch()
            return inner.identified(content(item).resolve(inner), by: id)
        }
    }
}
