public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
public enum ColorScheme: Sendable, Hashable { case light, dark }
public enum TextAlignment: Sendable, Hashable { case leading, center, trailing }
public struct EnvironmentValues {
    private var custom: [ObjectIdentifier: Any] = [:]
    var objects: [ObjectIdentifier: AnyObject] = [:]
    public init() {}
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { custom[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { custom[ObjectIdentifier(key)] = newValue }
    }
    public var colorScheme: ColorScheme = .light
    public var isEnabled = true
    var allowsHits = true
    public var font: Font?
    public var multilineTextAlignment: TextAlignment = .leading
    public var lineLimit: Int?
    var foreground = Color.primary

    var buttonStyle: ((ButtonStyleConfiguration) -> AnyView)?
    var focus: FocusLink?
    var submit: (() -> Void)?
    var accessibilityTraits: AccessibilityTraits = []
    var stackAxis = Axis.vertical
    var label = "", identifier = ""
}
extension Context {
    func with<T>(_ key: WritableKeyPath<EnvironmentValues, T>, _ value: T) -> Self {
        var copy = self
        copy.environment[keyPath: key] = value
        return copy
    }
}
@propertyWrapper @MainActor public struct Environment<Value>: MountedProperty {
    private final class Storage { var values = EnvironmentValues() }
    private let storage = Storage()
    private let read: (EnvironmentValues) -> Value
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { read = { $0[keyPath: keyPath] } }
    public init(_ objectType: Value.Type) where Value: AnyObject, Value: Observable {
        read = {
            guard let model = $0.objects[ObjectIdentifier(objectType)] as? Value else {
                preconditionFailure("Supply an instance of \(objectType) using .environment(_:)")
            }
            return model
        }
    }
    public init<T>(_ objectType: T.Type) where T: AnyObject, T: Observable, Value == T? {
        read = { $0.objects[ObjectIdentifier(objectType)] as? T }
    }
    public var wrappedValue: Value { read(storage.values) }
    func install(in context: Context) { storage.values = context.environment }
}
public struct Font: Hashable, Sendable {
    public struct Weight: Hashable, Sendable {
        let value: Int32
        public static let ultraLight = Self(value: 100), thin = Self(value: 200), light = Self(value: 300)
        public static let regular = Self(value: 400), medium = Self(value: 500), semibold = Self(value: 600)
        public static let bold = Self(value: 700), heavy = Self(value: 800), black = Self(value: 900)
    }
    var size: CGFloat, weight: Weight, slanted = false
    public static func system(size: CGFloat, weight: Weight = .regular) -> Self { Self(size: size, weight: weight) }
    public static let largeTitle = system(size: 34), title = system(size: 28), title2 = system(size: 22)
    public static let title3 = system(size: 20), headline = system(size: 17, weight: .semibold), body = system(size: 17)
    public static let callout = system(size: 16), subheadline = system(size: 15), footnote = system(size: 13)
    public static let caption = system(size: 12), caption2 = system(size: 11)
    public func weight(_ weight: Weight) -> Self { var f = self; f.weight = weight; return f }
    public func bold() -> Self { weight(.bold) }
    public func italic() -> Self { var f = self; f.slanted = true; return f }
}
