import QtBridge

public struct ContextMenu<MenuItems: View> {
    fileprivate let items: MenuItems
    public init(@ContentBuilder menuItems: () -> MenuItems) { items = menuItems() }
}

private nonisolated struct ContextMenuHost<Content: View, Items: View>: Primitive {
    let content: Content
    let menu: ContextMenu<Items>?

    @MainActor func elements(in context: Context) -> [Element] {
        let actions = MenuActions()
        let group = context.widget(QSGroup, action: actions.perform)
        let popup = qs_context_menu(group)!
        actions.configure(menu?.items, in: context, on: popup)
        return context.children(of: content, inside: group)
    }
}

extension View {
    /// Provides the trigger-local anchor for an application-drawn desktop context menu.
    @_spi(Qt) nonisolated public func qtOnContextRequest(isEnabled: Bool = true, perform: @escaping @MainActor (CGPoint) -> Void) -> some View {
        Transform(content: self) { content, context in
            let group = context.widget(QSGroup, tap: { widget in
                let origin = context.origin(of: .local, widget: widget)
                let point = qs_tap_location(widget)
                perform(CGPoint(x: point.width - origin.x, y: point.height - origin.y))
            })
            qs_context_request_scope(group, isEnabled && context.environment.isEnabled ? 1 : 0)
            return context.children(of: content, inside: group)
        }
    }

    nonisolated public func contextMenu<MenuItems: View>(@ContentBuilder menuItems: () -> MenuItems) -> some View {
        contextMenu(ContextMenu(menuItems: menuItems))
    }

    nonisolated public func contextMenu<M: View, P: View>(@ContentBuilder menuItems: () -> M,
                                                         @ContentBuilder preview: () -> P) -> some View {
        // Desktop context menus display their commands without a preview.
        contextMenu(menuItems: menuItems)
    }

    nonisolated public func contextMenu<MenuItems: View>(_ contextMenu: ContextMenu<MenuItems>?) -> some View {
        ContextMenuHost(content: self, menu: contextMenu)
    }
}
