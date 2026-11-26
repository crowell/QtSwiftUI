import SwiftUI
import XCTest
@testable import CallDiagnostics

final class SharePickerTests: XCTestCase {
    @MainActor func testChooseScreenOrWindowAndCancel() async throws {
        var chosen: [String] = [], canceled = 0
        let view = ScreenSharePreview(onSelect: { chosen.append($0) }, onCancel: { canceled += 1 })
        let window = try await ScreenWindow(view, width: 840, height: 620)
        defer { window.close() }
        try window.capture("share-picker.png", directoryVariable: "QTSWIFTUI_SHARE_REFERENCE")
        try await window.click(711, 489)
        XCTAssertTrue(chosen.isEmpty)
        try await window.click(176, 230)
        try await window.click(711, 489)
        XCTAssertEqual(chosen, ["SOURCE_SCREEN"])
        try await window.click(339, 392)
        try window.capture("share-picker-selected.png", directoryVariable: "QTSWIFTUI_SHARE_REFERENCE")
        try await window.click(711, 489)
        XCTAssertEqual(chosen.last, "SOURCE_WINDOW_2")
        try await window.click(502, 393)
        try await window.click(711, 489)
        XCTAssertEqual(chosen.last, "SOURCE_WINDOW_BROKEN")
        try await window.click(617, 489)
        try await window.click(750, 129)
        XCTAssertEqual(canceled, 2)
        XCTAssertEqual(chosen.count, 3)
    }
}
