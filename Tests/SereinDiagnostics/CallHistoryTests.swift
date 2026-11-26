import XCTest
import SwiftUI
@testable import CallDiagnostics

final class CallHistoryTests: XCTestCase {
    @MainActor func testSelectJoinSearchAndFilter() async throws {
        let model = CallHistoryModel()
        var calls: [String] = []
        var links = 0
        model.onCreateLink = { links += 1 }
        model.onCall = { calls.append($0.peerId) }
        let window = try await ScreenWindow(CallHistoryPreview(model: model), width: 360, height: 418)
        defer { window.close() }
        try window.capture("call-history.png", directoryVariable: "QTSWIFTUI_HISTORY_REFERENCE")
        try await window.click(132, 64)
        XCTAssertEqual(links, 1)
        try await window.click(120, 117)
        XCTAssertEqual(model.selected, .conversation(conversationId: model.history[0].peerId, callHistoryGroup: model.history[0].group))
        let previous = model.selected
        try await window.click(306, 182)
        XCTAssertEqual(calls, [model.history[1].peerId])
        XCTAssertEqual(model.selected, previous)
        try await window.click(321, 14)
        XCTAssertTrue(model.missedOnly)
        XCTAssertEqual(model.results?.map(\.conversation.title), ["Alice", "Alex Chen"])
        try window.capture("call-history-missed.png", directoryVariable: "QTSWIFTUI_HISTORY_REFERENCE")
        try await window.click(84, 14)
        try await Task.sleep(for: .milliseconds(100))
        try await window.click(84, 14)
        try await window.type("Alex")
        XCTAssertEqual(model.query, "Alex")
        XCTAssertEqual(model.results?.map(\.conversation.title), ["Alex Chen"])
        try await window.click(125, 115)
        XCTAssertEqual(model.selected, .conversation(conversationId: model.history[5].peerId, callHistoryGroup: model.history[5].group))
    }

    @MainActor func testSelectLastCallAfterScrolling() async throws {
        let model = CallHistoryModel()
        let window = try await ScreenWindow(CallHistoryPreview(model: model), width: 360, height: 280)
        defer { window.close() }
        try await window.scroll(toEnd: true)
        try await window.click(104, 251)
        let last = try XCTUnwrap(model.history.last)
        XCTAssertEqual(model.selected, .conversation(conversationId: last.peerId, callHistoryGroup: last.group))
    }

    @MainActor func testEmptyHistoryCreateOnlyWhenAvailable() async throws {
        let model = CallHistoryModel()
        model.history = []
        var links = 0
        model.onCreateLink = { links += 1; model.creatingLink = true }
        let window = try await ScreenWindow(CallHistoryPreview(model: model), width: 360, height: 418)
        defer { window.close() }
        try await window.click(135, 64)
        try await window.click(135, 64)
        XCTAssertEqual(links, 1)
    }
}
