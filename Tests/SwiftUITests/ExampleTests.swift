import XCTest
import QtBridge
@testable import SwiftUI
@testable import Controls
@testable import Conversation

final class ExampleTests: XCTestCase {
    func testConversationSendSwitchAndSubmit() async {
        await MainActor.run {
            let host = Host(title: "Conversation") { Inbox().resolve($0) }
            defer { host.close() }
            host.open(width: 860, height: 520)
            XCTAssertEqual(qs_read_text(host.window, "message-count", "3 messages"), 1)
            XCTAssertEqual(qs_click(host.window, "send"), 0)
            XCTAssertEqual(qs_enter(host.window, "composer", "Hello from Qt"), 1)
            XCTAssertEqual(qs_mouse_click(host.window, "send"), 1)
            XCTAssertEqual(qs_read_text(host.window, "message-count", "4 messages"), 1)
            XCTAssertEqual(qs_mouse_click(host.window, "room-Rowan"), 1)
            XCTAssertEqual(qs_has_focus(host.window, "composer"), 1)
            XCTAssertEqual(qs_read_text(host.window, "message-count", "1 message"), 1)
            XCTAssertEqual(qs_enter(host.window, "composer", "A private reply"), 1)
            XCTAssertEqual(qs_key_return(host.window, "composer"), 1)
            XCTAssertEqual(qs_read_text(host.window, "message-count", "2 messages"), 1)
            XCTAssertEqual(qs_mouse_click(host.window, "room-Design group"), 1)
            XCTAssertEqual(qs_read_text(host.window, "message-count", "4 messages"), 1)
        }
    }
    func testPreferencesEditsAndConditionalControls() async {
        await MainActor.run {
            let host = Host(title: "Settings") { Settings().resolve($0) }
            defer { host.close() }
            host.open(width: 460, height: 360)
            XCTAssertEqual(qs_read_text(host.window, "volume-label", "65%"), 1)
            XCTAssertEqual(qs_click(host.window, "notifications"), 1)
            XCTAssertEqual(qs_read_text(host.window, "volume-label", "65%"), 0)
            XCTAssertEqual(qs_enter(host.window, "display-name", "Rowan"), 1)
            XCTAssertEqual(qs_mouse_click(host.window, "save"), 1)
            XCTAssertEqual(qs_read_text(host.window, "saved", "Saved for Rowan"), 1)
        }
    }
}
