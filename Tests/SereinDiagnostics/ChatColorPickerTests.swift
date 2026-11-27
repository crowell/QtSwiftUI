import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

final class ChatColorPickerTests: XCTestCase {
    @MainActor func testSelectingAndEditingColors() async throws {
        let window = try await ScreenWindow(ChatColorPickerPreview(), width: 780, height: 720)
        defer { window.close() }
        try window.capture("picker-initial.png", directoryVariable: "QTSWIFTUI_PICKER_REFERENCE")
        let original = window.pixel(500, 62)
        let crimson = window.pixel(162, 327), orange = window.pixel(390, 479)
        XCTAssertNotEqual(original, crimson)
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        XCTAssertNotEqual(defaultColor, original)
        try await window.click(162, 327)
        XCTAssertEqual(window.pixel(500, 62), crimson, "The outgoing bubble adopts the preset")
        try await window.click(390, 479)
        XCTAssertEqual(window.pixel(500, 62), orange, "The outgoing bubble adopts the custom color")
        try await window.click(390, 479)
        try window.capture("picker-menu.png", directoryVariable: "QTSWIFTUI_PICKER_REFERENCE")
        try await window.click(390, 528)
        XCTAssertEqual(window.pixel(345, 260), orange, "Edit opens the selected custom color")
        try await window.click(390, 494) // Hue slider midpoint
        let edited = window.pixel(345, 260)
        XCTAssertNotEqual(edited, orange)
        try await window.click(546, 580) // Save
        XCTAssertEqual(window.pixel(500, 62), edited, "Saving updates the picker preview")
        XCTAssertEqual(window.pixel(390, 490), edited, "Saving updates the original swatch")
    }

    @MainActor func testResetAndCancel() async throws {
        let window = try await ScreenWindow(ChatColorPickerPreview(), width: 780, height: 720)
        defer { window.close() }
        let background = window.pixel(100, 695)
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        try await window.click(162, 327)
        try await window.click(100, 566) // Reset this chat
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(694, 479) // Add a custom color
        XCTAssertNotEqual(window.pixel(100, 695), background, "The editor dims the picker background")
        try await window.click(476, 580) // Cancel
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(162, 327)
        try await window.click(100, 600) // Reset all chats
        try await window.click(455, 398) // Confirm the reset
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(162, 327)
        try await window.click(100, 600)
        XCTAssertTrue(window.isVisible)
        try await window.click(323, 398) // Cancel keeps the selected color and its window.
        XCTAssertTrue(window.isVisible)
        XCTAssertNotEqual(window.pixel(500, 62), defaultColor)
    }

    @MainActor func testAddingDuplicatingAndRemoving() async throws {
        let window = try await ScreenWindow(ChatColorPickerPreview(), width: 780, height: 720)
        defer { window.close() }
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        try await window.click(694, 479)
        try await window.click(546, 580)
        let added = window.pixel(500, 62)
        XCTAssertEqual(window.pixel(694, 490), added, "The new color occupies the old add button")
        try await window.click(694, 479)
        try await window.click(680, 560) // Duplicate opens an editor initialized with this color.
        XCTAssertEqual(window.pixel(345, 260), added)
        try await window.click(546, 580)
        XCTAssertEqual(window.pixel(86, 566), added, "The duplicate wraps onto the next row")
        try await window.click(86, 555)
        try await window.click(100, 665) // Delete the duplicate
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        XCTAssertEqual(window.pixel(694, 490), added, "Deleting the duplicate preserves the original")
    }
}
