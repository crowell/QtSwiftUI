import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

final class SettingsTests: XCTestCase {
    @MainActor func testDataUsageControls() async throws {
        let model = SettingsModel()
        let window = try await ScreenWindow(SettingsPreview(calls: false, settings: model), width: 640, height: 567)
        defer { window.close() }
        try window.capture("data-usage-settings.png", directoryVariable: "QTSWIFTUI_SETTINGS_REFERENCE")
        for y in [143, 177, 211, 245] { try await window.click(578, y) }
        XCTAssertEqual(model.downloads, AutoDownloadAttachment(photos: false, videos: true, audio: true, documents: true))
        try await window.click(546, 344)
        try window.capture("settings-quality-menu.png", directoryVariable: "QTSWIFTUI_SETTINGS_REFERENCE")
        try await window.click(475, 374)
        XCTAssertEqual(model.quality, "high")
        try await window.click(540, 344)
        try await window.click(90, 410) // Dismiss the open menu without selecting an item.
        XCTAssertEqual(model.quality, "high")
        try await window.click(578, 143)
        XCTAssertTrue(model.downloads.photos)
    }

    @MainActor func testDownArrowOpensQualitySelect() async throws {
        let model = SettingsModel()
        let window = try await ScreenWindow(SettingsPreview(calls: false, settings: model), width: 640, height: 567, keyboard: true)
        defer { window.close() }
        let closed = window.pixel(447, 374)
        #if os(Linux)
        // Qt's starting focus depends on the desktop. Follow its native tab order.
        for _ in 0..<8 {
            _ = qs_send_key_sequence(window.host.window, "Down")
            if window.pixel(447, 374) != closed { break }
            _ = qs_tab(window.host.window)
        }
        #else
        // The quality select is the page's only key view. Give it first responder in
        // the test window without depending on the user's full keyboard access setting.
        let trigger = try XCTUnwrap(window.hosting.nextKeyView)
        XCTAssertTrue(window.window.makeFirstResponder(trigger))
        let arrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.function, .numericPad],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.window.windowNumber,
                context: nil, characters: arrow, charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 125))
            window.window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(50))
        #endif
        XCTAssertNotEqual(window.pixel(447, 374), closed, "Down Arrow should open the focused quality select")
        try await window.click(478, 374)
        XCTAssertEqual(model.quality, "high")
    }

    @MainActor func testCallsControls() async throws {
        let model = SettingsModel()
        let window = try await ScreenWindow(SettingsPreview(calls: true, settings: model), width: 640, height: 567)
        defer { window.close() }
        try window.capture("call-settings.png", directoryVariable: "QTSWIFTUI_SETTINGS_REFERENCE")
        for y in [109, 143, 435] { try await window.click(578, y) }
        XCTAssertFalse(model.notify)
        XCTAssertTrue(model.ring)
        XCTAssertTrue(model.relay)
        try await window.click(540, 240)
        try window.capture("settings-camera-menu.png", directoryVariable: "QTSWIFTUI_SETTINGS_REFERENCE")
        try await window.click(440, 270)
        XCTAssertEqual(model.camera, SettingsModel.cameras[1].deviceId)
        try await window.click(540, 284)
        try await window.click(450, 314)
        XCTAssertEqual(model.microphone, .specificDevice(SettingsModel.microphones.devices[0]))
        try await window.click(540, 328)
        try await window.click(450, 358)
        XCTAssertEqual(model.speaker, .specificDevice(SettingsModel.speakers.devices[2]))
    }
}
