import QtBridge

@MainActor protocol MenuEntrySource {
    func collect(in context: Context, into entries: MenuEntries)
}

@MainActor final class MenuEntries {
    struct Entry {
        var title = ""
        var enabled = true
        var checked: Bool?
        var separator = false
        var children: MenuEntries?
        var action: (() -> Void)?
    }
    var rows: [Entry] = []

    static func read(_ view: some View, in context: Context) -> MenuEntries {
        var inner = context
        let result = MenuEntries()
        inner.menuEntries = result
        _ = view.resolve(inner)
        return result
    }

    static func title(_ label: some View, in context: Context) -> String {
        if !context.environment.label.isEmpty { return context.environment.label }
        if let text = label as? Text { return text.string }
        return read(label, in: context.descending(.property("menu title"))).rows.map(\.title).joined(separator: " ")
    }

    func install(on menu: UnsafeMutableRawPointer, actions: inout [() -> Void]) {
        for (index, row) in rows.enumerated() {
            let id = row.action == nil ? -1 : actions.count
            if let action = row.action { actions.append(action) }
            let submenu = qs_menu_item(menu, Int32(index), row.title, row.enabled ? 1 : 0,
                                       row.checked.map { $0 ? 1 : 0 } ?? -1, row.separator ? 1 : 0,
                                       row.children == nil ? 0 : 1, Int32(id))
            if let submenu, let children = row.children { children.install(on: submenu, actions: &actions) }
        }
        qs_menu_finish(menu, Int32(rows.count))
    }
}

extension Button: MenuEntrySource {
    func collect(in context: Context, into entries: MenuEntries) {
        entries.rows.append(.init(title: MenuEntries.title(label, in: context), enabled: context.environment.isEnabled, action: action))
    }
}
extension Toggle: MenuEntrySource {
    func collect(in context: Context, into entries: MenuEntries) {
        entries.rows.append(.init(title: MenuEntries.title(label, in: context), enabled: context.environment.isEnabled,
                                  checked: isOn.wrappedValue, action: { isOn.wrappedValue.toggle() }))
    }
}
extension Text: MenuEntrySource {
    func collect(in context: Context, into entries: MenuEntries) {
        entries.rows.append(.init(title: string, enabled: false))
    }
}
extension Divider: MenuEntrySource {
    func collect(in context: Context, into entries: MenuEntries) { entries.rows.append(.init(separator: true)) }
}

public struct Menu<Label: View, Content: View>: Primitive, MenuEntrySource {
    let label: Label, content: Content

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
        self.init(content: content) { Text(title) }
    }
    public init(_ configuration: MenuStyleConfiguration) where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
        label = configuration.label
        content = configuration.content
    }

    func collect(in context: Context, into entries: MenuEntries) {
        var nested = context.descending(.property("submenu"))
        nested.environment.label = ""
        entries.rows.append(.init(title: MenuEntries.title(label, in: context), enabled: context.environment.isEnabled,
                                  children: MenuEntries.read(content, in: nested)))
    }

    func elements(in context: Context) -> [Element] {
        if let style = context.environment.menuStyle {
            let configuration = MenuStyleConfiguration(label: .init(view: AnyView(label)), content: .init(view: AnyView(content)))
            return style(configuration).resolve(context.with(\.menuStyle, nil))
        }
        var actions: [() -> Void] = []
        let button = Button(action: {}) { label }
        return button.buttonElements(in: context, kind: QSMenuButton) { raw in
            if let index = Int(raw), actions.indices.contains(index) { actions[index]() }
        } configure: { button in
            var items = context.descending(.property("menu content"))
            // Menu labels can be composed from arbitrary views. Keep their backing widgets outside the window layout.
            let container = items.widget(QSGroup)
            qs_drawing_only(container)
            items.parent = container
            items.environment.label = ""
            items.environment.focus = nil
            let rows = MenuEntries.read(content, in: items)
            let popup = qs_menu_begin(button, context.environment.menuIndicator == .hidden ? 0 : 1)!
            rows.install(on: popup, actions: &actions)
        }
    }
}

@MainActor public protocol MenuStyle {
    associatedtype Body: View
    typealias Configuration = MenuStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

public struct MenuStyleConfiguration {
    public struct Label: Primitive {
        fileprivate let view: AnyView
        func elements(in context: Context) -> [Element] { view.resolve(context) }
    }
    public struct Content: Primitive {
        fileprivate let view: AnyView
        func elements(in context: Context) -> [Element] { view.resolve(context) }
    }
    fileprivate let label: Label, content: Content
}

public struct ButtonMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Menu(configuration) }
}
public struct DefaultMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Menu(configuration) }
}
extension MenuStyle where Self == ButtonMenuStyle { public static var button: Self { Self() } }
extension MenuStyle where Self == DefaultMenuStyle { public static var automatic: Self { Self() } }

private nonisolated struct StyledMenu<Content: View, Style: MenuStyle>: View {
    let content: Content
    let style: Style
    @MainActor var body: some View {
        Transform(content: content) { view, context in
            view.resolve(context.with(\.menuStyle, { AnyView(style.makeBody(configuration: $0)) }))
        }
    }
}

extension View {
    nonisolated public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        StyledMenu(content: self, style: style)
    }
    nonisolated public func menuIndicator(_ visibility: Visibility) -> some View {
        Transform(content: self) { view, context in view.resolve(context.with(\.menuIndicator, visibility)) }
    }
}
