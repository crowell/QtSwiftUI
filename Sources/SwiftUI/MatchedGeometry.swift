import QtBridge

@propertyWrapper public struct Namespace: MountedProperty, @unchecked Sendable {
    public struct ID: Hashable, Sendable { fileprivate let value: UUID }
    private let state = State(wrappedValue: ID(value: UUID()))
    public init() {}
    public var wrappedValue: ID { state.wrappedValue }
    func install(in context: Context) { state.install(in: context) }
}

public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let position = Self(rawValue: 1), size = Self(rawValue: 2)
    public static let frame: Self = [.position, .size]
}

@MainActor final class GeometryMatches {
    struct Key: Hashable { let namespace: Namespace.ID, id: AnyHashable }
    private typealias Pair = AnimatablePair<CGFloat, CGFloat>
    private typealias Frame = AnimatablePair<Pair, Pair>

    struct Member {
        let bounds: CGRect, anchor: UnitPoint, properties: MatchedGeometryProperties, isSource: Bool
        let animation: Animation?
        let place: (CGRect) -> Void
    }
    private var groups: [Key: [Member]] = [:]
    private var order: [Key] = []
    private var history: [Key: AnimatedValue<Frame>] = [:]

    func record(_ key: Key, _ member: Member) {
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(member)
    }

    func place(at time: TimeInterval, window: OpaquePointer) {
        var active = Set<Key>()
        // Placing a member can reveal another group inside a GeometryReader.
        while !order.isEmpty {
            let keys = order, members = groups
            order.removeAll(keepingCapacity: true)
            groups.removeAll(keepingCapacity: true)
            for key in keys {
                guard let group = members[key] else { continue }
                guard let source = group.first(where: \.isSource) else {
                    for member in group { member.place(member.bounds) }
                    continue
                }
                active.insert(key)
                let rect = source.bounds
                let target = Frame(Pair(rect.minX + rect.width * source.anchor.x, rect.minY + rect.height * source.anchor.y),
                                   Pair(rect.width, rect.height))
                let movement = history[key] ?? AnimatedValue(target)
                history[key] = movement
                movement.update(to: target, at: time, animation: source.animation)
                let value = movement.sample(at: time)
                if movement.isAnimating { qs_animation_frame(window) }
                for member in group {
                    var frame = member.bounds
                    if member.properties.contains(.size) {
                        frame.size = CGSize(width: max(0, value.second.first), height: max(0, value.second.second))
                    }
                    if member.properties.contains(.position) {
                        frame.origin = CGPoint(x: value.first.first - frame.width * member.anchor.x,
                                               y: value.first.second - frame.height * member.anchor.y)
                    }
                    member.place(frame)
                }
            }
        }
        history = history.filter { active.contains($0.key) }
    }
}

extension View {
    public func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID,
                                                    properties: MatchedGeometryProperties = .frame,
                                                    anchor: UnitPoint = .center, isSource: Bool = true) -> some View {
        Transform(content: self) { view, context in
            // Keep a widget in the normal stacking order while the drawing travels across native parents.
            let marker = context.widget(QSGroup)
            var inner = context.descending(.property("matched geometry"))
            inner.parent = marker
            let drawing = inner.widget(QSGroup)
            inner.parent = drawing
            let content = stacked(view.resolve(inner.descending(.position(0))), axis: .vertical, alignment: .center, spacing: 8)
            let effectiveAnchor = UnitPoint(x: context.environment.layoutDirection == .rightToLeft ? 1 - anchor.x : anchor.x, y: anchor.y)
            return [content.wrapping(size: content.measure) { bounds, proposal in
                qs_place(marker, bounds.minX, bounds.minY, bounds.width, bounds.height)
                let origin = qs_origin(marker)
                let global = CGRect(x: origin.width, y: origin.height, width: bounds.width, height: bounds.height)
                context.host.matches.record(.init(namespace: namespace, id: AnyHashable(id)),
                    .init(bounds: global, anchor: effectiveAnchor, properties: properties, isSource: isSource,
                          animation: context.animation) { frame in
                        qs_match_place(drawing, marker, frame.minX, frame.minY, frame.width, frame.height)
                        let offer = frame.size == bounds.size ? proposal : ProposedViewSize(frame.size)
                        content.place(CGRect(origin: .zero, size: frame.size), offer)
                        qs_group_finish_layout(drawing)
                    })
            }]
        }
    }
}
