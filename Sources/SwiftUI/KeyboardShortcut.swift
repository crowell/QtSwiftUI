import QtBridge

public struct EventModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let capsLock = Self(rawValue: 1)
    public static let shift = Self(rawValue: 2)
    public static let control = Self(rawValue: 4)
    public static let option = Self(rawValue: 8)
    public static let command = Self(rawValue: 16)
    public static let numericPad = Self(rawValue: 32)
    @available(*, deprecated, message: "Function modifier is reserved for system applications")
    public static let function = Self(rawValue: 64)
    public static let all: Self = [.capsLock, .shift, .control, .option, .command, .numericPad]
}

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public var character: Character
    public init(_ character: Character) { self.character = character }
    public init(extendedGraphemeClusterLiteral value: Character) { self.init(value) }
    public static let upArrow: Self = "\u{f700}", downArrow: Self = "\u{f701}"
    public static let leftArrow: Self = "\u{f702}", rightArrow: Self = "\u{f703}"
    public static let escape: Self = "\u{1b}", delete: Self = "\u{8}", deleteForward: Self = "\u{f728}"
    public static let home: Self = "\u{f729}", end: Self = "\u{f72b}"
    public static let pageUp: Self = "\u{f72c}", pageDown: Self = "\u{f72d}"
    public static let clear: Self = "\u{f739}", tab: Self = "\t", space: Self = " ", `return`: Self = "\r"
}

public struct KeyboardShortcut: Hashable, Sendable {
    public struct Localization: Sendable {
        fileprivate let value: Int
        public static let automatic = Self(value: 0)
        public static let withoutMirroring = Self(value: 1)
        public static let custom = Self(value: 2)
    }
    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public var localization: Localization
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.init(key, modifiers: modifiers, localization: .automatic)
    }
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
    }
    public static let defaultAction = Self(.return, modifiers: [])
    public static let cancelAction = Self(.escape, modifiers: [])
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.modifiers == rhs.modifiers && lhs.localization.value == rhs.localization.value
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
        hasher.combine(localization.value)
    }
}

extension View {
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command,
                                 localization: KeyboardShortcut.Localization) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(Optional(shortcut))
    }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.keyboardShortcut, shortcut)) }
    }
}

extension Context {
    func installShortcut(on widget: UnsafeMutableRawPointer) {
        let shortcut = environment.keyboardShortcut
        qs_button_shortcut(host.window, widget, shortcut.map { String($0.key.character) } ?? "",
                           Int32(truncatingIfNeeded: shortcut?.modifiers.rawValue ?? 0),
                           shortcut?.localization.value == 0 ? 1 : 0)
    }
}
