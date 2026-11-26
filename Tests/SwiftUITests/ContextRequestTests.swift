import QtBridge
import XCTest
@testable @_spi(Qt) import SwiftUI

final class ContextRequestTests: XCTestCase {
    @MainActor func testSecondaryAndKeyboardRequestsUseTriggerCoordinates() async {
        var presses = 0, active = true
        var inner: [CGPoint] = [], outer: [CGPoint] = []
        let host = Host(title: "Context request") { context in
            Button("Open") { presses += 1 }
                .frame(width: 80, height: 40)
                .qtOnContextRequest(isEnabled: active) { inner.append($0) }
                .padding(10)
                .qtOnContextRequest { outer.append($0) }
                .resolve(context)
        }
        defer { host.close() }
        host.open(width: 100, height: 60)
        _ = qs_click_point(host.window, 50, 30)
        XCTAssertEqual(presses, 1)
        _ = qs_open_context_menu(host.window, 42, 27, 0)
        XCTAssertEqual(inner, [CGPoint(x: 32, y: 17)])
        XCTAssertTrue(outer.isEmpty)
        _ = qs_open_context_menu(host.window, 0, 0, 1)
        XCTAssertEqual(inner.last, CGPoint(x: 39, y: 19))
        XCTAssertEqual(presses, 1)
        active = false
        host.update()
        qs_flush()
        _ = qs_open_context_menu(host.window, 42, 27, 0)
        XCTAssertEqual(inner.count, 2)
        XCTAssertEqual(outer, [CGPoint(x: 42, y: 27)])
    }
}
