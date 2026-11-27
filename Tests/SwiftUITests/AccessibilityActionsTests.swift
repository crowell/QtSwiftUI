import QtBridge
import XCTest
@testable import SwiftUI

final class AccessibilityActionsTests: XCTestCase {
    @MainActor func testDesktopRolesAndToggleActionsFollowViewUpdates() async {
        var checked = false
        let host = Host(title: "Accessibility traits") { context in
            VStack {
                HStack { Text("Chats"); Text("Calls") }
                    .accessibilityAddTraits(.isTabBar)
                    .accessibilityLabel("Sections")
                Text("Export these messages").accessibilityAddTraits(.isStaticText)
                Button("Include media") { checked.toggle() }
                    .accessibilityAddTraits(checked ? [.isToggle, .isSelected] : .isToggle)
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 300, height: 150)
        qs_flush()
        XCTAssertEqual(qs_has_accessible_role(host.window, "Sections", "PageTabList"), 1)
        XCTAssertEqual(qs_has_accessible_role(host.window, "Export these messages", "StaticText"), 1)
        XCTAssertEqual(qs_has_accessible_role(host.window, "Include media", "CheckBox"), 1)
        XCTAssertEqual(qs_accessible_checked(host.window, "Include media"), 0)
        XCTAssertEqual(qs_accessible_element(host.window, "Include media", -1, "Toggle"), 1)
        host.update()
        qs_flush()
        XCTAssertTrue(checked)
        XCTAssertEqual(qs_accessible_checked(host.window, "Include media"), 1)
    }

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
