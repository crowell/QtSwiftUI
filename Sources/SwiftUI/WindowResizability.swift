import Synchronization

public struct WindowResizability: Sendable {
    let restrictMaximum: Bool
    private static let modes = Mutex((automatic: Self(restrictMaximum: false),
                                      minimum: Self(restrictMaximum: false),
                                      content: Self(restrictMaximum: true)))
    public static var automatic: Self {
        get { modes.withLock { $0.automatic } }
        set { modes.withLock { $0.automatic = newValue } }
    }
    public static var contentMinSize: Self {
        get { modes.withLock { $0.minimum } }
        set { modes.withLock { $0.minimum = newValue } }
    }
    public static var contentSize: Self {
        get { modes.withLock { $0.content } }
        set { modes.withLock { $0.content = newValue } }
    }
}

private nonisolated struct ResizableScene<Content: Scene>: SceneCollection {
    let content: Content
    let resizability: WindowResizability
    var body: Never { fatalError("Primitive scene modifier") }
    @MainActor var windows: [WindowScene] {
        content.sceneWindows.map { window in
            var result = window
            result.resizability = resizability
            return result
        }
    }
}
extension Scene {
    nonisolated public func windowResizability(_ resizability: WindowResizability) -> some Scene {
        ResizableScene(content: self, resizability: resizability)
    }
}
