import QtBridge
@_spi(Reflection) import Swift
@_exported import Observation

enum Part: Hashable {
    case type(ObjectIdentifier), position(Int), id(AnyHashable), property(String), widget(UInt32)
}

@MainActor struct Context {
    let host: Host
    var path: [Part] = []
    var parent: UnsafeMutableRawPointer?
    var environment = EnvironmentValues()
    var spaces: [AnyHashable: NamedOrigin] = [:]
    var windowOffset: CGPoint {
        guard let parent else { return .zero }
        let position = qs_origin(parent)
        return CGPoint(x: position.width, y: position.height)
    }
    func descending(_ part: Part) -> Self {
        var result = self
        result.path.append(part)
        return result
    }
    func preparing<Owner>(_ original: Owner) -> Owner {
        var owner = original
        func update<P: DynamicProperty>(_ property: P, at name: String) -> P {
            let child = descending(.property(name))
            var result = property
            if let builtIn = result as? any MountedProperty {
                builtIn.install(in: child)
            } else {
                result = child.preparing(result)
            }
            result.update()
            return result
        }
        // Stored-property key paths preserve value semantics when a custom
        // DynamicProperty's mutating update() changes its own fields.
        let enumerated = _forEachFieldWithKeyPath(of: Owner.self) { name, key in
            if let property = owner[keyPath: key] as? any DynamicProperty {
                @MainActor func assign<P: DynamicProperty>(_ property: P) {
                    let updated = update(property, at: String(cString: name))
                    if let writable = key as? WritableKeyPath<Owner, P> { owner[keyPath: writable] = updated }
                }
                assign(property)
            }
            return true
        }
        if !enumerated {
            for (name, value) in Mirror(reflecting: owner).children {
                if let name, let property = value as? any DynamicProperty { _ = update(property, at: name) }
            }
        }
        return owner
    }
    func widget(_ kind: QSKind, pressed: ((Bool) -> Void)? = nil, exitCommand: (() -> Void)? = nil,
                hover: ((Bool) -> Void)? = nil, action: ((String) -> Void)? = nil) -> UnsafeMutableRawPointer {
        let entry = host.mount(path: path + [.widget(kind.rawValue)], kind: kind, parent: parent)
        let focus = environment.focus
        let submit = environment.submit
        host.events[entry.id] = { kind, value in
            switch kind {
            case QSActivate: action?(value)
            case QSFocusChanged: focus?.change(value == "1")
            case QSSubmit: submit?()
            case QSExitCommand: exitCommand?()
            case QSHoverChanged: hover?(value == "1")
            case QSPressedChanged: pressed?(value == "1")
            default: break
            }
        }
        if kind != QSSurface && kind != QSCanvas { qs_hit_testing(entry.widget, environment.allowsHits ? 1 : 0) }
        qs_enabled(entry.widget, environment.isEnabled ? 1 : 0)
        qs_accessibility(entry.widget, environment.label, environment.identifier)
        qs_help(entry.widget, environment.helpText)
        if let focus { qs_focus(entry.widget, focus.active() ? 1 : 0) }
        return entry.widget
    }
}

@Observable private final class ObservationPass { var revision = 0 }

@MainActor final class Host {
    private let observationPass = ObservationPass()
    struct Mount {
        let widget: UnsafeMutableRawPointer
        let id: Int32
    }
    private var mounts: [[Part]: Mount] = [:]
    private var liveMounts = Set<[Part]>()
    private var nextID: Int32 = 0
    var storage: [[Part]: AnyObject] = [:]
    var liveStorage = Set<[Part]>()
    private var disappear: [[Part]: () -> Void] = [:]
    private var nextDisappear: [[Part]: () -> Void] = [:]
    private var afterRender: [() -> Void] = []
    func lifetime(at path: [Part], appear: @escaping () -> Void, disappear action: @escaping () -> Void) {
        if disappear[path] == nil && nextDisappear[path] == nil { afterRender.append(appear) }
        nextDisappear[path] = action
    }
    var events: [Int32: (QSEventKind, String) -> Void] = [:]
    private let content: (Context) -> [Element]
    private(set) var window: OpaquePointer!

