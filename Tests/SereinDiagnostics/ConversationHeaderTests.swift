import SwiftUI
import XCTest
@testable import CallDiagnostics

final class ConversationHeaderTests: XCTestCase {
    @MainActor func testHeaderActionsAndMessageSearch() async throws {
        let m = ConversationPreviewModel()
        var calls: [String] = []
        m.onVideoCall = { calls.append("video") }
        m.onAudioCall = { calls.append("audio") }
        let w = try await ScreenWindow(ConversationPreview(model: m), width: 560, height: 502, keyboard: true)
        defer { w.close() }
        try await w.settle()
        try w.capture("conversation-header.png", directoryVariable: "QTSWIFTUI_HEADER_REFERENCE")
        try await w.click(396, 26)
        try await w.click(440, 26)
        XCTAssertEqual(calls, ["video", "audio"])
        try await w.click(484, 26)
        XCTAssertTrue(m.searching)
        try await w.type("tickets")
        try await w.pressReturn()
        XCTAssertEqual(m.query, "tickets")
        XCTAssertEqual(m.timeline.targetIndex, 1)
        try await w.click(484, 26)
        XCTAssertFalse(m.searching)
        try await w.click(90, 25)
        XCTAssertEqual(m.panel, .contact)
    }

    @MainActor func testConversationOverflowMenu() async throws {
        let m = ConversationPreviewModel()
        let w = try await ScreenWindow(ConversationPreview(model: m), width: 560, height: 502, keyboard: true)
        defer { w.close() }
        try await w.settle()
        let beforeMenu = w.pixel(475, 184)
        try await w.click(528, 26)
        try await w.settle()
        XCTAssertGreaterThan(w.pixel(475, 184) >> 16, (beforeMenu >> 16) + 80)
        try w.capture("conversation-header-menu.png", directoryVariable: "QTSWIFTUI_HEADER_REFERENCE")
        #if os(Linux)
        try await w.click(417, 264)
        XCTAssertTrue(m.conversation.isPinned)
        try await w.click(528, 26)
        try await w.click(417, 264)
        XCTAssertFalse(m.conversation.isPinned)
        try await w.click(528, 26)
        try await w.click(417, 157)
        XCTAssertEqual(m.panel, .media)
        #endif
    }
}
