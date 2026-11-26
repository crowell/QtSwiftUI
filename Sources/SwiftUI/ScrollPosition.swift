public struct ScrollPosition: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        case unspecified, user, edge(Edge), point(CGPoint), x(CGFloat), y(CGFloat)
        case id(any Hashable & Sendable, UnitPoint?)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.unspecified, .unspecified), (.user, .user): true
            case let (.edge(a), .edge(b)): a == b
            case let (.point(a), .point(b)): a == b
            case let (.x(a), .x(b)), let (.y(a), .y(b)): a == b
            case let (.id(a, aa), .id(b, ba)): AnyHashable(a) == AnyHashable(b) && aa == ba
            default: false
            }
        }
    }

    private let type: ObjectIdentifier
    private let matchID: @Sendable (AnyHashable) -> (any Hashable & Sendable)?
    private var visibleID: (any Hashable & Sendable)?
    private(set) var destination: Destination
    private var revision: UInt = 0

    public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        self.init(idType: Swift.type(of: id))
        destination = .id(id, anchor)
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        type = ObjectIdentifier(idType)
        func matcher<T: Hashable & Sendable>(_: T.Type) -> @Sendable (AnyHashable) -> (any Hashable & Sendable)? {
            { $0.base as? T }
        }
        matchID = matcher(idType)
        destination = .unspecified
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
        self.init(idType: idType)
        destination = .edge(edge)
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self, point: CGPoint) {
        self.init(idType: idType)
        destination = .point(point)
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat, y: CGFloat) {
        self.init(idType: idType, point: CGPoint(x: x, y: y))
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat) {
        self.init(idType: idType)
        destination = .x(x)
    }
    public init(idType: (some Hashable & Sendable).Type = Never.self, y: CGFloat) {
        self.init(idType: idType)
        destination = .y(y)
    }

    private mutating func set(_ value: Destination) {
        destination = value
        visibleID = nil
        revision &+= 1
    }
    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) { set(.id(id, anchor)) }
    public mutating func scrollTo(edge: Edge) { set(.edge(edge)) }
    public mutating func scrollTo(point: CGPoint) { set(.point(point)) }
    public mutating func scrollTo(x: CGFloat, y: CGFloat) { set(.point(CGPoint(x: x, y: y))) }
    public mutating func scrollTo(x: CGFloat) { set(.x(x)) }
    public mutating func scrollTo(y: CGFloat) { set(.y(y)) }
    public var isPositionedByUser: Bool {
        get { destination == .user }
        set { if newValue { destination = .user } }
    }
    public var edge: Edge? { if case .edge(let edge) = destination { edge } else { nil } }
    public var point: CGPoint? { if case .point(let point) = destination { point } else { nil } }
    public var x: CGFloat? { if case .x(let x) = destination { x } else { nil } }
    public var y: CGFloat? { if case .y(let y) = destination { y } else { nil } }
    public var viewID: (any Hashable & Sendable)? { if case .id(let id, _) = destination { id } else { visibleID } }
    func accepts(_ id: AnyHashable) -> Bool { matchID(id) != nil }
    mutating func userScrolled(to id: AnyHashable?) {
        destination = .user
        visibleID = id.flatMap(matchID)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.revision == rhs.revision && lhs.destination == rhs.destination &&
            lhs.visibleID.map { AnyHashable($0) } == rhs.visibleID.map { AnyHashable($0) }
    }
    public func viewID<T>(type: T.Type) -> T? where T: Hashable & Sendable { viewID as? T }
}

public struct ScrollAnchorRole: Hashable, Sendable {
    private enum Role { case initialOffset, sizeChanges, alignment }
    private let role: Role
    public static var initialOffset: Self { Self(role: .initialOffset) }
    public static var sizeChanges: Self { Self(role: .sizeChanges) }
    public static var alignment: Self { Self(role: .alignment) }
}
