import QtBridge

public enum AccessibilityAdjustmentDirection: Hashable, Sendable { case increment, decrement }

public struct AccessibilityActionKind: Equatable, Sendable {
    fileprivate let name: String
    private init(_ name: String) { self.name = name }
    public init(named name: Text) { self.name = name.string }
    public static let `default` = Self("Press"), escape = Self("Escape"), magicTap = Self("Magic Tap")
    public static let delete = Self("Delete"), showMenu = Self("ShowMenu")
}
@MainActor final class AccessibleAdjustment {
    let perform: ((AccessibilityAdjustmentDirection) -> Void)?
    let actions: [String: () -> Void]
    let names: [String]
    var attached = false
    init(_ perform: ((AccessibilityAdjustmentDirection) -> Void)?, actions: [String: () -> Void], names: [String]) {
        self.perform = perform
        self.actions = actions
        self.names = names
    }
}

nonisolated public struct AccessibilityAttachmentModifier: PrimitiveModifier {
    public typealias Body = Never
    fileprivate var adjustment: ((AccessibilityAdjustmentDirection) -> Void)?
    fileprivate var actions: [String: () -> Void] = [:]
    fileprivate var actionContent: (@MainActor (Context) -> MenuEntries)?
    fileprivate var hint: String?
    fileprivate var addedTraits: AccessibilityTraits = []
    fileprivate var removedTraits: AccessibilityTraits = []
    public func body(content: Content) -> Never { fatalError("Accessibility attachments are rendered directly") }

    @MainActor func applying(to content: AnyView) -> any View {
        Transform(content: content) { view, context in
            var context = context
            if let hint { context.environment.accessibleHint = hint }
            // The outermost attachment is the last modifier the caller applied.
            let decided = context.environment.accessibilityTraits.union(context.environment.removedAccessibilityTraits)
            let added = addedTraits.subtracting(decided)
            context.environment.accessibilityTraits.formUnion(added)
            context.environment.removedAccessibilityTraits.formUnion(removedTraits.subtracting(decided))
            var callbacks = actions
            var names = Array(actions.keys)
            if let entries = actionContent?(context) {
                for row in entries.rows where row.enabled && !row.title.isEmpty {
                    if let action = row.action, callbacks[row.title] == nil {
                        names.append(row.title)
                        callbacks[row.title] = action
                    }
                }
            }
            if adjustment == nil && callbacks.isEmpty {
                guard !added.intersection([.isHeader, .isModal]).isEmpty else { return view.resolve(context) }
                let group = context.widget(QSGroup)
                qs_group_semantics(group, added.contains(.isHeader) ? 1 : 0, added.contains(.isModal) ? 1 : 0)
                return context.children(of: view, inside: group)
            }
            let target = AccessibleAdjustment(adjustment, actions: callbacks, names: names)
            let group = context.widget(QSGroup, adjustment: adjustment, accessibilityAction: { target.actions[$0]?() })
            qs_group_semantics(group, added.contains(.isHeader) ? 1 : 0, added.contains(.isModal) ? 1 : 0)
            let children = context.with(\.adjustment, target).children(of: view, inside: group)
            // Explicit accessibility elements preserve their own names, values and children.
            // A bare view gets a combined element to own the adjustment actions.
            qs_group(group, target.attached ? 1 : 2, 0, 0, context.environment.accessibleValue)
            qs_adjustable(group, !target.attached && adjustment != nil ? 1 : 0)
            qs_group_actions_clear(group)
            if !target.attached { for action in names { qs_group_action(group, action) } }
            return children
        }
    }
}

extension View {
    nonisolated public func accessibilityActions<Content: View>(@ContentBuilder _ content: () -> Content) -> some View {
        let commands = content()
        return ModifiedContent(content: self, modifier: AccessibilityAttachmentModifier(actionContent: { MenuEntries.commands(commands, in: $0) }))
    }

    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(addedTraits: traits))
    }
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(removedTraits: traits))
    }
    nonisolated public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(actions: [actionKind.name: handler]))
    }
    nonisolated public func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityAction(.init(named: name), handler)
    }
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { accessibilityHint(hint, isEnabled: true) }
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(hint: isEnabled ? hint.string : nil))
    }
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { accessibilityHint(Text(hint)) }
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { accessibilityHint(Text(hint), isEnabled: isEnabled) }
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
        -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(adjustment: handler))
    }
}
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        attachment.addedTraits.formUnion(traits)
        attachment.removedTraits.subtract(traits)
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        attachment.removedTraits.formUnion(traits)
        attachment.addedTraits.subtract(traits)
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        attachment.actions[actionKind.name] = handler
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> ModifiedContent<Content, Modifier> {
        accessibilityAction(.init(named: name), handler)
    }
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Content, Modifier> { accessibilityHint(hint, isEnabled: true) }
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        if isEnabled { attachment.hint = hint.string }
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> ModifiedContent<Content, Modifier> { accessibilityHint(Text(hint)) }
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool) -> ModifiedContent<Content, Modifier> { accessibilityHint(Text(hint), isEnabled: isEnabled) }
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
        -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        attachment.adjustment = handler
        return .init(content: content, modifier: attachment)
    }
}
