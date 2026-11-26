import QtBridge
import XCTest
@testable import SwiftUI

final class AccessibilityActionsTests: XCTestCase {
    @MainActor func testDynamicButtonsAreInvokedOnTheirLabeledElement() async {
        var destinations = ["Calendar", "Photos"], events: [String] = []
        let host = Host(title: "Actions") { context in
            Text("A shared album")
                .accessibilityElement()
                .accessibilityLabel("Message")
                .accessibilityActions {
                    ForEach(destinations, id: \.self) { title in
                        Button(title) { events.append(title) }
                    }
                    Button("Unavailable") { events.append("disabled") }.disabled(true)
                }
                .resolve(context)
        }
        defer { host.close() }
        host.open(width: 200, height: 80)
        XCTAssertEqual(qs_accessible_element(host.window, "Message", 0, "Photos"), 1)
        XCTAssertEqual(qs_accessible_element(host.window, "Message", 0, "Unavailable"), 0)
        destinations = ["Maps"]
        host.update()
        qs_flush()
        XCTAssertEqual(qs_accessible_element(host.window, "Message", 0, "Photos"), 0)
        XCTAssertEqual(qs_accessible_element(host.window, "Message", 0, "Maps"), 1)
        XCTAssertEqual(events, ["Photos", "Maps"])
    }
}
