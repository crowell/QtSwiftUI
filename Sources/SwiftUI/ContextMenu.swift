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
