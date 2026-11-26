import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

final class CallsTabTests: XCTestCase {
    @MainActor func testResizeSelectReadAndCreateLink() async throws {
        let model = CallsPreviewModel()
        let window = try await ScreenWindow(CallsTabPreview(model: model), width: 760, height: 520)
        defer { window.close() }
        try window.capture("calls-tab.png", directoryVariable: "QTSWIFTUI_CALLS_REFERENCE")
        #if os(Linux)
        XCTAssertEqual(qs_has_pointer_style(window.host.window, 323, 242, QSPointerColumn), 1)
        XCTAssertEqual(qs_has_pointer_style(window.host.window, 335, 242, QSPointerColumn), 0)
        #endif
        try await window.drag(from: .init(x: 323, y: 242), to: .init(x: 365, y: 242))
        XCTAssertEqual(model.width, 362, accuracy: 1)
        try await window.drag(from: .init(x: 365, y: 242), to: .init(x: 213, y: 242))
        XCTAssertEqual(model.width, 280)
        #if os(Linux)
        XCTAssertEqual(qs_direct_adjust(window.host.window, "280", 1), 1)
        try await window.settle()
        XCTAssertEqual(model.width, 290)
        #endif
        XCTAssertEqual(model.unread, 2)
        try await window.click(100, 170)
        XCTAssertEqual(model.readIDs, ["sample-0"])
        XCTAssertEqual(model.unread, 1)
        try await window.click(100, 115)
        XCTAssertEqual(model.created.dialog, .manage)
    }

    @MainActor func testClearHistoryRequiresConfirmation() async throws {
        for confirm in [false, true] {
            let model = CallsPreviewModel()
            let window = try await ScreenWindow(CallsTabPreview(model: model), width: 760, height: 520)
            defer { window.close() }
            let original = model.history.history
            try await window.click(282, 22)
            if confirm { try window.capture("calls-menu.png", directoryVariable: "QTSWIFTUI_CALLS_REFERENCE") }
            try await window.click(250, 62)
            if confirm { try window.capture("clear-call-history.png", directoryVariable: "QTSWIFTUI_CALLS_REFERENCE") }
            XCTAssertEqual(model.history.history, original)
            if confirm {
                try await window.click(446, 304)
                XCTAssertTrue(model.history.history.isEmpty)
                XCTAssertNil(model.details.link)
                XCTAssertEqual(model.unread, 0)
                XCTAssertFalse(model.contacts.isEmpty)
            } else {
                try await window.click(315, 304)
                XCTAssertEqual(model.history.history, original)
                XCTAssertNotNil(model.details.link)
                XCTAssertFalse(window.isVisible)
            }
        }
    }

    @MainActor func testKeyboardSnapsAndResizesTheSidebarInBothDirections() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            var saved: CGFloat = 280
            var frame = CGRect.zero
            let sidebar = NavSidebar(title: "Contacts", preferredLeftPaneWidth: 280,
                                     savePreferredLeftPaneWidth: { saved = $0 }) {
                Color.red.frame(width: 16, height: 16)
            } content: { Color.clear }
            let view = HStack(spacing: 0) {
                sidebar.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("split")) } action: { frame = $0 }
                Color.white.allowsHitTesting(false)
            }.coordinateSpace(name: "split").environment(\.layoutDirection, direction)
            let window = try await ScreenWindow(view, width: 500, height: 280, keyboard: true)
            let rtl = direction == .rightToLeft
            XCTAssertEqual(frame.width, 280)
            #if os(Linux)
            _ = qs_tab(window.host.window)
            #else
            let handle = try XCTUnwrap(window.hosting.nextKeyView)
            XCTAssertTrue(window.window.makeFirstResponder(handle))
            #endif
            func arrow(expand: Bool, shift: Bool = false) async throws {
                let left = expand == rtl
                #if os(Linux)
                let key = (shift ? "Shift+" : "") + (left ? "Left" : "Right")
                XCTAssertEqual(qs_send_key_sequence(window.host.window, key), 1)
                #else
                let code = left ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey
                let character = String(UnicodeScalar(code)!)
                var flags: NSEvent.ModifierFlags = [.function, .numericPad]
                if shift { flags.insert(.shift) }
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.window.windowNumber, context: nil,
                        characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: left ? 123 : 124))
                    window.window.sendEvent(event)
                }
                #endif
                try await window.settle()
            }
            try await arrow(expand: false)
            XCTAssertEqual(saved, 97, "\(direction)")
            XCTAssertEqual(frame.width, 97)
            try await arrow(expand: true)
            XCTAssertEqual(saved, 280, "\(direction)")
            try await arrow(expand: true, shift: true)
            XCTAssertEqual(saved, 290, "\(direction)")
            window.close()
        }
    }

    @MainActor func testSearchNewCallPickerAndStartLocalCall() async throws {
        let model = CallsPreviewModel()
        let window = try await ScreenWindow(CallsTabPreview(model: model), width: 760, height: 520)
        defer { window.close() }
        try await window.click(247, 22)
        try window.capture("new-call.png", directoryVariable: "QTSWIFTUI_CALLS_REFERENCE")
        try await window.click(114, 66)
        try await window.type("Sam")
        XCTAssertEqual(model.newCallQuery, "Sam")
        XCTAssertEqual(model.matches.map(\.conversation.title), ["Sam Rivera"])
        try await window.click(284, 145)
        XCTAssertEqual(model.outgoing, "Video call to Sam Rivera")
    }
}
