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
    fileprivate var namedActions: [(Text, () -> Void)] = []
    fileprivate var actionContent: (@MainActor (Context) -> MenuEntries)?
    fileprivate var label: Text?
    fileprivate var value: Text?
    fileprivate var hint: Text?
    fileprivate var addedTraits: AccessibilityTraits = []
    fileprivate var removedTraits: AccessibilityTraits = []
    public func body(content: Content) -> Never { fatalError("Accessibility attachments are rendered directly") }

    @MainActor func applying(to content: AnyView) -> any View {
        Transform(content: content) { view, context in
            var context = context
            let environment = context.environment
            if let label { context.environment.label = label.resolvedString(environment) }
            if let value { context.environment.accessibleValue = value.resolvedString(environment) }
            if let hint { context.environment.accessibleHint = hint.resolvedString(environment) }
            // The outermost attachment is the last modifier the caller applied.
            let decided = context.environment.accessibilityTraits.union(context.environment.removedAccessibilityTraits)
            let added = addedTraits.subtracting(decided)
            context.environment.accessibilityTraits.formUnion(added)
            context.environment.removedAccessibilityTraits.formUnion(removedTraits.subtracting(decided))
            var callbacks = actions
            var names = Array(actions.keys)
            for (title, handler) in namedActions {
                let name = title.resolvedString(environment)
                if callbacks[name] == nil { names.append(name) }
                callbacks[name] = handler
            }
            if let entries = actionContent?(context) {
                for row in entries.rows where row.enabled && !row.title.isEmpty {
                    if let action = row.action, callbacks[row.title] == nil {
                        names.append(row.title)
                        callbacks[row.title] = action
                    }
                }
            }
            let roleTraits = added.intersection([.isHeader, .isModal, .isStaticText, .isTabBar])
            func applyRoles(to group: QSWidget?) {
                qs_group_semantics(group, roleTraits.contains(.isHeader) ? 1 : 0, roleTraits.contains(.isModal) ? 1 : 0,
                                   roleTraits.contains(.isStaticText) ? 1 : 0, roleTraits.contains(.isTabBar) ? 1 : 0)
            }
            if adjustment == nil && callbacks.isEmpty {
                guard !roleTraits.isEmpty else { return view.resolve(context) }
                let group = context.widget(QSGroup)
                applyRoles(to: group)
                return context.children(of: view, inside: group)
            }
            let target = AccessibleAdjustment(adjustment, actions: callbacks, names: names)
            let group = context.widget(QSGroup, adjustment: adjustment, accessibilityAction: { target.actions[$0]?() })
            applyRoles(to: group)
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
        .init(content: self, modifier: .init(namedActions: [(name, handler)]))
    }
    nonisolated public func accessibilityAction(named key: LocalizedStringKey, _ handler: @escaping () -> Void)
        -> ModifiedContent<Self, AccessibilityAttachmentModifier> { accessibilityAction(named: Text(key), handler) }
    @_disfavoredOverload nonisolated public func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping () -> Void)
        -> ModifiedContent<Self, AccessibilityAttachmentModifier> { accessibilityAction(named: Text(name), handler) }

    nonisolated public func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(label, isEnabled: true)
    }
    nonisolated public func accessibilityLabel(_ label: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(label: isEnabled ? label : nil))
    }
    nonisolated public func accessibilityLabel(_ key: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(Text(key))
    }
    nonisolated public func accessibilityLabel(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(Text(label))
    }
    @_disfavoredOverload nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(Text(label), isEnabled: isEnabled)
    }
    nonisolated public func accessibilityValue(_ value: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityValue(value, isEnabled: true)
    }
    nonisolated public func accessibilityValue(_ value: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(value: isEnabled ? value : nil))
    }
    nonisolated public func accessibilityValue(_ key: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityValue(Text(key))
    }
    nonisolated public func accessibilityValue(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityValue(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityValue(Text(value))
    }
    @_disfavoredOverload nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityValue(Text(value), isEnabled: isEnabled)
    }
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(hint, isEnabled: true)
    }
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        .init(content: self, modifier: .init(hint: isEnabled ? hint : nil))
    }
    nonisolated public func accessibilityHint(_ key: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(Text(key))
    }
    nonisolated public func accessibilityHint(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(Text(hint))
    }
    @_disfavoredOverload nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(Text(hint), isEnabled: isEnabled)
    }
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
        var attachment = modifier
        attachment.namedActions.append((name, handler))
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityAction(named key: LocalizedStringKey, _ handler: @escaping () -> Void)
        -> ModifiedContent<Content, Modifier> { accessibilityAction(named: Text(key), handler) }
    @_disfavoredOverload nonisolated public func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping () -> Void)
        -> ModifiedContent<Content, Modifier> { accessibilityAction(named: Text(name), handler) }

    nonisolated public func accessibilityLabel(_ label: Text) -> ModifiedContent<Content, Modifier> {
        accessibilityLabel(label, isEnabled: true)
    }
    nonisolated public func accessibilityLabel(_ label: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        if isEnabled { attachment.label = label }
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityLabel(_ key: LocalizedStringKey) -> ModifiedContent<Content, Modifier> {
        accessibilityLabel(Text(key))
    }
    nonisolated public func accessibilityLabel(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityLabel(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S) -> ModifiedContent<Content, Modifier> {
        accessibilityLabel(Text(label))
    }
    @_disfavoredOverload nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityLabel(Text(label), isEnabled: isEnabled)
    }
    nonisolated public func accessibilityValue(_ value: Text) -> ModifiedContent<Content, Modifier> {
        accessibilityValue(value, isEnabled: true)
    }
    nonisolated public func accessibilityValue(_ value: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        if isEnabled { attachment.value = value }
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityValue(_ key: LocalizedStringKey) -> ModifiedContent<Content, Modifier> {
        accessibilityValue(Text(key))
    }
    nonisolated public func accessibilityValue(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityValue(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S) -> ModifiedContent<Content, Modifier> {
        accessibilityValue(Text(value))
    }
    @_disfavoredOverload nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityValue(Text(value), isEnabled: isEnabled)
    }
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Content, Modifier> {
        accessibilityHint(hint, isEnabled: true)
    }
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        if isEnabled { attachment.hint = hint }
        return .init(content: content, modifier: attachment)
    }
    nonisolated public func accessibilityHint(_ key: LocalizedStringKey) -> ModifiedContent<Content, Modifier> {
        accessibilityHint(Text(key))
    }
    nonisolated public func accessibilityHint(_ key: LocalizedStringKey, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityHint(Text(key), isEnabled: isEnabled)
    }
    @_disfavoredOverload nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> ModifiedContent<Content, Modifier> {
        accessibilityHint(Text(hint))
    }
    @_disfavoredOverload nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        accessibilityHint(Text(hint), isEnabled: isEnabled)
    }
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
        -> ModifiedContent<Content, Modifier> {
        var attachment = modifier
        attachment.adjustment = handler
        return .init(content: content, modifier: attachment)
    }
}
