import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

final class ChatFolderTests: XCTestCase {
    @MainActor func testAddSuggestionAndOpenFolder() async throws {
        let model = ChatFoldersModel()
        let window = try await ScreenWindow(ChatFoldersPreview(model: model), width: 640, height: 730)
        defer { window.close() }
        try await window.click(585, 413)
        XCTAssertEqual(model.folders.last?.preset, .unreadChats)
        try await window.click(145, 243)
        XCTAssertEqual(model.editID, "ferry")
    }

    #if os(Linux)
    @MainActor func testSystemPointerDragWhenRunningOnX11() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QTSWIFTUI_X11_DRAG"] == "1")
        let model = ChatFoldersModel()
        let window = try await ScreenWindow(ChatFoldersPreview(model: model), width: 640, height: 730)
        defer { window.close() }
        let pointer = Process()
        pointer.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        pointer.arguments = ["search", "--onlyvisible", "--name", "^Serein$", "mousemove", "--window", "%@", "115", "295",
                             "mousedown", "1", "sleep", "0.15", "mousemove", "--window", "%@", "115", "277", "sleep", "0.15",
                             "mousemove", "--window", "%@", "115", "242", "sleep", "0.2", "mouseup", "1"]
        try pointer.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while pointer.isRunning && ContinuousClock.now < deadline { try await window.settle() }
        if pointer.isRunning { pointer.terminate() }
        pointer.waitUntilExit()
        XCTAssertEqual(pointer.terminationStatus, 0)
        try await window.settle()
        XCTAssertEqual(model.folders.sorted { $0.position < $1.position }.map(\.id), ["all", "family", "ferry"])
        XCTAssertFalse(model.editing)
    }

    @MainActor func testReorderAndSecondaryClickOnAnEditableRow() async throws {
        let model = ChatFoldersModel()
        let window = try await ScreenWindow(ChatFoldersPreview(model: model), width: 640, height: 730)
        defer { window.close() }
        XCTAssertEqual(qs_transfer_between(window.host.window, 110, 292, 110, 243), 1)
        try await window.settle()
        XCTAssertEqual(model.folders.sorted { $0.position < $1.position }.map(\.id), ["all", "family", "ferry"])
        _ = qs_open_context_menu(window.host.window, 140, 243, 0)
        try await window.settle()
        XCTAssertFalse(model.editing)
        try window.capture("chat-folder-menu.png", directoryVariable: "QTSWIFTUI_FOLDER_REFERENCE")
        try await window.click(213, 259)
        XCTAssertEqual(model.editID, "family")
    }
    #endif
}
