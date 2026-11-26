import QtBridge

@MainActor public struct OpenURLAction {
    public struct Result: Sendable {
        fileprivate enum Destination: Sendable {
            case handled, discarded, system(URL?)
        }
        fileprivate let destination: Destination
        public static let handled = Self(destination: .handled)
        public static let discarded = Self(destination: .discarded)
        public static let systemAction = Self(destination: .system(nil))
        public static func systemAction(_ url: URL) -> Self { Self(destination: .system(url)) }
        public static func systemAction(_ url: URL? = nil, prefersInApp: Bool) -> Self { Self(destination: .system(url)) }
    }

    private let handler: (URL) -> Result
    private let systemOpen: (URL) -> Bool
    init(handler: @escaping (URL) -> Result, systemOpen: @escaping (URL) -> Bool) {
        self.handler = handler
        self.systemOpen = systemOpen
    }
    public init(handler: @escaping (URL) -> Result) {
        self.init(handler: handler, systemOpen: { qs_open_url($0.absoluteString) != 0 })
    }
    public func callAsFunction(_ url: URL) { self(url) { _ in } }
    public func callAsFunction(_ url: URL, prefersInApp: Bool) { self(url) }
    public func callAsFunction(_ url: URL, completion: @escaping (_ accepted: Bool) -> Void) {
        switch handler(url).destination {
        case .handled: completion(true)
        case .discarded: completion(false)
        case .system(let replacement): completion(systemOpen(replacement ?? url))
        }
    }
}

extension EnvironmentValues {
    @MainActor public var openURL: OpenURLAction {
        get { urlAction ?? OpenURLAction { _ in .systemAction } }
        set { urlAction = newValue }
    }
}

public struct Link<Label: View>: View {
    private let destination: URL
    private let label: Label
    @Environment(\.openURL) private var openURL

    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }
    public init<S: StringProtocol>(_ title: S, destination: URL) where Label == Text {
        self.init(destination: destination) { Text(title) }
    }
    public var body: some View {
        Button { openURL(destination) } label: { label }
            .buttonStyle(.plain)
            .environment(\.isLink, true)
            .foregroundStyle(Color.blue)
    }
}
