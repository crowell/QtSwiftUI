import QtBridge

public struct AccessibilityTraits: SetAlgebra, Sendable {
    public typealias Element = AccessibilityTraits
    public typealias ArrayLiteralElement = AccessibilityTraits

    private var bits: UInt64
    private init(bits: UInt64) { self.bits = bits }
    public init() { bits = 0 }

    public static let isImage = Self(bits: 1 << 0)
    public static let updatesFrequently = Self(bits: 1 << 1)
    public static let isHeader = Self(bits: 1 << 2)
    public static let isModal = Self(bits: 1 << 3)
    public static let isSelected = Self(bits: 1 << 4)
    public static let isButton = Self(bits: 1 << 5)
    public static let isToggle = Self(bits: 1 << 6)
    public static let isSearchField = Self(bits: 1 << 7)
    public static let isLink = Self(bits: 1 << 8)
    public static let allowsDirectInteraction = Self(bits: 1 << 9)
    public static let startsMediaSession = Self(bits: 1 << 10)
    public static let isStaticText = Self(bits: 1 << 11)
    public static let isTabBar = Self(bits: 1 << 12)

    public func union(_ other: AccessibilityTraits) -> AccessibilityTraits { Self(bits: bits | other.bits) }
    public func intersection(_ other: AccessibilityTraits) -> AccessibilityTraits { Self(bits: bits & other.bits) }
    public func symmetricDifference(_ other: AccessibilityTraits) -> AccessibilityTraits { Self(bits: bits ^ other.bits) }
    public mutating func formUnion(_ other: AccessibilityTraits) { bits |= other.bits }
    public mutating func formIntersection(_ other: AccessibilityTraits) { bits &= other.bits }
    public mutating func formSymmetricDifference(_ other: AccessibilityTraits) { bits ^= other.bits }
    public func contains(_ member: AccessibilityTraits) -> Bool { bits & member.bits == member.bits }

    // SwiftUI treats a composite trait as one member. These return values are
    // observable, including the empty result of removing the final trait.
    @discardableResult
    public mutating func insert(_ newMember: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) {
        let inserted = !contains(newMember)
        formUnion(newMember)
        return (inserted, self)
    }
    @discardableResult
    public mutating func remove(_ member: AccessibilityTraits) -> AccessibilityTraits? {
        bits &= ~member.bits
        return self
    }
    @discardableResult
    public mutating func update(with newMember: AccessibilityTraits) -> AccessibilityTraits? {
        formIntersection(newMember)
        return bits == 0 ? nil : self
    }
}
public struct AccessibilityChildBehavior: Equatable, Sendable {
    fileprivate let behavior: Int32
    public static let ignore = Self(behavior: 0)
    public static let contain = Self(behavior: 1)
    public static let combine = Self(behavior: 2)
}
extension View {
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
