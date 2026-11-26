import Foundation

private struct DefaultsCodec<Value> {
    let read: (UserDefaults, String) -> Value?
    let write: (UserDefaults, String, Value) -> Void

    fileprivate func optional() -> DefaultsCodec<Value?> {
        .init(read: { store, key in self.read(store, key) }, write: { store, key, value in
            if let value { self.write(store, key, value) } else { store.removeObject(forKey: key) }
        })
    }

    fileprivate func representing<R: RawRepresentable>(_ type: R.Type) -> DefaultsCodec<R> where R.RawValue == Value {
        .init(read: { store, key in self.read(store, key).flatMap(R.init(rawValue:)) },
              write: { store, key, value in self.write(store, key, value.rawValue) })
    }
}

private enum DefaultsCodecs {
    static var boolean: DefaultsCodec<Bool> {
        .init(read: { $0.bool(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
    static var integer: DefaultsCodec<Int> {
        .init(read: { $0.integer(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
    static var double: DefaultsCodec<Double> {
        .init(read: { $0.double(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
    static var string: DefaultsCodec<String> {
        .init(read: { $0.string(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
    static var date: DefaultsCodec<Date> {
        .init(read: { $0.object(forKey: $1) as? Date }, write: { $0.set($2, forKey: $1) })
    }
    static var data: DefaultsCodec<Data> {
        .init(read: { $0.data(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
    static var url: DefaultsCodec<URL> {
        .init(read: { store, key in
            if let data = store.data(forKey: key) {
                return (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data)) as URL?
            }
            return store.url(forKey: key)
        }, write: { store, key, url in
            if url.isFileURL {
                store.set(url.path, forKey: key)
            } else if let data = try? NSKeyedArchiver.archivedData(withRootObject: url as NSURL, requiringSecureCoding: true) {
                store.set(data, forKey: key)
            }
        })
    }
}

/// Corelibs Foundation does not post a change notification for individual
/// UserDefaults.set calls. A single timer watches keys mounted in live views.
@MainActor private final class DefaultsWatch {
    private struct Weak { weak var watch: DefaultsWatch? }
    private static var live: [Weak] = []
    private static var timer: Task<Void, Never>?

    let store: UserDefaults
    let key: String
    weak var host: Host?
    private var previous: NSObject?

    init(store: UserDefaults, key: String, host: Host) {
        self.store = store
        self.key = key
        self.host = host
        previous = store.object(forKey: key) as? NSObject
        Self.live.append(Weak(watch: self))
        if Self.timer == nil {
            Self.timer = Task {
                while !Self.live.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                    Self.refresh()
                }
                Self.timer = nil
            }
        }
    }

    static func refresh(transaction: Transaction? = nil) {
        var changed: [ObjectIdentifier: Host] = [:]
        live.removeAll { reference in
            guard let watch = reference.watch, let host = watch.host else { return true }
            let latest = watch.store.object(forKey: watch.key) as? NSObject
            if latest != watch.previous {
                watch.previous = latest
                changed[ObjectIdentifier(host)] = host
            }
            return false
        }
        for host in changed.values { host.update(transaction: transaction) }
    }
}

@propertyWrapper public struct AppStorage<Value>: MountedProperty {
    private let key: String
    private let fallback: Value
    private let explicitStore: UserDefaults?
    private var store: UserDefaults
    private let codec: DefaultsCodec<Value>

    private init(_ key: String, fallback: Value, store: UserDefaults?, codec: DefaultsCodec<Value>) {
        self.key = key
        self.fallback = fallback
        explicitStore = store
        self.store = store ?? .standard
        self.codec = codec
    }

    public var wrappedValue: Value {
        get {
            guard store.object(forKey: key) != nil else { return fallback }
            return codec.read(store, key) ?? fallback
        }
        nonmutating set {
            codec.write(store, key, newValue)
            store.synchronize()
            let transaction = Transaction.current
            if Thread.isMainThread { MainActor.assumeIsolated { DefaultsWatch.refresh(transaction: transaction) } }
            else { Task { @MainActor in DefaultsWatch.refresh(transaction: transaction) } }
        }
    }
    public var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }

    @MainActor mutating func install(in context: Context) {
        store = explicitStore ?? context.environment.appDefaults
        let host = context.host
        host.liveStorage.insert(context.path)
        if let current = host.storage[context.path] as? DefaultsWatch, current.key == key, current.store === store { return }
        host.storage[context.path] = DefaultsWatch(store: store, key: key, host: host)
    }
}

// The codecs and their configuration are immutable. UserDefaults supports
// concurrent reads and writes, and all view invalidation runs on the main actor.
extension AppStorage: @unchecked Sendable where Value: Sendable {}

extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.boolean)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.integer)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.double)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.string)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.url)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Date {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.date)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.data)
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.integer.representing(Value.self))
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        self.init(key, fallback: wrappedValue, store: store, codec: DefaultsCodecs.string.representing(Value.self))
    }
}

extension AppStorage where Value: ExpressibleByNilLiteral {
    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.boolean.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Int? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.integer.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Double? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.double.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == String? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.string.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == URL? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.url.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Date? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.date.optional())
    }
    public init(_ key: String, store: UserDefaults? = nil) where Value == Data? {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.data.optional())
    }
}

extension AppStorage {
    public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == Int {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.integer.representing(R.self).optional())
    }
    public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == String {
        self.init(key, fallback: nil, store: store, codec: DefaultsCodecs.string.representing(R.self).optional())
    }
}

private nonisolated struct DefaultStoreView<Content: View>: View {
    let content: Content
    let store: UserDefaults
    @MainActor var body: some View { content.environment(\.appDefaults, store) }
}

private nonisolated struct DefaultStoreScene<Content: Scene>: SceneCollection {
    let scene: Content
    let store: UserDefaults
    var body: Never { fatalError("Primitive scene modifier") }
    @MainActor var windows: [WindowScene] {
        scene.sceneWindows.map { scene in
            var window = scene
            window.appDefaults = scene.appDefaults ?? store
            return window
        }
    }
}

extension View {
    nonisolated public func defaultAppStorage(_ store: UserDefaults) -> some View {
        DefaultStoreView(content: self, store: store)
    }
}

extension Scene {
    nonisolated public func defaultAppStorage(_ store: UserDefaults) -> some Scene {
        DefaultStoreScene(scene: self, store: store)
    }
}
