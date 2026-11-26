import QtBridge
import Glibc

@MainActor public protocol App {
    associatedtype Body: Scene
    init()
    @SceneBuilder var body: Body { get }
}
@MainActor public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
}
extension Never: Scene {}
@resultBuilder public enum SceneBuilder {
    public static func buildBlock<S: Scene>(_ scene: S) -> S { scene }
}
@MainActor private protocol WindowScene {
    var title: String { get }
    var size: CGSize? { get }
    func content(in context: Context) -> [Element]
}
public struct WindowGroup<Content: View>: Scene, WindowScene {
    let title: String
    var size: CGSize?
    let make: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { title = ""; make = content }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) { self.title = String(title); make = content }
    public var body: Never { fatalError("WindowGroup is a primitive scene") }
    func content(in context: Context) -> [Element] { make().resolve(context) }
}
private struct SizedScene<S: Scene>: Scene, WindowScene {
    let scene: S, size: CGSize?
    var title: String { scene.windowScene.title }
    var body: Never { fatalError("SizedScene is a primitive scene") }
    func content(in context: Context) -> [Element] { scene.windowScene.content(in: context) }
}
extension Scene {
    fileprivate var windowScene: any WindowScene {
        if let window = self as? any WindowScene { return window }
        return body.windowScene
    }
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        SizedScene(scene: self, size: CGSize(width: width, height: height))
    }
}
extension App {
    public static func main() {
        let app = Self()
        let scene = app.body.windowScene
        let host = Host(title: scene.title) { context in
            context.preparing(app).body.windowScene.content(in: context)
        }
        let size = scene.size ?? CGSize(width: 640, height: 480)
        host.open(width: Int(size.width), height: Int(size.height))
        let status = qs_run(host.window, getenv("QTSWIFTUI_SCREENSHOT")) {
            _ = RunLoop.main.run(mode: .default, before: Date())
        }
        host.close()
        if status != 0 { exit(status) }
    }
}
