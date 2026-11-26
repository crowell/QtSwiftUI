import QtBridge
import XCTest
@testable import SwiftUI

private struct CapsuleHitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 80, height: 40).background(Color.black).contentShape(Capsule())
    }
}

private struct FocusTargets: View {
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Button("Move focus") { focused = true }.accessibilityIdentifier("move")
            Text("Keyboard target").focusable(interactions: .edit).focusEffectDisabled()
                .focused($focused).accessibilityIdentifier("target")
            Text(focused ? "Focused" : "Idle").accessibilityIdentifier("status")
        }
    }
}

final class FocusInteractionTests: XCTestCase {
    @MainActor func testButtonUsesLabelPathForMouseOnly() async {
        var clicks = 0
        let host = Host(title: "Hit shape") { ctx in
            Button("Close") { clicks += 1 }.buttonStyle(CapsuleHitStyle()).resolve(ctx)
        }
        defer { host.close() }
        host.open(width: 80, height: 40)
        XCTAssertEqual(qs_pixel(host.window, 1, 1), 0xff000000)
        XCTAssertEqual(qs_click_point(host.window, 1, 1), 1)
        XCTAssertEqual(clicks, 0)
        XCTAssertEqual(qs_click_point(host.window, 40, 20), 1)
        XCTAssertEqual(clicks, 1)
    }

    @MainActor func testFocusableTextReceivesAndReleasesKeyboardFocus() async {
        let host = Host(title: "Focus") { FocusTargets().resolve($0) }
        defer { host.close() }
        host.open(width: 180, height: 120)
        XCTAssertEqual(qs_click(host.window, "move"), 1)
        XCTAssertEqual(qs_has_focus(host.window, "target"), 1)
        XCTAssertEqual(qs_read_text(host.window, "status", "Focused"), 1)
        XCTAssertEqual(qs_tab(host.window), 1)
        XCTAssertEqual(qs_read_text(host.window, "status", "Idle"), 1)
    }
}
