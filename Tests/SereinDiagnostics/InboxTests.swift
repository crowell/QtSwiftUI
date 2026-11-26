import SwiftUI
import XCTest
@testable import CallDiagnostics

final class InboxTests: XCTestCase {
    @MainActor func testRailSelectionCollapseAndUnreadBadge() async throws {
        let model = InboxPreviewModel()
        let window = try await ScreenWindow(InboxPreview(model: model), width: 560, height: 520)
        defer { window.close() }
        try window.capture("inbox.png", directoryVariable: "QTSWIFTUI_INBOX_REFERENCE")
        XCTAssertEqual(model.selected, .calls)
        let badge = window.pixel(44, 99)
        XCTAssertGreaterThan(badge >> 16, (badge & 255) + 70)
        try await window.click(40, 66)
        XCTAssertEqual(model.selected, .chats)
        try await window.click(40, 490)
        XCTAssertEqual(model.selected, .settings)
        try await window.click(40, 22)
        XCTAssertTrue(model.collapsed)
        try await window.click(40, 22)
        XCTAssertFalse(model.collapsed)
        XCTAssertEqual(model.selected, .settings)
        try await window.click(40, 110)
        XCTAssertEqual(model.selected, .calls)
        try await window.click(193, 62)
        XCTAssertEqual(model.createdLink.dialog, .manage)
    }
}
