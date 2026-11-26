import XCTest
import SwiftUI
@testable import CallDiagnostics

final class ParticipantRequestTests: XCTestCase {
    @MainActor func testParticipantActionsBeforeDismissal() async throws {
        var events: [String] = []
        let modal = JoinRequestPreview(onApprove: { events.append("approve") }, onDeny: { events.append("deny") },
                                       onAboutContact: { events.append("about") }, onClose: { events.append("close") })
        let window = try await ScreenWindow(modal, width: 520, height: 510)
        defer { window.close() }
        try window.capture("join-request.png", directoryVariable: "QTSWIFTUI_REQUEST_REFERENCE")
        try await window.click(215, 223)
        XCTAssertEqual(events, ["about"])
        try await window.click(241, 343)
        try await window.click(241, 382)
        try await window.click(389, 119)
        XCTAssertEqual(events, ["about", "approve", "close", "deny", "close", "close"])
    }
}
