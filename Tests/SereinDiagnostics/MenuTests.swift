import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

#if !os(Linux)
@MainActor private final class MenuSelection: NSObject {
    let title: String
    let finished = XCTestExpectation(description: "AppKit tracked the menu selection")
    var handled = false
    init(_ title: String) { self.title = title }

    @objc func beganTracking(_ note: Notification) {
        guard let menu = note.object as? NSMenu else { return }
        perform(#selector(selectItem(_:)), with: menu, afterDelay: 0.1, inModes: [.common, .eventTracking, .default])
    }

    @objc func selectItem(_ menu: NSMenu) {
        let index = menu.indexOfItem(withTitle: title)
        if index >= 0 && menu.items[index].isEnabled {
            handled = true
            menu.performActionForItem(at: index)
        }
        menu.cancelTrackingWithoutAnimation()
        finished.fulfill()
    }
}

extension ScreenWindow {
    @MainActor func choose(_ title: String, x: Int, y: Int) async throws {
        let selection = MenuSelection(title)
        NotificationCenter.default.addObserver(selection, selector: #selector(MenuSelection.beganTracking(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(selection) }
        try await click(x, y)
        let result = await XCTWaiter.fulfillment(of: [selection.finished], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(selection.handled, "Expected the native menu to offer " + title)
    }
}
#endif

#if os(Linux)
@MainActor @Observable private final class DrinkSelection {
    var options = ["Tea", "Coffee"]
    var checked = false
    var picked = ""
}
#endif

final class MenuTests: XCTestCase {
    #if os(Linux)
    @MainActor func testNativeMenuUpdatesActionsAndCheckmarks() async throws {
        struct Options: View {
            var selection: DrinkSelection
            var body: some View {
                Menu("Drinks") {
                    Button("Unavailable") { selection.picked = "unavailable" }.disabled(true)
                    Toggle("With milk", isOn: Binding(get: { selection.checked }, set: { selection.checked = $0 }))
                    Divider()
                    Menu("Options") {
                        ForEach(selection.options, id: \.self) { title in Button(title) { selection.picked = title } }
                    }
                }.accessibilityLabel("Drinks")
            }
        }
        let model = DrinkSelection()
        let window = try await ScreenWindow(Options(selection: model), width: 160, height: 60)
        defer { window.close() }
        let host = window.host.window
        XCTAssertEqual(qs_accessible_element(host, "Drinks", -1, "ShowMenu"), 1)
        XCTAssertEqual(qs_popup_item_state(host, "Unavailable"), 0)
        XCTAssertEqual(qs_click_popup_item(host, "Unavailable"), 0)
        XCTAssertEqual(qs_popup_item_state(host, "With milk"), 1)
        XCTAssertEqual(qs_click_popup_item(host, "With milk"), 1)
        try await window.settle()
        XCTAssertTrue(model.checked)
        try await window.click(80, 30)
        XCTAssertEqual(qs_popup_item_state(host, "With milk"), 3)
        XCTAssertEqual(qs_click_popup_item(host, "Options"), 1)
        _ = qs_send_key_sequence(host, "Right")
        try await window.settle()
        XCTAssertEqual(qs_popup_item_state(host, "Coffee"), 1)
        model.options = ["Coffee", "Tea & lime"]
        try await window.settle()
        XCTAssertEqual(qs_popup_item_state(host, "Tea"), -1)
        XCTAssertEqual(qs_click_popup_item(host, "Tea & lime"), 1)
        try await window.settle()
        XCTAssertEqual(model.picked, "Tea & lime")
        _ = qs_send_key_sequence(host, "Down")
        XCTAssertEqual(qs_popup_item_state(host, "With milk"), 3)
        _ = qs_send_key_sequence(host, "Escape")
        XCTAssertEqual(qs_popup_item_state(host, "With milk"), -1)
    }
    #endif

    @MainActor func testDisappearingMessageTimer() async throws {
        var submitted: [Int] = [], closes = 0
        let view = AxoBaseDialog.Host {
            DisappearingTimeDialog(initialValue: 45 * 60, onSubmit: { submitted.append($0) }, onClose: { closes += 1 })
        }.background(AxoColor.surfacePrimary)
        let window = try await ScreenWindow(view, width: 520, height: 440)
        defer { window.close() }
        try window.capture("disappearing-timer.png", directoryVariable: "QTSWIFTUI_TIMER_REFERENCE")
        #if os(Linux)
        try await window.click(330, 240)
        XCTAssertEqual(qs_popup_item_state(window.host.window, "Weeks"), 1)
        try window.capture("disappearing-timer-units.png", directoryVariable: "QTSWIFTUI_TIMER_REFERENCE")
        XCTAssertEqual(qs_click_popup_item(window.host.window, "Weeks"), 1)
        try await window.settle()
        #else
        try await window.choose("Weeks", x: 330, y: 240)
        #endif
        try await window.click(333, 287)
        XCTAssertEqual(submitted, [4 * 7 * 86_400])
        XCTAssertEqual(closes, 1)
        #if os(Linux)
        try await window.click(185, 240)
        XCTAssertEqual(qs_popup_item_state(window.host.window, "5"), -1)
        XCTAssertEqual(qs_click_popup_item(window.host.window, "2"), 1)
        try await window.settle()
        #else
        try await window.choose("2", x: 185, y: 240)
        #endif
        try await window.click(333, 287)
        XCTAssertEqual(submitted.last, 2 * 7 * 86_400)
        try await window.click(184, 287)
        XCTAssertEqual(closes, 3)
        XCTAssertEqual(submitted.count, 2)
    }
}
