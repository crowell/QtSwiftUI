import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

extension ScreenWindow {
    @MainActor func chooseContextAction(_ title: String, x: Int, y: Int, capture: String? = nil) async throws {
        #if os(Linux)
        XCTAssertEqual(qs_open_context_menu(host.window, Int32(x), Int32(y), 0), 1)
        XCTAssertEqual(qs_popup_item_state(host.window, title), 1)
        if let capture { try self.capture(capture, directoryVariable: "QTSWIFTUI_STICKER_REFERENCE") }
        XCTAssertEqual(qs_click_popup_item(host.window, title), 1)
        #else
        // Ask the hosting view for the native menu at the click and dispatch its AppKit action.
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: x, y: height - y),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(hosting.menu(for: event))
        menu.update()
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == title && $0.isEnabled })
        menu.performActionForItem(at: index)
        #endif
        try await settle()
    }
}

final class StickerTests: XCTestCase {
    @MainActor func testInstallAndUninstallSharedPack() async throws {
        let model = StickerPreviewModel()
        let window = try await ScreenWindow(StickerPreview(model: model), width: 600, height: 460, keyboard: true)
        defer { window.close() }
        let id = "received-pack-1"
        func status() -> StickerPack.Status? { model.packs.first(where: { $0.id == id })?.status }
        func choose(_ title: String) async throws {
            try await window.chooseContextAction(title, x: 130, y: 292, capture: title == "Add" ? "stickers-context-menu.png" : nil)
        }
        try window.capture("stickers.png", directoryVariable: "QTSWIFTUI_STICKER_REFERENCE")
        XCTAssertEqual(status(), .downloaded)
        try await choose("Add")
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(status(), .installed)
        try await choose("Remove")
        XCTAssertEqual(status(), .installed)
        try window.capture("sticker-uninstall.png", directoryVariable: "QTSWIFTUI_STICKER_REFERENCE")
        try await window.click(234, 264)
        XCTAssertEqual(status(), .installed)
        try await choose("Remove")
        try await window.click(367, 264)
        XCTAssertEqual(status(), .downloaded)
    }

    @MainActor func testClickPackAndInstallFromPreview() async throws {
        let model = StickerPreviewModel()
        let window = try await ScreenWindow(StickerPreview(model: model), width: 600, height: 460)
        defer { window.close() }
        let id = "received-pack-1"
        try await window.click(130, 292)
        XCTAssertEqual(model.selectedID, id)
        try window.capture("sticker-preview.png", directoryVariable: "QTSWIFTUI_STICKER_REFERENCE")
        try await window.click(432, 397)
        XCTAssertEqual(model.packs.first(where: { $0.id == id })?.status, .installed)
    }
}
