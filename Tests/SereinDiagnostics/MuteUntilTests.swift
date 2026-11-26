import SwiftUI
import XCTest
@testable import CallDiagnostics

final class MuteUntilTests: XCTestCase {
    @MainActor func testChooseFutureDayHourMinuteAndPeriod() async throws {
        var submitted: Date?
        let window = try await ScreenWindow(MuteUntilPreview(submit: { submitted = $0 }), width: 640, height: 600, keyboard: true)
        defer { window.close() }
        try await window.click(313, 284)
        try await window.settlePopover()
        try await window.clickPopover(37, 97) // November 1 precedes the minimum date.
        XCTAssertNotNil(window.popoverFrame)
        try await window.clickPopover(258, 32)
        try await window.clickPopover(181, 97) // Thursday, December 3
        XCTAssertNil(window.popoverFrame)

        try await window.click(437, 284)
        try await window.settlePopover()
        try await window.clickPopover(40, 124)  // 9
        try await window.clickPopover(88, 109)  // 02
        try await window.clickPopover(136, 72)  // PM
        try window.capturePopover("mute-until-time.png", directoryVariable: "QTSWIFTUI_MUTE_REFERENCE")
        try await window.escapePopover()
        try await window.click(436, 354)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MuteUntilPreview.zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(submitted))
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 12, 3, 21, 2])
    }

    @MainActor func testOpenSereinCalendarAndTimeColumns() async throws {
        var submitted: [Date] = []
        var canceled = 0
        let view = MuteUntilPreview(submit: { submitted.append($0) }, close: { canceled += 1 })
        let window = try await ScreenWindow(view, width: 640, height: 600, keyboard: true)
        defer { window.close() }
        try await window.click(313, 284)
        try await window.settlePopover()
        XCTAssertNotNil(window.popoverFrame)
        try window.capturePopover("mute-until-calendar.png", directoryVariable: "QTSWIFTUI_MUTE_REFERENCE")
        try await window.escapePopover()
        XCTAssertNil(window.popoverFrame)
        try await window.click(437, 284)
        try await window.settlePopover()
        XCTAssertNotNil(window.popoverFrame)
        try await window.escapePopover()
        try await window.click(436, 354)
        let date = try XCTUnwrap(submitted.first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MuteUntilPreview.zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 11, 5, 8, 0])
        try await window.click(367, 354)
        XCTAssertEqual(canceled, 1)
    }
}
