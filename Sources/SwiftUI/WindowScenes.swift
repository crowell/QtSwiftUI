import QtBridge

@MainActor struct WindowScene {
    let title: String
    let id: String?
    let single: Bool
    var valueType: ObjectIdentifier?
    var initialValue: (() -> AnyHashable)?
    var size: CGSize?
    var resizability = WindowResizability.automatic
    let content: (Context) -> [Element]
    var commands: (Context, MenuEntries) -> Void = { _, _ in }
}

@MainActor protocol SceneCollection: Scene {
    var windows: [WindowScene] { get }
}

extension Scene {
    @MainActor var sceneWindows: [WindowScene] {
        if let collection = self as? any SceneCollection { return collection.windows }
        return body.sceneWindows
    }
}

private nonisolated struct SceneTuple<each Content: Scene>: SceneCollection {
    let scenes: (repeat each Content)
    var body: Never { fatalError("Primitive scene") }
    @MainActor var windows: [WindowScene] {
        var result: [WindowScene] = []
        for scene in repeat each scenes { result.append(contentsOf: scene.sceneWindows) }
        return result
    }
}

@resultBuilder public struct SceneBuilder {
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock() -> some Scene { SceneTuple(scenes: ()) }
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    @_disfavoredOverload public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> some Scene {
        SceneTuple(scenes: (repeat each content))
    }
}

public nonisolated struct WindowGroup<Content: View>: SceneCollection {
    private let title: String
    private let id: String?
    let makeView: () -> Content
    let valueType: ObjectIdentifier?
    let initialValue: (() -> AnyHashable)?

    init(title: String, id: String?, valueType: ObjectIdentifier? = nil, initialValue: (() -> AnyHashable)? = nil,
         makeView: @escaping () -> Content) {
        self.title = title
        self.id = id
        self.valueType = valueType
        self.initialValue = initialValue
        self.makeView = makeView
    }

    @_disfavoredOverload public init(@ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: "", id: nil) { view }
    }
    public init(@ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: "", id: nil, makeView: makeContent)
    }

    @_disfavoredOverload public init(id: String, @ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: "", id: id) { view }
    }
    public init(id: String, @ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: "", id: id, makeView: makeContent)
    }

    @_disfavoredOverload public init(_ title: Text, @ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: title.string, id: nil) { view }
    }
    public init(_ title: Text, @ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: title.string, id: nil, makeView: makeContent)
    }

    @_disfavoredOverload public init(_ title: Text, id: String, @ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: title.string, id: id) { view }
    }
    public init(_ title: Text, id: String, @ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: title.string, id: id, makeView: makeContent)
    }

    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: String(title), id: nil) { view }
    }
    public init<S: StringProtocol>(_ title: S, @ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: String(title), id: nil, makeView: makeContent)
    }

    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, id: String, @ContentBuilder content: () -> Content) {
        let view = content()
        self.init(title: String(title), id: id) { view }
    }
    public init<S: StringProtocol>(_ title: S, id: String, @ContentBuilder makeContent: @escaping () -> Content) {
        self.init(title: String(title), id: id, makeView: makeContent)
    }
    public var body: Never { fatalError("Primitive window group") }
    @MainActor var windows: [WindowScene] {
        [WindowScene(title: title, id: id, single: false, valueType: valueType, initialValue: initialValue,
                     content: { makeView().resolve($0) })]
    }
}

public nonisolated struct Window<Content: View>: SceneCollection {
    private let title: String
    private let id: String
    private let view: Content
    public init<S: StringProtocol>(_ title: S, id: String, @ContentBuilder content: () -> Content) {
        self.title = String(title); self.id = id; view = content()
    }
    public init(_ title: Text, id: String, @ContentBuilder content: () -> Content) { self.init(title.string, id: id, content: content) }
    public var body: Never { fatalError("Primitive window") }
    @MainActor var windows: [WindowScene] {
        [WindowScene(title: title, id: id, single: true, content: { view.resolve($0) })]
    }
}

private nonisolated struct SizedScene<S: Scene>: SceneCollection {
    let scene: S, size: CGSize
    var body: Never { fatalError("Primitive scene") }
    @MainActor var windows: [WindowScene] {
        scene.sceneWindows.map { scene in
            var result = scene
            result.size = size
            return result
        }
    }
}
extension Scene {
    nonisolated public func defaultSize(_ size: CGSize) -> some Scene { SizedScene(scene: self, size: size) }
    nonisolated public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        SizedScene(scene: self, size: CGSize(width: width, height: height))
    }
}

struct WindowRequest {
    var id: String?
    var type: ObjectIdentifier?
    var value: AnyHashable?

