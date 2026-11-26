import QtBridge

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = Self(rawValue: 1)
    public static let keyboard = Self(rawValue: 2)
    public static let all = Self(rawValue: .max)
}

public struct GeometryProxy {
    public let size: CGSize
    let globalOrigin: CGPoint
    let origins: [AnyHashable: CGPoint]
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect { frame(in: coordinateSpace.coordinateSpace) }
    @_disfavoredOverload public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        switch coordinateSpace {
        case .local: return CGRect(origin: .zero, size: size)
        case .global: return CGRect(origin: globalOrigin, size: size)
        case .named(let name):
            let origin = origins[name] ?? .zero
            return CGRect(x: globalOrigin.x - origin.x, y: globalOrigin.y - origin.y, width: size.width, height: size.height)
        }
    }
}
extension Context {
    func geometry(in bounds: CGRect) -> GeometryProxy {
        let offset = windowOffset
        return GeometryProxy(size: bounds.size, globalOrigin: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                             origins: spaces.mapValues(\.point))
    }
}
public struct GeometryReader<Content: View>: Primitive {
    let content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    func elements(in context: Context) -> [Element] {
        [Element { $0.replacingUnspecifiedDimensions() } place: { bounds, _ in
            let proxy = context.geometry(in: bounds)
            let proposal = ProposedViewSize(bounds.size)
            for child in content(proxy).resolve(context) {
                child.place(CGRect(origin: bounds.origin, size: child.measure(proposal)), proposal)
            }
        }]
    }
}
@MainActor final class NamedOrigin { var point: CGPoint = .zero }
@MainActor private final class GeometrySample<Value> { var value: Value? }

private struct GeometryObserver<Content: View, Value: Equatable & Sendable>: Primitive {
    let content: Content
    let project: @Sendable (GeometryProxy) -> Value
    let change: (Value, Value) -> Void

    func elements(in context: Context) -> [Element] {
        content.resolve(context).enumerated().map { index, child in
            let path = context.path + [.property("geometry change"), .position(index)]
            let sample = context.host.storage[path] as? GeometrySample<Value> ?? GeometrySample<Value>()
            context.host.storage[path] = sample
            context.host.liveStorage.insert(path)
            let element = child.wrapping(size: child.measure) { bounds, proposal in
                child.place(bounds, proposal)
                let value = project(context.geometry(in: bounds))
                let previous = sample.value
                if previous != .some(value) {
                    sample.value = value
                    context.host.afterLayout { change(previous ?? value, value) }
                }
            }
            return element
        }
    }
}
extension View {
    public func onGeometryChange<T: Equatable & Sendable>(for type: T.Type, of transform: @escaping @Sendable (GeometryProxy) -> T,
                                                         action: @escaping (_ newValue: T) -> Void) -> some View {
        GeometryObserver(content: self, project: transform) { _, next in action(next) }
    }
    public func onGeometryChange<T: Equatable & Sendable>(for type: T.Type, of transform: @escaping @Sendable (GeometryProxy) -> T,
                                                         action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        GeometryObserver(content: self, project: transform, change: action)
    }
    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View { coordinateSpace(name: name.name) }
    public func coordinateSpace<T: Hashable>(name: T) -> some View {
        Transform(content: self) { view, context in
            let origin = NamedOrigin()
            var inner = context
            inner.spaces[AnyHashable(name)] = origin
            return view.resolve(inner).map { child in
                child.wrapping(size: child.measure) { bounds, proposal in
                    let offset = context.windowOffset
                    origin.point = CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y)
                    child.place(bounds, proposal)
                }
            }
        }
    }
    // The desktop host lays out its content entirely inside the window decorations.
    // Its container and keyboard safe-area insets are both zero.
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }

    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            return ctx.children(of: view, inside: group) { size in
                shape.path(in: CGRect(origin: .zero, size: size)).withNativePath {
                    qs_group_clip(group, $0, style.isEOFilled ? 1 : 0, style.isAntialiased ? 1 : 0)
                }
            }
        }
    }
    public func clipped(antialiased: Bool = false) -> some View {
        Transform(content: self) { view, context in
            let container = context.widget(QSGroup)
            var inner = context.descending(.position(0))
            inner.parent = container
            let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
            return [child.wrapping(size: child.measure) { bounds, proposal in
                qs_place(container, bounds.minX, bounds.minY, bounds.width, bounds.height)
                child.place(CGRect(origin: .zero, size: bounds.size), proposal)
            }]
        }
    }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            qs_group_rotation(group, ctx.interpolated(angle.degrees, key: "rotation"), anchor.x, anchor.y)
            return ctx.children(of: view, inside: group)
        }
    }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        Transform(content: self) { view, ctx in
            let dx = ctx.interpolated(x, key: "offset x"), dy = ctx.interpolated(y, key: "offset y")
            return view.resolve(ctx).map { child in child.wrapping(size: child.measure) { child.place($0.offsetBy(dx: dx, dy: dy), $1) } }
        }
    }
    public func offset(_ offset: CGSize) -> some View { self.offset(x: offset.width, y: offset.height) }
}
