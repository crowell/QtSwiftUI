import QtBridge

public protocol VisualEffect: Sendable, Animatable {}
public struct EmptyVisualEffect: VisualEffect {
    public init() {}
}

private struct GeometryEffect: VisualEffect {
    var translation = CGSize.zero
    var alpha = 1.0

    var animatableData: AnimatablePair<CGSize.AnimatableData, Double> {
        get { .init(translation.animatableData, alpha) }
        set { (translation.animatableData, alpha) = (newValue.first, newValue.second) }
    }
}

extension VisualEffect {
    private var geometryEffect: GeometryEffect { self as? GeometryEffect ?? GeometryEffect() }

    public func offset(_ offset: CGSize) -> some VisualEffect { self.offset(x: offset.width, y: offset.height) }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some VisualEffect {
        var result = geometryEffect
        result.translation.width += x
        result.translation.height += y
        return result
    }
    public func opacity(_ opacity: Double) -> some VisualEffect {
        var result = geometryEffect
        result.alpha *= min(1, max(0, opacity))
        return result
    }
}

extension View {
    public func visualEffect(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect) -> some View {
        Transform(content: self) { view, context in
            let group = context.widget(QSGroup)
            return context.children(of: view, inside: group).map { child in
                let element = child.wrapping(size: child.measure) { bounds, proposal in
                    var result = effect(EmptyVisualEffect(), context.geometry(in: bounds)) as? GeometryEffect ?? GeometryEffect()
                    result.animatableData = context.interpolated(result.animatableData, key: "visual effect")
                    let offset = result.translation
                    qs_group_opacity(group, result.alpha)
                    child.place(bounds.offsetBy(dx: offset.width, dy: offset.height), proposal)
                }
                return element
            }
        }
    }
}
