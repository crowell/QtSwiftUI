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

private nonisolated struct LeveledScene<Content: Scene>: SceneCollection {
    let content: Content
    let level: WindowLevel
    var body: Never { fatalError("Primitive scene modifier") }
    @MainActor var windows: [WindowScene] {
        content.sceneWindows.map { window in
            var result = window
            result.level = level
            return result
        }
    }
}

extension Scene {
    nonisolated public func windowLevel(_ level: WindowLevel) -> some Scene {
        LeveledScene(content: self, level: level)
    }
}
