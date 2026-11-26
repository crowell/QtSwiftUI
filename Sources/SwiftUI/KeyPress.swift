public struct KeyPress: Sendable, CustomDebugStringConvertible {
    public struct Phases: OptionSet, Sendable, CustomDebugStringConvertible {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let down = Self(rawValue: 1), `repeat` = Self(rawValue: 2), up = Self(rawValue: 4)
        public static let all = Self(rawValue: .max)
        public var debugDescription: String {
            if self == .all { return ".all" }
            let names = [(Self.down, ".down"), (.repeat, ".repeat"), (.up, ".up")]
                .compactMap { contains($0.0) ? $0.1 : nil }
            return names.count == 1 ? names[0] : "[" + names.joined(separator: ", ") + "]"
        }
    }
    public enum Result: Hashable, Sendable { case handled, ignored }
    public let phase: Phases
    public let key: KeyEquivalent
    public let characters: String
    public let modifiers: EventModifiers
    public var debugDescription: String { "KeyPress(\(phase.debugDescription), \(characters.debugDescription))" }
}

struct KeyPressHandler {
    let path: [Part]
    let phases: KeyPress.Phases
    let action: (KeyPress) -> KeyPress.Result
}

@MainActor final class WindowKeyPresses {
    private var handlers: [Int32: [KeyPressHandler]] = [:]
    private var held: [KeyEquivalent: (owner: Int32, path: [Part])] = [:]
    func install(_ list: [KeyPressHandler], for id: Int32) { handlers[id] = list.isEmpty ? nil : list }
    func reset() { handlers.removeAll(); held.removeAll() }
    func dispatch(_ key: KeyPress, to owner: Int32) -> KeyPress.Result {
        if key.phase == .down { held[key.key] = nil }
        let route = held[key.key]
        defer { if key.phase == .up { held[key.key] = nil } }
        for handler in handlers[owner] ?? [] {
            if handler.phases.contains(key.phase), handler.action(key) == .handled {
                if key.phase == .down { held[key.key] = (owner, handler.path) }
                return .handled
            }
            // A handler that claimed key-down also bounds the route for repeat and key-up.
            if route?.owner == owner, route?.path == handler.path { return .handled }
        }
        return .ignored
    }
}

extension View {
    nonisolated public func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View {
        onKeyPress(key, phases: [.down, .repeat]) { _ in action() }
    }
    nonisolated public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        onKeyPress(keys: [key], phases: phases, action: action)
    }
    nonisolated public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        onKeyPress(phases: phases) { keys.contains($0.key) ? action($0) : .ignored }
    }
    nonisolated public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        onKeyPress(phases: phases) { press in
            press.characters.unicodeScalars.allSatisfy(characters.contains) ? action(press) : .ignored
        }
    }
    nonisolated public func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                           action: @escaping (KeyPress) -> KeyPress.Result) -> some View {
        KeyPressSubscription(content: self, phases: phases, action: action)
    }
}

private nonisolated struct KeyPressSubscription<Content: View>: View {
    let content: Content
    let phases: KeyPress.Phases
    let action: (KeyPress) -> KeyPress.Result
    @MainActor var body: some View {
        Transform(content: content) { view, context in
            let handler = KeyPressHandler(path: context.path, phases: phases, action: action)
            return view.resolve(context.with(\.keyPressHandlers, context.environment.keyPressHandlers + [handler]))
        }
    }
}
