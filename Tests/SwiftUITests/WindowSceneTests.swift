import QtBridge
import XCTest
@testable import SwiftUI

@MainActor private final class SceneProbe {
    var open: OpenWindowAction?
    var dismiss: DismissWindowAction?
    var panels = 0
    var groups = 0
    var closed = 0
    var multiple = false
    var documents: [Binding<Int?>] = []
    var drafts: [Binding<Int>] = []
    var defaults = 0
}
private struct ProbeContent: View {
    let key: String
    let probe: SceneProbe
    @Environment(\.openWindow) var open
    @Environment(\.dismissWindow) var dismiss
    @Environment(\.supportsMultipleWindows) var multiple
    var body: some View {
        Text(key).onAppear {
            probe.multiple = multiple
            switch key {
            case "root": probe.open = open
            case "panel": probe.panels += 1; probe.dismiss = dismiss
            default: probe.groups += 1
            }
        }.onDisappear { probe.closed += 1 }
    }
}
private struct ProbeApp: App {
    let probe: SceneProbe
    init() { probe = SceneProbe() }
    var body: some Scene {
        WindowGroup("Root", id: "root") { ProbeContent(key: "root", probe: probe) }
        Window(Text("Inspector"), id: "panel") { ProbeContent(key: "panel", probe: probe) }
            .defaultSize(width: 92, height: 64)
        WindowGroup(id: "document") { ProbeContent(key: "document", probe: probe) }
        WindowGroup(Text("Number"), id: "number", for: Int.self) { value in
            Text(String(describing: value.wrappedValue))
                .onAppear { probe.documents.append(value) }
                .onDisappear { probe.closed += 1 }
        }
        WindowGroup("Draft", id: "draft", for: Int.self) { value in
            Text(String(value.wrappedValue))
                .onAppear { probe.drafts.append(value) }
                .onDisappear { probe.closed += 1 }
        } defaultValue: {
            probe.defaults += 1
            return 100 + probe.defaults
        }
    }
}

private struct ResizableApp: App {
    var sizing = WindowResizability.contentSize
    init() {}
    var body: some Scene {
        Window("Resize", id: "size") {
            Color.white.frame(minWidth: 100, maxWidth: 250, minHeight: 60, maxHeight: 160)
        }
        .defaultSize(CGSize(width: 200, height: 100))
        .windowResizability(sizing)
    }
}

private struct LaunchApp: App {
    let probe = SceneProbe()
    var first = SceneLaunchBehavior.automatic
    var detail = SceneLaunchBehavior.automatic
    var extra = SceneLaunchBehavior.automatic
    var body: some Scene {
        WindowGroup(id: "root") { ProbeContent(key: "root", probe: probe) }
            .defaultLaunchBehavior(first)
        Window("Inspector", id: "detail") { ProbeContent(key: "panel", probe: probe) }
            .defaultLaunchBehavior(detail)
        Window("Extra", id: "extra") { ProbeContent(key: "extra", probe: probe) }
            .defaultLaunchBehavior(extra)
    }
}

private struct StackingApp: App {
    @State var level = WindowLevel.floating
    var body: some Scene {
        Window("Inspector", id: "inspector") {
            Button("Move behind") { level = .desktop }.accessibilityIdentifier("lower")
        }
        .windowLevel(level)
        .defaultLaunchBehavior(.presented)
        Window("Main", id: "main") { Text("Main") }
            .windowLevel(.normal)
            .defaultLaunchBehavior(.presented)
    }
}

final class WindowSceneTests: XCTestCase {
    @MainActor func testWindowLevelsApplyPerSceneAndUpdateLive() async throws {
        XCTAssertEqual(Set([WindowLevel.automatic, .normal, .desktop, .floating]).count, 4)
        let windows = AppWindows(StackingApp())
        defer { windows.finish() }
        let hosts = try XCTUnwrap(windows.launchWindows())
        XCTAssertEqual(hosts.map { qs_window_level($0.window) }, [QSFloatingWindow, QSNormalWindow])
        XCTAssertEqual(qs_click(hosts[0].window, "lower"), 1)
        qs_flush()
        XCTAssertEqual(hosts.map { qs_window_level($0.window) }, [QSDesktopWindow, QSNormalWindow])
    }

