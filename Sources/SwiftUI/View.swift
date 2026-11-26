@_exported import CoreGraphics
import QtBridge

@MainActor public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Never { self }
}

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

public typealias ContentBuilder = ViewBuilder

@resultBuilder public enum ViewBuilder {
    public static func buildExpression<V: View>(_ v: V) -> V { v }
    @MainActor public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<V: View>(_ v: V) -> V { v }
    @MainActor public static func buildBlock<each V: View>(_ v: repeat each V) -> TupleView<(repeat each V)> {
        TupleView((repeat each v))
    }
    public static func buildIf<V: View>(_ v: V?) -> V? { v }
    @MainActor public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { .init(first: first) }
    @MainActor public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { .init(second: second) }
    @MainActor public static func buildLimitedAvailability<V: View>(_ v: V) -> AnyView { AnyView(v) }
}

public struct EmptyView: Primitive {
    public nonisolated init() {}
    func elements(in context: Context) -> [Element] { [] }
}
public struct TupleView<T>: Primitive {
    public var value: T
    public init(_ value: T) { self.value = value }
    func elements(in context: Context) -> [Element] {
        Mirror(reflecting: value).children.enumerated().flatMap { index, child in
            (child.value as? any View)?.resolve(context.descending(.position(index)).preferenceBranch()) ?? []
        }
    }
}
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: Primitive, SubviewSource {
    func subviews(in context: Context) -> [Subview] {
        switch storage {
        case .first(let view): view.collectSubviews(in: context.descending(.position(0)))
        case .second(let view): view.collectSubviews(in: context.descending(.position(1)))
        }
    }
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    init(first: TrueContent) { storage = .first(first) }
    init(second: FalseContent) { storage = .second(second) }
    func elements(in context: Context) -> [Element] {
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
public struct Group<Content: View>: Primitive {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    func elements(in context: Context) -> [Element] { content.resolve(context) }
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
        data.flatMap { item in content(item).resolve(context.descending(.id(AnyHashable(item[keyPath: key]))).preferenceBranch()) }
    }
}
