import QtBridge

public struct AccessibilityTraits: OptionSet, Sendable {
    public var rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let isImage = Self(rawValue: 1)
    public static let updatesFrequently = Self(rawValue: 2)
    public static let isHeader = Self(rawValue: 4), isModal = Self(rawValue: 8)
}
public struct AccessibilityChildBehavior: Equatable, Sendable {
    var exposesChildren: Bool
    public static let ignore = Self(exposesChildren: false), contain = Self(exposesChildren: true)
}
extension View {
    public func accessibilityValue(_ value: Text) -> some View { environment(\.accessibleValue, value.string) }
    public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { environment(\.accessibleValue, String(value)) }
    public func accessibilityHidden(_ hidden: Bool) -> some View {
        Transform(content: self) { view, ctx in
            let widget = ctx.widget(QSGroup)
            qs_group_hidden(widget, hidden ? 1 : 0)
            var inner = ctx.descending(.position(0))
            inner.parent = widget
            let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
            return [Element(size: child.measure) { bounds, proposal in
                qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
                child.place(CGRect(origin: .zero, size: bounds.size), proposal)
            }]
        }
    }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
        Transform(content: self) { view, ctx in
            let inner = ctx.with(\.accessibilityTraits, ctx.environment.accessibilityTraits.union(traits))
            guard !traits.intersection([.isHeader, .isModal]).isEmpty else { return view.resolve(inner) }
            let group = ctx.widget(QSGroup)
            qs_group_semantics(group, traits.contains(.isHeader) ? 1 : 0, traits.contains(.isModal) ? 1 : 0)
            return inner.children(of: view, inside: group)
        }
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        Transform(content: self) { view, ctx in
            let widget = ctx.widget(QSGroup)
            let traits = ctx.environment.accessibilityTraits
            qs_group(widget, children.exposesChildren ? 1 : 0, traits.contains(.isImage) ? 1 : 0,
                     traits.contains(.updatesFrequently) ? 1 : 0, ctx.environment.accessibleValue)
            var inner = ctx.descending(.position(0))
            inner.parent = widget
            inner.environment.label = ""
            inner.environment.identifier = ""
            inner.environment.accessibilityTraits = []
            inner.environment.accessibleValue = ""
            let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
            return [Element(size: child.measure) { bounds, p in
                qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
                child.place(CGRect(origin: .zero, size: bounds.size), p)
            }]
        }
    }
}