    @MainActor func testExplicitLaunchAndSuppressedWindows() async {
        var app = LaunchApp()
        app.detail = .presented
        app.extra = .presented
        let windows = AppWindows(app)
        defer { windows.finish() }
        XCTAssertEqual(windows.launchWindows()?.count, 2)
        XCTAssertNil(app.probe.open)
        XCTAssertEqual(app.probe.panels, 1)
        XCTAssertEqual(app.probe.groups, 1)

        var background = LaunchApp()
        background.first = .suppressed
        let suppressed = AppWindows(background)
        defer { suppressed.finish() }
        XCTAssertEqual(suppressed.launchWindows()?.count, 0)
        XCTAssertNil(background.probe.open)
    }

    @MainActor func testNativeWindowEnforcesContentSizeBounds() throws {
        func captureSize(_ host: SwiftUI.Host, width: Int, height: Int) throws -> CGSize {
            host.open(width: width, height: height)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertNotEqual(qs_capture(host.window, url.path), 0)
            let data = try Data(contentsOf: url)
            let scale = qs_window_scale(host.window)
            // The PNG IHDR stores its pixel dimensions as two big-endian integers.
            func dimension(_ offset: Int) -> CGFloat {
                CGFloat(data[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }) / scale
            }
            return CGSize(width: dimension(16), height: dimension(20))
        }
        for restrictMaximum in [true, false] {
            var app = ResizableApp()
            app.sizing = restrictMaximum ? .contentSize : .contentMinSize
            let windows = AppWindows(app)
            defer { windows.finish() }
            let host = try XCTUnwrap(windows.launchWindows()?.first)
            XCTAssertEqual(try captureSize(host, width: 40, height: 30), CGSize(width: 100, height: 60))
            XCTAssertEqual(try captureSize(host, width: 500, height: 400),
                           restrictMaximum ? CGSize(width: 250, height: 160) : CGSize(width: 500, height: 400))
        }
    }

    @MainActor func testPresentationValueBindingMatchingAndDefaults() async throws {
        let app = ProbeApp(), probe = app.probe
        let windows = AppWindows(app)
        defer { windows.finish() }
        _ = windows.launchWindows()
        let open = try XCTUnwrap(probe.open)
        open(value: 7)
        open(id: "number", value: 7)
        open(id: "number", value: "wrong type")
        XCTAssertEqual(probe.documents.count, 1)
        let first = try XCTUnwrap(probe.documents.first)
        XCTAssertEqual(first.wrappedValue, 7)
        first.wrappedValue = 8
        open(value: 8)
        open(value: 7)
        open(id: "number")
        XCTAssertEqual(probe.documents.map(\.wrappedValue), [8, 7, nil])

        open(id: "draft", value: 8)
        open(id: "draft")
        open(id: "draft", value: 101)
        XCTAssertEqual(probe.defaults, 1)
        XCTAssertEqual(probe.drafts.map(\.wrappedValue), [8, 101])
        open(id: "panel")
        let dismiss = try XCTUnwrap(probe.dismiss)
        dismiss(id: "number", value: 8)
        dismiss(value: 7)
        for _ in 0..<3 { qs_flush(); await Task.yield() }
        XCTAssertEqual(probe.closed, 2)
        open(id: "draft", value: 8)
        XCTAssertEqual(probe.drafts.count, 2)
    }

    @MainActor func testSingletonActivationGroupMultiplicityAndDismissal() async throws {
        let app = ProbeApp(), probe = app.probe
        let windows = AppWindows(app)
        defer { windows.finish() }
        XCTAssertNotNil(windows.launchWindows()?.first)
        let open = try XCTUnwrap(probe.open)
        XCTAssertTrue(probe.multiple)
        open(id: "panel")
        open(id: "panel")
        XCTAssertEqual(probe.panels, 1)
        open(id: "document")
        open(id: "document")
        XCTAssertEqual(probe.groups, 2)
        let dismiss = try XCTUnwrap(probe.dismiss)
        dismiss(id: "document")
        for _ in 0..<3 { qs_flush(); await Task.yield() }
        XCTAssertEqual(probe.closed, 2)
        dismiss()
        for _ in 0..<3 { qs_flush(); await Task.yield() }
        XCTAssertEqual(probe.closed, 3)
        open(id: "panel")
        XCTAssertEqual(probe.panels, 2)
    }
}