    init(title: String, content: @escaping (Context) -> [Element]) {
        self.content = content
        window = qs_window(title, Unmanaged.passUnretained(self).toOpaque(), { pointer, width, height in
            MainActor.assumeIsolated {
                Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().render(width: Int(width), height: Int(height))
            }
        }, { pointer, id, kind, value in
            let string = value.map { String(cString: $0) } ?? ""
            MainActor.assumeIsolated { Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().events[id]?(kind, string) }
        })
    }
    func open(width: Int, height: Int) { qs_open(window, Int32(width), Int32(height)) }
    func close() {
        if let window { qs_close(window); self.window = nil }
        for stop in disappear.values { stop() }
        disappear.removeAll()
        observationPass.revision += 1
        mounts.removeAll()
        events.removeAll()
        storage.removeAll()
    }
    func update() { if let window { qs_update(window) } }
    func mount(path: [Part], kind: QSKind, parent: UnsafeMutableRawPointer?) -> Mount {
        liveMounts.insert(path)
        if let entry = mounts[path] { return entry }
        nextID += 1
        let entry = Mount(widget: qs_create(window, parent, kind, nextID)!, id: nextID)
        mounts[path] = entry
        return entry
    }
    private func render(width: Int, height: Int) {
        liveMounts.removeAll(keepingCapacity: true)
        liveStorage.removeAll(keepingCapacity: true)
        nextDisappear.removeAll(keepingCapacity: true)
        // Changing this tracked value releases the previous pass’s one-shot observation.
        observationPass.revision += 1
        let revision = observationPass.revision
        withObservationTracking {
            _ = observationPass.revision
            layout(width: width, height: height)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationPass.revision == revision else { return }
                self.update()
            }
        }
        let ended = disappear.filter { nextDisappear[$0.key] == nil }
        disappear = nextDisappear
        for action in ended.values { action() }
        let pending = afterRender
        afterRender.removeAll(keepingCapacity: true)
        for action in pending { action() }
    }
    private func layout(width: Int, height: Int) {
        var context = Context(host: self)
        context.environment.closePresentation = { [weak self] in
            if let window = self?.window { qs_request_close(window) }
        }
        let roots = content(context)
        let root = stacked(roots, axis: .vertical, alignment: .center, spacing: 8)
        let proposal = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
        let size = root.measure(proposal)
        root.place(CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                          width: size.width, height: size.height), proposal)
        // Qt owns descendant widgets. Release stale descendants before their scroll area.
        for path in mounts.keys.filter({ !liveMounts.contains($0) }).sorted(by: { $0.count > $1.count }) {
            if let mount = mounts.removeValue(forKey: path) {
                events[mount.id] = nil
                qs_destroy(mount.widget)
            }
        }
        storage = storage.filter { liveStorage.contains($0.key) }
    }
}

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

protocol MountedProperty: DynamicProperty {
    @MainActor func install(in context: Context)
}

@propertyWrapper @dynamicMemberLookup public struct Binding<Value>: DynamicProperty {
    private let get: () -> Value
    private let set: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { self.get = get; self.set = set }
    public static func constant(_ value: Value) -> Self { Self(get: { value }, set: { _ in }) }
    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
    public var projectedValue: Self { self }
    public subscript<T>(dynamicMember path: WritableKeyPath<Value, T>) -> Binding<T> {
        Binding<T>(get: { wrappedValue[keyPath: path] }, set: { wrappedValue[keyPath: path] = $0 })
    }
}
@propertyWrapper public struct State<Value>: MountedProperty {
    private final class Cell {
        private let lock = NSLock()
        private var stored: Value
        private weak var host: Host?
        init(_ value: Value) { stored = value }
        var value: Value {
            get { lock.withLock { stored } }
            set {
                let target = lock.withLock {
                    stored = newValue
                    return host
                }
                guard let target else { return }
                if Thread.isMainThread {
                    MainActor.assumeIsolated { target.update() }
                } else {
                    Task { @MainActor [weak target] in target?.update() }
                }
            }
        }
        func attach(to host: Host) { lock.withLock { self.host = host } }
    }
    private final class Link {
        private let lock = NSLock()
        private var target: Cell
        init(_ cell: Cell) { target = cell }
        var cell: Cell {
            get { lock.withLock { target } }
            set { lock.withLock { target = newValue } }
        }
    }
    private let link: Link
    public init(wrappedValue: Value) { link = Link(Cell(wrappedValue)) }
    public init(initialValue: Value) { self.init(wrappedValue: initialValue) }
    public init() where Value: ExpressibleByNilLiteral { self.init(wrappedValue: nil) }
    public var wrappedValue: Value {
        get { link.cell.value }
        nonmutating set { link.cell.value = newValue }
    }
    public var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
    func install(in context: Context) {
        let host = context.host
        host.liveStorage.insert(context.path)
        if let existing = host.storage[context.path] as? Cell { link.cell = existing }
        else { host.storage[context.path] = link.cell }
        link.cell.attach(to: host)
    }
}
