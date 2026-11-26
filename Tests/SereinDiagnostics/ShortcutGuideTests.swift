import SwiftUI
import XCTest
@testable import CallDiagnostics

final class ShortcutGuideTests: XCTestCase {
    @MainActor func testLinuxLabelsAndCloseControl() async throws {
        var closed = false
        let guide = ShortcutGuide(platform: "linux") { closed = true }
        let mac = ShortcutGuide(platform: "darwin", close: {})
        XCTAssertEqual(guide.label(.commandOrCtrl).0, "Ctrl")
        XCTAssertNotEqual(mac.label(.commandOrCtrl).0, guide.label(.commandOrCtrl).0)
        let window = try await ScreenWindow(guide, width: 600, height: 400, keyboard: true)
        defer { window.close() }
        try await window.scroll(toEnd: true)
        try await window.click(571, 29)
        XCTAssertTrue(closed)
    }
}
