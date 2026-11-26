public enum CoordinateSpace: Hashable {
    case local, global, named(AnyHashable)
    public var isLocal: Bool { self == .local }
    public var isGlobal: Bool { self == .global }
}

public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .global }
}
public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .local }
}
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    let name: AnyHashable
    public var coordinateSpace: CoordinateSpace { .named(name) }
}
extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace { .init() }
}
extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace { .init() }
}
extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace { .init(name: AnyHashable(name)) }
    public static var scrollView: NamedCoordinateSpace { .named(ScrollSpace.nearest) }
    public static func scrollView(axis: Axis) -> Self { .named(ScrollSpace.axis(axis)) }
}

enum ScrollSpace: Hashable {
    case nearest, axis(Axis)
}
