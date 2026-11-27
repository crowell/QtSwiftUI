import QtBridge

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = Self(rawValue: 1)
    public static let keyboard = Self(rawValue: 2)
    public static let all = Self(rawValue: .max)
}

struct CoordinateSpaceGeometry {
    var size: CGSize
    var toWindow: CGAffineTransform
    var rotationDepth: Int

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
}

public struct GeometryProxy {
    let local: CoordinateSpaceGeometry
    let spaces: [AnyHashable: CoordinateSpaceGeometry]
    var fromWindow: CGAffineTransform { local.toWindow.inverted() }

    public var size: CGSize { local.size }
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect { frame(in: coordinateSpace.coordinateSpace) }
    @_disfavoredOverload public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        switch coordinateSpace {
        case .local: return local.bounds
        case .global: return local.bounds.applying(local.toWindow)
        case .named(let name):
            let fromWindow = spaces[name]?.toWindow.inverted() ?? .identity
            return local.bounds.applying(local.toWindow.concatenating(fromWindow))
        }
    }

    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
        // SwiftUI provides named bounds across translations and scales. Crossing
        // a rotation loses those bounds even if a later rotation cancels it.
        guard let other = spaces[coordinateSpace.name], other.rotationDepth == local.rotationDepth else { return nil }
        return other.bounds.applying(other.toWindow.concatenating(fromWindow))
    }
}

extension Context {
    func transformToWindow(from origin: CGPoint) -> CGAffineTransform {
        let translation = CGAffineTransform(translationX: origin.x, y: origin.y)
        guard let parent else { return translation }
        return translation.concatenating(widgetToWindow(parent))
    }

    func spaceGeometry(in bounds: CGRect) -> CoordinateSpaceGeometry {
        CoordinateSpaceGeometry(size: bounds.size, toWindow: transformToWindow(from: bounds.origin), rotationDepth: rotationDepth)
    }

    func geometry(in bounds: CGRect) -> GeometryProxy {
        GeometryProxy(local: spaceGeometry(in: bounds), spaces: spaces.compactMapValues(\.geometry))
    }
}

@frozen nonisolated public struct GeometryReader<Content: View>: Primitive {
    public var content: (GeometryProxy) -> Content
    public init(@ContentBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    @MainActor func elements(in context: Context) -> [Element] {
        [Element { $0.replacingUnspecifiedDimensions() } place: { bounds, _ in
            let proxy = context.geometry(in: bounds)
            let proposal = ProposedViewSize(bounds.size)
            for child in content(proxy).resolve(context) {
                child.place(Alignment.topLeading.rect(child.measure(proposal), in: bounds, direction: context.environment.layoutDirection), proposal)
            }
        }]
    }
}

@MainActor final class PlacedCoordinateSpace {
    var geometry: CoordinateSpaceGeometry?
}

private nonisolated struct NamedSpaceView<Content: View, Name: Hashable>: Primitive, SubviewSource {
    let content: Content
    let name: Name

    @MainActor func elements(in context: Context) -> [Element] {
        subviews(in: context).flatMap { $0.resolve(context.preferenceBranch()) }
    }

    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { child in
            child.applying { view, destination in
                let space = PlacedCoordinateSpace()
                var inner = destination
                inner.spaces[AnyHashable(name)] = space
                return view.resolve(inner).map { element in
                    element.wrapping(size: element.measure) { bounds, proposal in
                        space.geometry = destination.spaceGeometry(in: bounds)
                        element.place(bounds, proposal)
                    }
                }
            }
        }
    }
}

@MainActor private final class GeometrySample<Value> { var value: Value? }

private nonisolated struct GeometryObserver<Content: View, Value: Equatable & Sendable>: Primitive {
    let content: Content
    let project: @Sendable (GeometryProxy) -> Value
    let change: (Value, Value) -> Void

    @MainActor func elements(in context: Context) -> [Element] {
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
            // The observing view is the subview presented to the enclosing layout.
            element.values.removeAll()
            element.priority = 0
            return element
        }
    }
}
extension View {
    @preconcurrency nonisolated public func onGeometryChange<T: Equatable & Sendable>(for type: T.Type, of transform: @escaping @Sendable (GeometryProxy) -> T,
                                                         action: @escaping (_ newValue: T) -> Void) -> some View {
        GeometryObserver(content: self, project: transform) { _, next in action(next) }
    }
    @preconcurrency nonisolated public func onGeometryChange<T: Equatable & Sendable>(for type: T.Type, of transform: @escaping @Sendable (GeometryProxy) -> T,
                                                         action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        GeometryObserver(content: self, project: transform, change: action)
    }
    nonisolated public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View { coordinateSpace(name: name.name) }
    nonisolated public func coordinateSpace<T: Hashable>(name: T) -> some View {
        NamedSpaceView(content: self, name: name)
    }
    // The desktop host lays out its content entirely inside the window decorations.
    // Its container and keyboard safe-area insets are both zero.
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }

    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            return ctx.children(of: view, inside: group) { size in
                shape.displayPath(in: CGRect(origin: .zero, size: size), context: ctx).withNativePath {
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
    /// Qt platform adapter for content which uses a repeating compositor animation on macOS.
    @_spi(Qt) public func qtContinuousRotation(period: TimeInterval) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            let milliseconds = period.isFinite && period > 0 ? max(1, min(period * 1000, Double(Int32.max))) : 0
            qs_group_spin(group, Int32(milliseconds))
            return ctx.children(of: view, inside: group)
        }
    }

    nonisolated public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        scaleEffect(x: scale.width, y: scale.height, anchor: anchor)
    }
    nonisolated public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        scaleEffect(x: s, y: s, anchor: anchor)
    }
    nonisolated public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            let anchorX = ctx.environment.layoutDirection == .rightToLeft ? 1 - anchor.x : anchor.x
            // Keep a collapsed axis invertible when geometry is read from inside it.
            func invertible(_ value: CGFloat) -> CGFloat {
                let minimum = (2 * CGFloat.leastNormalMagnitude).squareRoot()
                return abs(value) < minimum ? (value < 0 ? -minimum : minimum) : value
            }
            qs_group_scale(group, invertible(ctx.interpolated(x, key: "scale x")),
                           invertible(ctx.interpolated(y, key: "scale y")), anchorX, anchor.y)
            return ctx.children(of: view, inside: group)
        }
    }
    nonisolated public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            let direction = ctx.environment.layoutDirection
            let degrees = ctx.interpolated(angle.degrees, key: "rotation")
            let anchorX = direction == .rightToLeft ? 1 - anchor.x : anchor.x
            qs_group_rotation(group, direction == .rightToLeft ? -degrees : degrees, anchorX, anchor.y)
            var inner = ctx
            if degrees != 0 { inner.rotationDepth += 1 }
            return inner.children(of: view, inside: group)
        }
    }
    nonisolated public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        Transform(content: self) { view, ctx in
            let dx = ctx.environment.layoutDirection.horizontalOffset(ctx.interpolated(x, key: "offset x"))
            let dy = ctx.interpolated(y, key: "offset y")
            return view.resolve(ctx).map { child in child.wrapping(size: child.measure) { child.place($0.offsetBy(dx: dx, dy: dy), $1) } }
        }
    }
    nonisolated public func offset(_ offset: CGSize) -> some View { self.offset(x: offset.width, y: offset.height) }
}
