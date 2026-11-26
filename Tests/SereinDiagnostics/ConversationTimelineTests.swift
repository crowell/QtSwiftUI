import SwiftUI
import XCTest
@testable import CallDiagnostics

final class ConversationTimelineTests: XCTestCase {
    @MainActor func testOpenAtNewestMessageAndUseUnreadNavigation() async throws {
        let model = TimelinePreviewModel()
        var geometry: ScrollGeometry?
        var visible: [String] = []
        let view = TimelinePreview(model: model)
            .onScrollTargetVisibilityChange(idType: String.self) { visible = $0 }
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, data in geometry = data }
        let window = try await ScreenWindow(view, width: 560, height: 450, keyboard: true)
        defer { window.close() }
        let oldest = try XCTUnwrap(model.rows.first?.id)
        let newest = try XCTUnwrap(model.rows.last?.id)
        func expectViewport(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                            _ matches: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            var stableSince = ContinuousClock.now
            var previous = geometry
            repeat {
                try await window.settle()
                if !matches() || previous != geometry { stableSince = .now }
                previous = geometry
                if stableSince.duration(to: .now) >= .milliseconds(150) { break }
            } while ContinuousClock.now < deadline
            XCTAssertTrue(matches(), "\(description), offset \(String(describing: geometry?.contentOffset)), visible \(visible), near bottom \(String(describing: model.nearBottom))", file: file, line: line)
        }
        try await expectViewport("opened at newest") { model.nearBottom == true && visible.contains(newest) }
        let initial = try XCTUnwrap(geometry)
        XCTAssertGreaterThan(initial.contentOffset.y, 50)
        XCTAssertEqual(initial.contentSize.height - initial.visibleRect.maxY, 0, accuracy: 2)
        try window.capture("conversation-timeline.png", directoryVariable: "QTSWIFTUI_TIMELINE_REFERENCE")

        model.jump(to: 0)
        func showingHistory() -> Bool {
            model.nearBottom == false && visible.contains(oldest) && (geometry?.contentOffset.y ?? .infinity) < 40
        }
        try await expectViewport("scrolled to history", showingHistory)
        try window.capture("conversation-timeline-history.png", directoryVariable: "QTSWIFTUI_TIMELINE_REFERENCE")
        try await window.click(526, 370)
        try await expectViewport("jumped to unread mention") {
            model.targetIndex == model.firstUnread && (geometry?.contentOffset.y ?? 0) > 100 && visible.contains(model.rows[model.firstUnread].id)
        }
        model.jump(to: 0)
        try await expectViewport("jumped to first message", showingHistory)
        #if os(Linux)
        model.jump(to: -1)
        try await expectViewport("jumped to bottom edge") { model.nearBottom == true && visible.contains(newest) }
        model.jump(to: 0)
        try await expectViewport("returned to history", showingHistory)
        #endif
        model.jump(to: model.rows.count - 1)
        try await expectViewport("jumped to last message") { model.nearBottom == true && visible.contains(newest) }
    }
}
