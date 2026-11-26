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
extension App {
    public static func main() {
        let windows = AppWindows(Self())
        guard let launched = windows.launchWindows() else { windows.finish(); return }
        let status = qs_run(launched.first?.window, getenv("QTSWIFTUI_SCREENSHOT")) {
            _ = RunLoop.main.run(mode: .default, before: Date())
        }
        windows.finish()
        if status != 0 { exit(status) }
    }
}
