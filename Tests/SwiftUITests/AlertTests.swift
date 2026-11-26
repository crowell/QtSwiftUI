import QtBridge
import XCTest
@testable import SwiftUI

final class AlertTests: XCTestCase {
    @MainActor func testDefaultDismissalAndCancellation() async {
        var shown = false, accepted = 0, canceled = 0
        let binding = Binding(get: { shown }, set: { shown = $0 })
        let host = Host(title: "Participant") { context in
            Text("Participant").alert(isPresented: binding) {
                Alert(title: Text("Media keys"), message: Text("Waiting for keys"),
                      primaryButton: .destructive(Text("Remove")) { accepted += 1 },
                      secondaryButton: .cancel { canceled += 1 })
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 240, height: 160)
        XCTAssertEqual(qs_alert_response(host.window, "Media keys", "Waiting for keys", nil), 0)
        func present() {
            shown = true
            host.update()
            qs_flush()
            qs_flush()
        }
        present()
        XCTAssertEqual(qs_alert_response(host.window, "Media keys", "Waiting for keys", "Cancel"), 1)
        XCTAssertFalse(shown)
        XCTAssertEqual(canceled, 1)
        host.update()
        qs_flush()
        present()
        XCTAssertEqual(qs_alert_response(host.window, "Media keys", "Waiting for keys", "Remove"), 1)
        XCTAssertEqual(accepted, 1)
        XCTAssertFalse(shown)
    }

    @MainActor func testReplacingAnItemReplacesItsAlertAndDismissesTheCurrentItem() async {
        struct Item: Identifiable { let id: Int }
        var selected: Item? = Item(id: 1)
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let host = Host(title: "Items") { context in
            Color.white.alert(item: binding) { Alert(title: Text("Item \($0.id)")) }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 240, height: 160)
        qs_flush()
        XCTAssertEqual(qs_alert_response(host.window, "Item 1", "", nil), 1)
        selected = Item(id: 2)
        host.update()
        qs_flush()
        qs_flush()
        XCTAssertEqual(qs_alert_response(host.window, "Item 1", "", nil), 0)
        XCTAssertEqual(qs_alert_response(host.window, "Item 2", "", "OK"), 1)
        XCTAssertNil(selected)
    }
}
