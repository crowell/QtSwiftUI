import QtBridge
import XCTest
@testable import SwiftUI

@MainActor private final class SettingsProbe {
    var shown = 0
    var dismiss: DismissWindowAction?
}
private struct Preferences: View {
    let probe: SettingsProbe
    @Environment(\.dismissWindow) var dismiss
    var body: some View {
        Text("Preferences").frame(width: 200, height: 120)
            .onAppear { probe.shown += 1; probe.dismiss = dismiss }
    }
}
private struct ApplicationWithSettings: App {
    let probe = SettingsProbe()

    var body: some Scene {
        Settings { Preferences(probe: probe) }
        WindowGroup("Main") {
            SettingsLink { Text("Open preferences") }.accessibilityIdentifier("open")
            SettingsLink()
        }
    }
}

final class SettingsTests: XCTestCase {
    @MainActor func testSettingsMenuShortcutAndLinkShareTheWindow() async throws {
        let app = ApplicationWithSettings()
        let windows = AppWindows(app)
        defer { windows.finish() }
        let main = try XCTUnwrap(windows.launchWindows()?.first)
        qs_flush()
        XCTAssertEqual(app.probe.shown, 0)
        _ = qs_send_key_sequence(main.window, "Ctrl+,")
        XCTAssertEqual(app.probe.shown, 1)
        XCTAssertEqual(qs_click(main.window, "open"), 1)
        XCTAssertEqual(app.probe.shown, 1)
        app.probe.dismiss?()
        for _ in 0..<3 { qs_flush(); await Task.yield() }
        XCTAssertEqual(qs_click(main.window, "open"), 1)
        XCTAssertEqual(app.probe.shown, 2)
        app.probe.dismiss?()
        for _ in 0..<3 { qs_flush(); await Task.yield() }
        _ = qs_click_point(main.window, 16, 10)
        XCTAssertEqual(qs_click_popup_item(main.window, "Settings…"), 1)
        XCTAssertEqual(app.probe.shown, 3)
    }

    @MainActor func testLinkWithoutSettingsScene() {
        let host = Host(title: "No settings") { context in
            SettingsLink { Text("Preferences") }.accessibilityIdentifier("open").resolve(context)
        }
        defer { host.close() }
        host.open(width: 240, height: 90)
        XCTAssertEqual(qs_click(host.window, "open"), 0)
    }
}
