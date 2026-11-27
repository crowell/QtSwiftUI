import QtBridge

@MainActor @preconcurrency public protocol Commands {
    associatedtype Body: Commands
    @ContentBuilder var body: Body { get }
}

extension Never: Commands {}

@MainActor private protocol CommandContent: Commands {
    func collect(in context: Context, into menus: MenuEntries)
}

private extension Commands {
    func resolve(in context: Context, into menus: MenuEntries) {
        let inner = context.descending(.type(ObjectIdentifier(Self.self)))
        if let primitive = self as? any CommandContent {
            primitive.collect(in: inner, into: menus)
        } else {
            inner.preparing(self).body.resolve(in: inner, into: menus)
        }
    }
}

public nonisolated struct EmptyCommands: CommandContent {
    public init() {}
    public var body: Never { fatalError("EmptyCommands has no body") }
    @MainActor fileprivate func collect(in context: Context, into menus: MenuEntries) {}
}

extension EmptyView: Commands, CommandContent {
    fileprivate func collect(in context: Context, into menus: MenuEntries) {}
}

extension TupleContent: Commands, CommandContent where repeat each Content: Commands {
    fileprivate func collect(in context: Context, into menus: MenuEntries) {
        var index = 0
        for command in repeat each content {
            command.resolve(in: context.descending(.position(index)), into: menus)
            index += 1
        }
    }
}

extension Optional: Commands, CommandContent where Wrapped: Commands {
    public var body: Never { fatalError("Optional commands are rendered directly") }
    fileprivate func collect(in context: Context, into menus: MenuEntries) {
        self?.resolve(in: context, into: menus)
    }
}

extension _ConditionalContent: Commands, CommandContent where TrueContent: Commands, FalseContent: Commands {
    public var body: Never { fatalError("Conditional commands are rendered directly") }
    @MainActor fileprivate func collect(in context: Context, into menus: MenuEntries) {
        switch storage {
        case .first(let content): content.resolve(in: context.descending(.position(0)), into: menus)
        case .second(let content): content.resolve(in: context.descending(.position(1)), into: menus)
        }
    }
}

@resultBuilder public struct CommandsBuilder {
    public static func buildExpression<C: Commands>(_ content: C) -> C { content }
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C: Commands>(_ content: C) -> C { content }
    @_disfavoredOverload public static func buildBlock<each C: Commands>(_ content: repeat each C) -> some Commands {
        TupleContent((repeat each content))
    }
    public static func buildIf<C: Commands>(_ content: C?) -> C? { content }
    public static func buildEither<T: Commands, F: Commands>(first: T) -> _ConditionalContent<T, F> { .init(first: first) }
    public static func buildEither<T: Commands, F: Commands>(second: F) -> _ConditionalContent<T, F> { .init(second: second) }
}

extension ViewBuilder {
    @_disfavoredOverload public static func buildExpression<C: Commands>(_ content: C) -> C { content }
    @_disfavoredOverload public static func buildBlock<each C: Commands>(_ content: repeat each C) -> some Commands {
        TupleContent((repeat each content))
    }
    @_disfavoredOverload public static func buildIf<C: Commands>(_ content: C?) -> C? { content }
    @_disfavoredOverload public static func buildEither<T: Commands, F: Commands>(first: T) -> _ConditionalContent<T, F> { .init(first: first) }
    @_disfavoredOverload public static func buildEither<T: Commands, F: Commands>(second: F) -> _ConditionalContent<T, F> { .init(second: second) }
}

public nonisolated struct CommandMenu<Content: View>: CommandContent {
    private let title: Text
    private let items: Content
    public init(_ name: Text, @ContentBuilder content: () -> Content) {
        title = name
        items = content()
    }
    public init(_ name: LocalizedStringKey, @ContentBuilder content: () -> Content) {
        self.init(Text(name), content: content)
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ name: S, @ContentBuilder content: () -> Content) {
        self.init(Text(verbatim: String(name)), content: content)
    }
    public var body: Never { fatalError("CommandMenu is rendered directly") }
    @MainActor fileprivate func collect(in context: Context, into menus: MenuEntries) {
        var inner = context
        let container = inner.widget(QSGroup)
        qs_drawing_only(container)
        inner.parent = container
        menus.rows.append(.init(title: title.resolvedString(context.environment.locale), children: MenuEntries.read(items, in: inner)))
    }
}

private nonisolated struct CommandScene<S: Scene, Content: Commands>: SceneCollection {
    let scene: S
    let commands: Content
    var body: Never { fatalError("Primitive command scene") }
    @MainActor var windows: [WindowScene] {
        scene.sceneWindows.map { original in
            var result = original
            result.commands = { context, menus in
                original.commands(context.descending(.position(0)), menus)
                commands.resolve(in: context.descending(.position(1)), into: menus)
            }
            return result
        }
    }
}

extension Scene {
    nonisolated public func commands<Content: Commands>(@ContentBuilder content: () -> Content) -> some Scene {
        CommandScene(scene: self, commands: content())
    }
}

extension WindowScene {
    func windowContent(in source: Context) -> [Element] {
        var context = source
        if let appDefaults { context.environment.appDefaults = appDefaults }
        let items = MenuEntries()
        let menuContext = context.descending(.property("window commands"))
        if let open = context.environment.presentSettings {
            let menu = MenuEntries()
            menu.rows.append(.init(title: "Settings…", shortcut: KeyboardShortcut(",", modifiers: .control), action: open))
            items.rows.append(.init(title: ProcessInfo.processInfo.processName, children: menu))
        }
        commands(menuContext, items)
        let content = content(context)
        guard !items.rows.isEmpty else { return content }
        let actions = MenuActions()
        let bar = menuContext.widget(QSMenuBar, action: actions.perform)
        actions.install(items, on: bar)
        let menuSize = qs_measure(bar, -1)
        let menuHeight = menuSize.height
        let root = stacked(content, axis: .vertical, alignment: .center, spacing: 8)
        func remaining(_ proposal: ProposedViewSize) -> ProposedViewSize {
            ProposedViewSize(width: proposal.width, height: proposal.height.map { max(0, $0 - menuHeight) })
        }
        return [Element { proposal in
            let measured = root.measure(remaining(proposal))
            let offeredWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0
            let offeredHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
            return CGSize(width: max(menuSize.width, measured.width, offeredWidth),
                          height: max(measured.height + menuHeight, offeredHeight))
        } place: { rect, proposal in
            qs_place(bar, rect.minX, rect.minY, rect.width, menuHeight)
            let inner = remaining(proposal)
            let area = CGRect(x: rect.minX, y: rect.minY + menuHeight, width: rect.width, height: max(0, rect.height - menuHeight))
            let size = root.measure(inner)
            root.place(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), inner)
        }]
    }
}
