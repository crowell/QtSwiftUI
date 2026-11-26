import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#endif

@MainActor @Observable private final class Commands {
    var inner = true
    var selections: [String] = []
    var previews = 0

    func preview() -> Text {
        previews += 1
        return Text("Preview")
    }
}

final class ContextMenuTests: XCTestCase {
    @MainActor func testNestedMenusAndOptionalFallback() async throws {
        struct Sample: View {
            let commands: Commands
            var body: some View {
                let inner = ContextMenu { Button("Inner") { commands.selections.append("Inner") } }
                VStack(spacing: 0) {
                    Color.blue.frame(height: 40).contextMenu(commands.inner ? inner : nil)
                    Color.green.frame(height: 40)
                }.contextMenu {
                    Button("Outer") { commands.selections.append("Outer") }
                } preview: { commands.preview() }
            }
        }
        let commands = Commands()
        let window = try await ScreenWindow(Sample(commands: commands), width: 140, height: 80)
        defer { window.close() }
        try await window.chooseContextAction("Inner", x: 60, y: 20)
        try await window.chooseContextAction("Outer", x: 60, y: 60)
        commands.inner = false
        try await window.settle()
        try await window.chooseContextAction("Outer", x: 60, y: 20)
        XCTAssertEqual(commands.selections, ["Inner", "Outer", "Outer"])
        XCTAssertEqual(commands.previews, 0)
    }

    #if os(Linux)
    @MainActor func testKeyboardContextRequestFromFocusedControl() async throws {
        var opened = 0, pressed = 0
        let view = Button("Target") { pressed += 1 }.contextMenu {
            Button("Unavailable") { XCTFail("Disabled item fired") }.disabled(true)
            Button("Command") { opened += 1 }
        }
        let window = try await ScreenWindow(view, width: 160, height: 70, keyboard: true)
        defer { window.close() }
        try await window.click(80, 35)
        XCTAssertEqual(pressed, 1)
        XCTAssertEqual(qs_open_context_menu(window.host.window, 0, 0, 1), 1)
        XCTAssertEqual(qs_popup_item_state(window.host.window, "Unavailable"), 0)
        _ = qs_send_key_sequence(window.host.window, "Return")
        try await window.settle()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(pressed, 1)
    }
    #endif
}
