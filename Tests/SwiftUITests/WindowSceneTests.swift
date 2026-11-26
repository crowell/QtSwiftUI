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

final class WindowSceneTests: XCTestCase {
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
            let host = try XCTUnwrap(windows.openFirst())
            XCTAssertEqual(try captureSize(host, width: 40, height: 30), CGSize(width: 100, height: 60))
            XCTAssertEqual(try captureSize(host, width: 500, height: 400),
                           restrictMaximum ? CGSize(width: 250, height: 160) : CGSize(width: 500, height: 400))
        }
    }

    @MainActor func testPresentationValueBindingMatchingAndDefaults() async throws {
        let app = ProbeApp(), probe = app.probe
        let windows = AppWindows(app)
        defer { windows.finish() }
        _ = windows.openFirst()
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
