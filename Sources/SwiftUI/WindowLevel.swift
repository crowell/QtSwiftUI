import QtBridge

public struct WindowLevel: Sendable, Hashable {
    private enum Level: Hashable, Sendable { case automatic, desktop, floating, normal }
    private let level: Level

    public static var automatic: Self { Self(level: .automatic) }
    public static var desktop: Self { Self(level: .desktop) }
    public static var floating: Self { Self(level: .floating) }
    public static var normal: Self { Self(level: .normal) }

    var native: QSWindowLevel {
        switch level {
        case .automatic, .normal: QSNormalWindow
        case .desktop: QSDesktopWindow
        case .floating: QSFloatingWindow
        }
    }
}

public struct WindowInteractionBehavior: Sendable {
    let enabled: Bool?
    public static let automatic = Self(enabled: nil)
    public static let enabled = Self(enabled: true)
    public static let disabled = Self(enabled: false)
}

extension Scene {
    nonisolated public func windowLevel(_ level: WindowLevel) -> some Scene {
        WindowPropertyScene(scene: self, key: \.level, value: level)
    }
    nonisolated public func windowBackgroundDragBehavior(_ behavior: WindowInteractionBehavior) -> some Scene {
        WindowPropertyScene(scene: self, key: \.backgroundDrag, value: behavior)
    }
}
