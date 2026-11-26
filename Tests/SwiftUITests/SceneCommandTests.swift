import QtBridge
import XCTest
@testable import SwiftUI

final class SceneCommandTests: XCTestCase {
    private struct Editing: Commands {
        let enabled: Bool
        let perform: () -> Void
        var body: some Commands {
            CommandMenu(Text("Edit")) {
                Menu("Selection") { Button("Copy selection", action: perform) }
                Divider()
                Button("Rename", action: perform)
                    .keyboardShortcut("r", modifiers: .control)
                    .disabled(!enabled)
            }
        }
    }

    @MainActor func testMenuEditsAndKeyboardDispatch() async {
        var calls = 0, enabled = true, showEdit = true
        let host = Host(title: "Commands") { context in
            WindowGroup { Color.white }
                .commands {
                    CommandMenu("File") { Button("New") { calls += 10 } }
                    if showEdit { Editing(enabled: enabled) { calls += 1 } }
                }
                .defaultSize(width: 240, height: 120)
                .windowScene.windowContent(in: context)
        }
        defer { host.close() }
        host.open(width: 240, height: 120)
        qs_flush()
        _ = qs_click_point(host.window, 16, 10)
        XCTAssertGreaterThan(qs_popup_item_state(host.window, "New"), 0)
        XCTAssertEqual(qs_click_popup_item(host.window, "New"), 1)
        XCTAssertEqual(calls, 10)
        _ = qs_send_key_sequence(host.window, "Ctrl+R")
        XCTAssertEqual(calls, 11)
        enabled = false
        host.update()
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Ctrl+R")
        XCTAssertEqual(calls, 11)
        showEdit = false
        host.update()
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Ctrl+R")
        XCTAssertEqual(calls, 11)
        _ = qs_click_point(host.window, 16, 10)
        XCTAssertEqual(qs_click_popup_item(host.window, "New"), 1)
        XCTAssertEqual(calls, 21)
    }
}