    init(id: String? = nil) { self.id = id }
    init<D: Codable & Hashable>(id: String? = nil, value: D) {
        self.id = id
        type = ObjectIdentifier(D.self)
        self.value = AnyHashable(value)
    }

    @MainActor func matches(_ definition: WindowScene) -> Bool {
        (id == nil || definition.id == id) && (type == nil || definition.valueType == type)
    }
}

@MainActor public struct OpenWindowAction {
    let open: (WindowRequest) -> Void
    public func callAsFunction(id: String) { open(WindowRequest(id: id)) }
    public func callAsFunction<D: Codable & Hashable>(value: D) { open(WindowRequest(value: value)) }
    public func callAsFunction<D: Codable & Hashable>(id: String, value: D) { open(WindowRequest(id: id, value: value)) }
}
@MainActor public struct DismissWindowAction {
    let dismiss: (WindowRequest?) -> Void
    public func callAsFunction() { dismiss(nil) }
    public func callAsFunction(id: String) { dismiss(WindowRequest(id: id)) }
    public func callAsFunction<D: Codable & Hashable>(value: D) { dismiss(WindowRequest(value: value)) }
    public func callAsFunction<D: Codable & Hashable>(id: String, value: D) { dismiss(WindowRequest(id: id, value: value)) }
}
extension EnvironmentValues {
    @MainActor public var openWindow: OpenWindowAction { OpenWindowAction(open: presentWindow) }
    @MainActor public var dismissWindow: DismissWindowAction { DismissWindowAction(dismiss: dismissScene) }
    public var supportsMultipleWindows: Bool { canPresentWindow }
}

/// App property storage lives for the entire event loop, including when the first
/// window is closed and a secondary window continues receiving events.
@MainActor final class AppWindows<Application: App> {
    private let app: Application
    private let appState = Host()
    private struct Instance {
        let sceneIndex: Int
        let host: Host
        let presentation: WindowPresentation
    }
    private var instances: [UUID: Instance] = [:]

    init(_ app: Application) {
        self.app = app
        appState.onUpdate = { [weak self] transaction in
            for window in self?.instances.values.map(\.host) ?? [] { window.update(transaction: transaction) }
        }
    }

    private func scenes(_ environment: EnvironmentValues = EnvironmentValues()) -> [WindowScene] {
        var context = Context(host: appState)
        context.environment = environment
        return context.preparing(app).body.sceneWindows
    }
    func openFirst() -> Host? { scenes().isEmpty ? nil : open(index: 0) }

    private func open(index: Int, value: AnyHashable? = nil) -> Host? {
        let definitions = scenes()
        guard definitions.indices.contains(index) else { return nil }
        let definition = definitions[index]
        if let current = instances.values.first(where: { instance in
            instance.sceneIndex == index && (definition.single || (value != nil && instance.presentation.value == value))
        }) {
            qs_window_raise(current.host.window)
            return current.host
        }
        let key = UUID()
        let presentation = WindowPresentation(value ?? definition.initialValue?())
        let host = Host(title: definition.title) { [weak self] source in
            guard let self else { return [] }
            var context = source
            context.environment.canPresentWindow = true
            context.environment.presentWindow = { [weak self] request in
                guard let self, let index = self.scenes().firstIndex(where: request.matches) else { return }
                _ = self.open(index: index, value: request.value)
            }
            context.windowValue = presentation.binding(in: context)
            context.environment.dismissScene = { [weak self] request in self?.dismiss(key, request: request) }
            context.environment.closePresentation = { [weak self] in self?.dismiss(key, request: nil) }
            let current = self.scenes(context.environment)
            guard current.indices.contains(index) else { return [] }
            source.host.resizability = current[index].resizability
            return current[index].windowContent(in: context)
        }
        host.observeClose { [weak self] in self?.instances.removeValue(forKey: key)?.host.close() }
        instances[key] = Instance(sceneIndex: index, host: host, presentation: presentation)
        let size = definition.size ?? CGSize(width: 640, height: 480)
        host.open(width: Int(size.width), height: Int(size.height))
        return host
    }

    private func dismiss(_ current: UUID, request: WindowRequest?) {
        let definitions = scenes()
        for (key, instance) in instances {
            if let request {
                guard definitions.indices.contains(instance.sceneIndex),
                      request.matches(definitions[instance.sceneIndex]),
                      request.value == nil || instance.presentation.value == request.value else { continue }
            } else if key != current { continue }
            qs_request_window_close(instance.host.window)
        }
    }

    func finish() {
        for instance in instances.values { instance.host.close() }
        instances.removeAll()
        appState.close()
    }
}
