public struct SceneLaunchBehavior: Sendable {
    enum Mode { case automatic, presented, suppressed }
    let mode: Mode
    public static let automatic = Self(mode: .automatic)
    public static let presented = Self(mode: .presented)
    public static let suppressed = Self(mode: .suppressed)
}

private nonisolated struct LaunchScene<Content: Scene>: SceneCollection {
    let content: Content
    let behavior: SceneLaunchBehavior
    var body: Never { fatalError("Primitive scene modifier") }

    @MainActor var windows: [WindowScene] {
        content.sceneWindows.map { window in
            var result = window
            result.launchBehavior = behavior
            return result
        }
    }
}

extension Scene {
    nonisolated public func defaultLaunchBehavior(_ behavior: SceneLaunchBehavior) -> some Scene {
        LaunchScene(content: self, behavior: behavior)
    }
}
