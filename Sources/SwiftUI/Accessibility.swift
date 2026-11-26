import QtBridge

public struct AccessibilityTraits: OptionSet, Sendable {
    public var rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let allowsDirectInteraction = Self(rawValue: 512)
    public static let isLink = Self(rawValue: 256)
    public static let isSearchField = Self(rawValue: 128)
    public static let isImage = Self(rawValue: 1)
    public static let updatesFrequently = Self(rawValue: 2)
    public static let isSelected = Self(rawValue: 16), isButton = Self(rawValue: 32), isToggle = Self(rawValue: 64)
    public static let isHeader = Self(rawValue: 4), isModal = Self(rawValue: 8)
}
public struct AccessibilityChildBehavior: Equatable, Sendable {
    fileprivate let behavior: Int32
    public static let ignore = Self(behavior: 0)
    public static let contain = Self(behavior: 1)
    public static let combine = Self(behavior: 2)
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
            return [child.grouped(in: widget)]
        }
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        Transform(content: self) { view, ctx in
            let adjustment = ctx.environment.adjustment
            let widget = ctx.widget(QSGroup, adjustment: adjustment?.perform, accessibilityAction: { adjustment?.actions[$0]?() })
            qs_group_actions_clear(widget)
            if let adjustment { for name in adjustment.names { qs_group_action(widget, name) } }
            adjustment?.attached = true
            qs_adjustable(widget, adjustment?.perform == nil ? 0 : 1)
            let traits = ctx.environment.accessibilityTraits
            qs_group(widget, children.behavior, traits.contains(.isImage) ? 1 : 0,
                     traits.contains(.updatesFrequently) ? 1 : 0, ctx.environment.accessibleValue)
            var inner = ctx.descending(.position(0))
            inner.parent = widget
            inner.environment.label = ""
            inner.environment.identifier = ""
            inner.environment.accessibilityTraits = []
            inner.environment.removedAccessibilityTraits = []
            inner.environment.accessibleValue = ""
            inner.environment.accessibleHint = ""
            inner.environment.adjustment = nil
            let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
            return [child.grouped(in: widget)]
        }
    }
}
