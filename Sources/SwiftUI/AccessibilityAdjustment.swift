import QtBridge

public enum AccessibilityAdjustmentDirection: Hashable, Sendable { case increment, decrement }

@MainActor final class AccessibleAdjustment {
    let perform: (AccessibilityAdjustmentDirection) -> Void
    var attached = false
    init(_ perform: @escaping (AccessibilityAdjustmentDirection) -> Void) { self.perform = perform }
}

nonisolated public struct AccessibilityAttachmentModifier: PrimitiveModifier {
    public typealias Body = Never
    fileprivate var adjustment: (AccessibilityAdjustmentDirection) -> Void
    public func body(content: Content) -> Never { fatalError("Accessibility attachments are rendered directly") }

    @MainActor func applying(to content: AnyView) -> any View {
        Transform(content: content) { view, context in
            let target = AccessibleAdjustment(adjustment)
            let group = context.widget(QSGroup, adjustment: adjustment)
            let children = context.with(\.adjustment, target).children(of: view, inside: group)
            // Explicit accessibility elements preserve their own names, values and children.
            // A bare view gets a combined element to own the adjustment actions.
            qs_group(group, target.attached ? 1 : 2, 0, 0, context.environment.accessibleValue)
            qs_adjustable(group, target.attached ? 0 : 1)
            return children
        }
    }
}

extension View {
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
        -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(adjustment: handler))
    }
}
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
        -> ModifiedContent<Content, Modifier> {
        .init(content: content, modifier: .init(adjustment: handler))
    }
}
