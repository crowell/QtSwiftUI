public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
public enum ScenePhase: Comparable, Hashable, Sendable { case background, inactive, active }
public enum ColorScheme: Sendable, Hashable { case light, dark }
public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight, rightToLeft

    func position(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard self == .rightToLeft else { return rect }
        return CGRect(x: bounds.minX + (bounds.maxX - rect.maxX), y: rect.minY, width: rect.width, height: rect.height)
    }
    func horizontalOffset(_ value: CGFloat) -> CGFloat { self == .rightToLeft ? -value : value }
}

public enum LayoutDirectionBehavior: Hashable, Sendable {
    case fixed
    case mirrors(in: LayoutDirection)
    public static var mirrors: Self { .mirrors(in: .rightToLeft) }
}
public enum TextAlignment: Sendable, Hashable { case leading, center, trailing }
public struct EnvironmentValues {
    private var custom: [ObjectIdentifier: Any] = [:]
    var objects: [ObjectIdentifier: AnyObject] = [:]
    public init() {}
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { custom[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { custom[ObjectIdentifier(key)] = newValue }
    }
    public var scenePhase: ScenePhase = .background
    public var colorScheme: ColorScheme = .light
    public var layoutDirection: LayoutDirection = Locale.current.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    public var isEnabled = true
    public var isScrollEnabled = true
    public var controlSize: ControlSize = .regular
    var plainField = false
    var fieldStyle: (@MainActor (TextField<_TextFieldStyleLabel>) -> AnyView)?
    var allowsHits = true
    var keyPressHandlers: [KeyPressHandler] = []
    var adjustment: AccessibleAdjustment?
    var gesturesEnabled = true
    public var font: Font?
    public var multilineTextAlignment: TextAlignment = .leading
    public var lineLimit: Int?
    public var verticalScrollBounceBehavior = ScrollBounceBehavior.automatic
    public var horizontalScrollBounceBehavior = ScrollBounceBehavior.automatic
    public var verticalScrollIndicatorVisibility = ScrollIndicatorVisibility.automatic
    public var horizontalScrollIndicatorVisibility = ScrollIndicatorVisibility.automatic
    var selectableText = false
    public var displayScale: CGFloat = 1
    var tracking: CGFloat = 0
    var foregroundPaint = ResolvedPaint.color(.primary)
    var foreground: Color {
        get { foregroundPaint.representativeColor }
        set { foregroundPaint = .color(newValue) }
    }

    public internal(set) var keyboardShortcut: KeyboardShortcut?
    var buttonStyle: ((ButtonStyleConfiguration, Context) -> AnyView)?
    var isLink = false
    var focus: FocusLink?
    public var isFocusEffectEnabled = true
    var submit: (() -> Void)?
    var closePresentation: @MainActor () -> Void = {}
    var urlAction: OpenURLAction?
    public var calendar: Calendar = .autoupdatingCurrent
    public var locale: Locale = .autoupdatingCurrent
    public var timeZone: TimeZone = .autoupdatingCurrent
    var accessibilityTraits: AccessibilityTraits = []
    var accessibleValue = ""
    var scrollBackground = Visibility.automatic
    var stackAxis = Axis.vertical
    var label = "", identifier = "", helpText = ""
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
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum TextStyle: Hashable, CaseIterable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
        var font: Font {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption
            case .caption2: .caption2
            }
        }
    }
    var size: CGFloat, weight: Weight, slanted = false
    var design: Design = .default
    var family: String?
    var qtFamily: String {
        if let family { return family }
        switch design {
        case .default: return ""
        case .serif: return "serif"
        case .rounded: return "sans-serif"
        case .monospaced: return "monospace"
        }
    }
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Self {
        Self(size: size, weight: weight, design: design)
    }
    public static func system(_ style: TextStyle, design: Design = .default, weight: Weight? = nil) -> Self {
        var font = style.font
        font.design = design
        if let weight { font.weight = weight }
        return font
    }
    public static func custom(_ name: String, size: CGFloat) -> Self { Self(size: size, weight: .regular, family: name) }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Self { Self(size: fixedSize, weight: .regular, family: name) }
    public func monospaced() -> Self { var copy = self; copy.design = .monospaced; copy.family = nil; return copy }
    public static let largeTitle = system(size: 34), title = system(size: 28), title2 = system(size: 22)
    public static let title3 = system(size: 20), headline = system(size: 17, weight: .semibold), body = system(size: 17)
    public static let callout = system(size: 16), subheadline = system(size: 15), footnote = system(size: 13)
    public static let caption = system(size: 12), caption2 = system(size: 11)
    public func weight(_ weight: Weight) -> Self { var f = self; f.weight = weight; return f }
    public func bold() -> Self { weight(.bold) }
    public func italic() -> Self { var f = self; f.slanted = true; return f }
}
