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
    }
}

final class WindowSceneTests: XCTestCase {
    @MainActor func testSingletonActivationGroupMultiplicityAndDismissal() async throws {
        let app = ProbeApp(), probe = app.probe
        let windows = AppWindows(app)
        defer { windows.finish() }
        XCTAssertNotNil(windows.openFirst())
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
