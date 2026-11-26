import QtBridge

public struct AccessibilityTraits: OptionSet, Sendable {
    public var rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let isImage = Self(rawValue: 1)
}
public struct AccessibilityChildBehavior: Equatable, Sendable {
    var exposesChildren: Bool
    public static let ignore = Self(exposesChildren: false), contain = Self(exposesChildren: true)
}
extension View {
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.accessibilityTraits, ctx.environment.accessibilityTraits.union(traits)))
        }
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        Transform(content: self) { view, ctx in
            let widget = ctx.widget(QSGroup)
            qs_group(widget, children.exposesChildren ? 1 : 0, ctx.environment.accessibilityTraits.contains(.isImage) ? 1 : 0)
            var inner = ctx.descending(.position(0))
            inner.parent = widget
            inner.environment.label = ""
            inner.environment.identifier = ""
            inner.environment.accessibilityTraits = []
            let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
            return [Element(size: child.measure) { bounds, p in
                qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
                child.place(CGRect(origin: .zero, size: bounds.size), p)
            }]
        }
    }
}
